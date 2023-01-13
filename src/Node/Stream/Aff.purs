-- | Asynchronous I/O with the [*Node.js* Stream API](https://nodejs.org/docs/latest/api/stream.html).
-- |
-- | Open __file streams__ with
-- | [__Node.FS.Stream__](https://pursuit.purescript.org/packages/purescript-node-fs/docs/Node.FS.Stream).
-- |
-- | Open __process streams__ with
-- | [__Node.Process__](https://pursuit.purescript.org/packages/purescript-node-process/docs/Node.Process).
-- |
-- | All __I/O errors__ will be thrown through the `Aff` `MonadError` class
-- | instance.
-- |
-- | `Aff` __cancellation__ will clean up all *Node.js* event listeners.
-- |
-- | All of these `Aff` functions will prevent the *Node.js* __event loop__ from
-- | exiting until the `Aff` function completes.
-- |
-- | ## Reading
-- |
-- | #### Implementation
-- |
-- | The reading functions in this module all operate on a `Readable` stream
-- | in
-- | [“paused mode”](https://nodejs.org/docs/latest/api/stream.html#stream_two_reading_modes).
-- |
-- | Internally the reading functions use the
-- | [`readable.read([size])`](https://nodejs.org/docs/latest/api/stream.html#readablereadsize)
-- | function and are subject to the caveats of that function.
-- |
-- | #### Result Buffers
-- |
-- | The result of a reading function may be chunked into more than one `Buffer`.
-- | The `buffers` element of the result is an `Array Buffer` of what
-- | was read.
-- | To concatenate the result into a single `Buffer`, use
-- | `Node.Buffer.concat :: Array Buffer -> Buffer`.
-- |
-- | ```
-- | input :: Buffer <- liftEffect <<< concat <<< (_.buffers) =<< readSome stdin
-- | ```
-- |
-- | To calculate the number of bytes read, use
-- | `Node.Buffer.size :: Buffer -> m Int`.
-- |
-- | ```
-- | {buffers} :: Array Buffer <- readSome stdin
-- | bytesRead :: Int
-- |     <- liftEffect $ Array.foldM (\a b -> (a+_) <$> size b) 0 buffers
-- | ```
-- |
-- | #### Result `readagain` flag
-- |
-- | The `readagain` field of the result is a `Boolean` flag which
-- | is `true` if the stream has not reached End-Of-File (and also if the stream
-- | has not errored or been destroyed), so we know we can read again.
-- | If the flag is `false` then
-- | no more bytes will ever be produced by the stream.
-- |
-- | Reading from an ended, closed, errored, or destroyed stream
-- | will complete immediately with `{buffers:[], readagain:false}`.
-- |
-- | The `readagain` flag will give the same answer as a call to `Internal.readable`.
-- |
-- | ## Writing
-- |
-- | #### Implementation
-- |
-- | The writing functions in this module all operate on a `Writeable` stream.
-- |
-- | Internally the writing functions will call the
-- | [`writable.write(chunk[, encoding][, callback])`](https://nodejs.org/docs/latest/api/stream.html#writablewritechunk-encoding-callback)
-- | function on each of the `Buffer`s,
-- | and will asychronously wait if there is “backpressure” from the stream.
-- |
-- | The writing functions will complete after all the data is flushed to the
-- | stream.
-- |
-- | If a write fails then it will `throwError` in the `Aff`.
module Node.Stream.Aff
  ( readSome
  , readAll
  , readN
  , write
  , end
  , toStringUTF8
  , fromStringUTF8
  ) where

import Prelude

import Control.Monad.ST.Class (liftST)
import Data.Array as Array
import Data.Array.ST as Array.ST
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect, untilE)
import Effect.Aff (effectCanceler, error, makeAff, nonCanceler)
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Class (class MonadEffect, liftEffect)
import Effect.Class.Console as Console
import Effect.Exception (catchException)
import Effect.Ref as Ref
import Node.Buffer (Buffer)
import Node.Buffer as Buffer
import Node.Encoding as Encoding
import Node.Stream (Readable, Writable)
import Node.Stream as Stream
import Node.Stream.Aff.Internal (onceDrain, onceEnd, onceError, onceReadable, readable, writable)

-- | Wait until there is some data available from the stream, then read it.
-- |
-- | This function is useful for streams like __stdin__ which never
-- | reach End-Of-File.
readSome
  :: forall m r
   . MonadAff m
  => Readable r
  -> m {buffers :: Array Buffer, readagain :: Boolean}
readSome r = liftAff <<< makeAff $ \complete -> do
  bufs <- liftST $ Array.ST.new

  removeError <- onceError r \err -> complete (Left err)

  removeEnd <- onceEnd r do
    removeError
    ret <- liftST $ Array.ST.unsafeFreeze bufs
    complete (Right {buffers:ret, readagain:false})

  let
    cleanupRethrow err = do
      removeError
      removeEnd
      complete (Left err)
      pure nonCanceler

  catchException cleanupRethrow do
    ifM (readable r)
      do
        -- try to read right away.
        untilE do
          Stream.read r Nothing >>= case _ of
            Nothing -> pure true
            Just chunk -> do
              void $ liftST $ Array.ST.push chunk bufs
              pure false

        ret1 <- liftST $ Array.ST.unsafeFreeze bufs
        readagain <- readable r
        if readagain && Array.length ret1 == 0 then do
          -- if still readable and we couldn't read anything right away,
          -- then wait for the readable event.
          -- “The 'readable' event will also be emitted once the end of the
          -- stream data has been reached but before the 'end' event is emitted.”
          -- if not readable then this was a zero-length Readable stream.
          -- https://nodejs.org/api/stream.html#event-readable
          removeReadable <- onceReadable r do
            untilE do
              Stream.read r Nothing >>= case _ of
                Nothing -> pure true
                Just chunk -> do
                  void $ liftST $ Array.ST.push chunk bufs
                  pure false
            ret2 <- liftST $ Array.ST.unsafeFreeze bufs
            removeError
            removeEnd
            readagain2 <- readable r
            complete (Right {buffers:ret2, readagain:readagain2})
          -- canceller might by called while waiting for `onceReadable`
          pure $ effectCanceler do
            removeError
            removeEnd
            removeReadable
        -- else return what we read right away
        else do
          removeError
          removeEnd
          complete (Right {buffers: ret1, readagain})
          pure nonCanceler
      do
        removeError
        removeEnd
        complete (Right { buffers: [], readagain: false})
        pure nonCanceler

-- | Read all data until the end of the stream.
-- |
-- | Note that __stdin__ will never end.
readAll
  :: forall m r
   . MonadAff m
  => Readable r
  -> m {buffers :: Array Buffer, readagain :: Boolean}
readAll r = liftAff <<< makeAff $ \complete -> do
  bufs <- liftST $ Array.ST.new
  removeReadable <- Ref.new (pure unit :: Effect Unit)

  removeError <- onceError r \err -> do
    join $ Ref.read removeReadable
    complete (Left err)

  removeEnd <- onceEnd r do
    removeError
    ret <- liftST $ Array.ST.unsafeFreeze bufs
    complete (Right {buffers: ret, readagain: false})

  let
    cleanupRethrow err = do
      removeError
      removeEnd
      join $ Ref.read removeReadable
      complete (Left err)
      pure nonCanceler

  -- try to read right away.
  catchException cleanupRethrow do
    ifM (readable r)
      do
        untilE do
          Stream.read r Nothing >>= case _ of
            Nothing -> pure true
            Just chunk -> do
              void $ liftST $ Array.ST.push chunk bufs
              pure false

        -- then wait for the stream to be readable until the stream has ended.
        let
          waitToRead = do
            removeReadable' <- onceReadable r do
              -- “The 'readable' event will also be emitted once the end of the
              -- stream data has been reached but before the 'end' event is emitted.”
              untilE do
                Stream.read r Nothing >>= case _ of
                  Nothing -> pure true
                  Just chunk -> do
                    _ <- liftST $ Array.ST.push chunk bufs
                    pure false
              waitToRead -- this is not recursion
            Ref.write removeReadable' removeReadable

        waitToRead
        -- canceller might by called while waiting for `onceReadable`
        pure $ effectCanceler do
          removeError
          removeEnd
          join $ Ref.read removeReadable

      do
        removeError
        removeEnd
        complete (Right {buffers: [], readagain: false})
        pure nonCanceler

-- | Wait for *N* bytes to become available from the stream.
-- |
-- | If more than *N* bytes are available on the stream, then
-- | completes with *N* bytes and leaves the rest in the stream’s internal buffer.
-- |
-- | If the end of the stream is reached before *N* bytes are available,
-- | then completes with less than *N* bytes.
readN
  :: forall m r
   . MonadAff m
  => Readable r
  -> Int
  -> m { buffers :: Array Buffer, readagain :: Boolean }
readN r n = liftAff <<< makeAff $ \complete ->
  if n < 0 then complete (Left $ error "read bytes must be > 0") *> pure nonCanceler
  else do
    redRef <- Ref.new 0
    bufs <- liftST $ Array.ST.new
    removeReadable <- Ref.new (pure unit :: Effect Unit)

    -- TODO on error, we're not calling removeEnd... maybe that's fine?
    removeError <- onceError r \err -> do
      join $ Ref.read removeReadable
      complete (Left err)

    removeEnd <- onceEnd r do
      removeError
      ret <- liftST $ Array.ST.unsafeFreeze bufs
      complete (Right {buffers:ret, readagain: false})

    let
      cleanupRethrow err = do
        removeError
        removeEnd
        join $ Ref.read removeReadable
        complete (Left err)
        pure nonCanceler

      -- try to read N bytes and then either return N bytes or run a continuation
      tryToRead continuation = do
        untilE do
          red <- Ref.read redRef
          -- https://nodejs.org/docs/latest-v15.x/api/stream.html#stream_readable_read_size
          -- “If size bytes are not available to be read, null will be returned
          -- unless the stream has ended, in which case all of the data remaining
          -- in the internal buffer will be returned.”
          Stream.read r (Just (n - red)) >>= case _ of
            Nothing -> pure true
            Just chunk -> do
              _ <- liftST $ Array.ST.push chunk bufs
              s <- Buffer.size chunk
              red' <- Ref.modify (_ + s) redRef
              if red' >= n then
                pure true
              else
                pure false
        red <- Ref.read redRef
        if red >= n then do
          removeError
          removeEnd
          ret <- liftST $ Array.ST.unsafeFreeze bufs
          readagain <- readable r
          complete (Right {buffers:ret, readagain})
        else
          continuation unit

      -- if there were not enough bytes right away, then wait for bytes to come in.
      waitToRead _ = do
        removeReadable' <- onceReadable r do
          tryToRead waitToRead -- not recursion
        Ref.write removeReadable' removeReadable

    catchException cleanupRethrow do
      -- try to read right away.
      ifM (readable r)
        do
          tryToRead waitToRead
          -- canceller might by called while waiting for `onceReadable`
          pure $ effectCanceler do
            removeError
            removeEnd
            join $ Ref.read removeReadable
        do
          removeError
          removeEnd
          -- If the stream is not readable should that be a fail?
          -- Maybe we should distinguish between ended (not fail) and error (fail)
          complete (Right {buffers: [], readagain: false})
          pure nonCanceler

-- | Write to a stream.
-- |
-- | Will complete after the data is flushed to the stream.
write
  :: forall m w
   . MonadAff m
  => Writable w
  -> Array Buffer
  -> m Unit
write w bs = liftAff <<< makeAff $ \complete -> do
  removeDrain <- Ref.new (pure unit :: Effect Unit)

  let
    oneWrite bufs = do
      -- untilE do
        -- Console.log "untilE"
        -- chunkMay <- liftST $ Array.ST.shift bufs
        case Array.uncons bufs of
          Nothing -> do
            complete (Right unit)
          Just {head,tail} -> do
            -- “write … calls the supplied callback once the data has been fully handled.
            -- If an error occurs, the callback will be called with the error
            -- as its first argument. The callback is called asynchronously and
            -- before 'error' is emitted.”
            nobackpressure <- Stream.write w head $ case _ of
              Nothing -> do
                pure unit
              Just err -> do
                -- Console.log $ "flush error " <> show err
                complete (Left err)

            -- Console.log $ "write nobackpressure " <> show nobackpressure <> " len " <> show (Array.length tail)

            if nobackpressure
              then do
                -- Console.log "write complete"
                oneWrite tail -- recursion
              else do
                -- Console.log "write backpressure"
                removeDrain' <- onceDrain w (oneWrite tail)
                Ref.write removeDrain' removeDrain


  oneWrite bs

  -- canceller might be called while waiting for `onceDrain`
  pure $ effectCanceler do
    join $ Ref.read removeDrain

-- | Signal that no more data will be written to the `Writable`. Will complete
-- | after all data is written and flushed.
-- |
-- | When the `Writable` is an [__fs.WriteStream__](https://nodejs.org/api/fs.html#class-fswritestream)
-- | then this will close the file descriptor because
-- |
-- | > “If `autoClose` is set to true (default behavior) on `'error'`
-- | > or `'finish'` the file descriptor will be closed automatically.”
end
  :: forall m w
   . MonadAff m
  => Writable w
  -> m Unit
end w = liftAff <<< makeAff $ \complete -> do
  Stream.end w $ case _ of
    Nothing -> complete (Right unit)
    Just err -> complete (Left err)
  pure nonCanceler

-- | Concatenate an `Array` of UTF-8 encoded `Buffer`s into a `String`.
toStringUTF8 :: forall m. MonadEffect m => Array Buffer -> m String
toStringUTF8 bs = liftEffect $ Buffer.toString Encoding.UTF8 =<< Buffer.concat bs

-- | Encode a `String` as an `Array` containing one UTF-8 encoded `Buffer`.
fromStringUTF8 :: forall m. MonadEffect m => String -> m (Array Buffer)
fromStringUTF8 s = liftEffect $ map pure $ Buffer.fromString s Encoding.UTF8
