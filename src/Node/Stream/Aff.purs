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
-- | The `fst` element of the result `Tuple` is an `Array Buffer` of what
-- | was read.
-- | To concatenate the result into a single `Buffer`, use
-- | `Node.Buffer.concat :: Array Buffer -> Buffer`.
-- |
-- | ```
-- | input :: Buffer <- liftEffect <<< concat <<< fst =<< readSome stdin
-- | ```
-- |
-- | To calculate the number of bytes read, use
-- | `Node.Buffer.size :: Buffer -> m Int`.
-- |
-- | ```
-- | Tuple inputs _ :: Array Buffer <- readSome stdin
-- | bytesRead :: Int
-- |     <- liftEffect $ Array.foldM (\a b -> (a+_) <$> size b) 0 inputs
-- | ```
-- |
-- | #### Result `readagain` flag
-- |
-- | The `snd` element of the result `Tuple` is a `Boolean` flag which
-- | is `true` if the stream has not reached End-Of-File (and also if the stream
-- | has not errored or been destroyed), so we know we can read again.
-- | If the flag is `false` then
-- | no more bytes will ever be produced by the stream.
-- |
-- | Reading from an ended, closed, errored, or destroyed stream
-- | will complete immediately with `Tuple [] false`.
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
import Data.Tuple (Tuple(..))
import Effect (Effect, untilE)
import Effect.Aff (effectCanceler, makeAff, nonCanceler)
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Class (class MonadEffect, liftEffect)
import Effect.Exception (catchException)
import Effect.Ref as Ref
import Node.Buffer (Buffer)
import Node.Buffer as Buffer
import Node.Encoding as Encoding
import Node.Stream (Readable, Writable)
import Node.Stream as Stream
import Node.Stream.Aff.Internal (onceDrain, onceEnd, onceError, onceReadable, readable)

-- | Wait until there is some data available from the stream, then read it.
-- |
-- | This function is useful for streams like __stdin__ which never
-- | reach End-Of-File.
readSome
  :: forall m r
   . MonadAff m
  => Readable r
  -> m (Tuple (Array Buffer) Boolean)
readSome r = liftAff <<< makeAff $ \res -> do
  bufs <- liftST $ Array.ST.new

  removeError <- onceError r $ res <<< Left

  removeEnd <- onceEnd r do
    removeError
    ret <- liftST $ Array.ST.unsafeFreeze bufs
    res (Right (Tuple ret false))

  -- try to read right away.
  catchException (res <<< Left) do
    ifM (readable r)
      do
        untilE do
          Stream.read r Nothing >>= case _ of
            Nothing -> pure true
            Just chunk -> do
              void $ liftST $ Array.ST.push chunk bufs
              pure false
      do
        removeError
        removeEnd
        res (Right (Tuple [] false))

  ret1 <- liftST $ Array.ST.unsafeFreeze bufs
  readagain <- readable r
  removeReadable <-
    if readagain && Array.length ret1 == 0 then do
      -- if still readable and we couldn't read anything right away,
      -- then wait for the readable event.
      -- “The 'readable' event will also be emitted once the end of the
      -- stream data has been reached but before the 'end' event is emitted.”
      -- if not readable then this was a zero-length Readable stream.
      -- https://nodejs.org/api/stream.html#event-readable
      onceReadable r do
        catchException (res <<< Left) do
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
          res (Right (Tuple ret2 readagain2))

    -- return what we read right away
    else do
      removeError
      removeEnd
      res (Right (Tuple ret1 readagain))
      pure (pure unit) -- dummy canceller

  -- canceller might by called while waiting for `onceReadable`
  pure $ effectCanceler do
    removeError
    removeEnd
    removeReadable

-- | Read all data until the end of the stream.
-- |
-- | Note that __stdin__ will never end.
readAll
  :: forall m r
   . MonadAff m
  => Readable r
  -> m (Tuple (Array Buffer) Boolean)
readAll r = liftAff <<< makeAff $ \res -> do
  bufs <- liftST $ Array.ST.new
  removeReadable <- Ref.new (pure unit :: Effect Unit)

  removeError <- onceError r $ res <<< Left

  removeEnd <- onceEnd r do
    removeError
    ret <- liftST $ Array.ST.unsafeFreeze bufs
    res (Right (Tuple ret false))

  let
    cleanupRethrow err = do
      removeError
      removeEnd
      join $ Ref.read removeReadable
      res (Left err)

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
      do
        removeError
        removeEnd
        res (Right (Tuple [] false))

  -- then wait for the stream to be readable until the stream has ended.
  let
    waitToRead = do
      removeReadable' <- onceReadable r do
        -- “The 'readable' event will also be emitted once the end of the
        -- stream data has been reached but before the 'end' event is emitted.”
        catchException cleanupRethrow do
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
  -> m (Tuple (Array Buffer) Boolean)
readN r n = liftAff <<< makeAff $ \res -> do
  redRef <- Ref.new 0
  bufs <- liftST $ Array.ST.new
  removeReadable <- Ref.new (pure unit :: Effect Unit)

  -- TODO on error, we're not calling removeEnd...
  removeError <- onceError r $ res <<< Left

  -- The `end` event is sometimes raised after we have read N bytes, even
  -- if there are more bytes in the stream?
  removeEnd <- onceEnd r do
    removeError
    ret <- liftST $ Array.ST.unsafeFreeze bufs
    res (Right (Tuple ret false))

  let
    cleanupRethrow err = do
      removeError
      removeEnd
      join $ Ref.read removeReadable
      res (Left err)

    -- try to read N bytes and then either return N bytes or run a continuation
    tryToRead continuation = do
      catchException cleanupRethrow do
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
          res (Right (Tuple ret readagain))
        else
          continuation unit

  -- try to read right away.
  ifM (readable r)
    do
      tryToRead (\_ -> pure unit)
    do
      removeError
      removeEnd
      res (Right (Tuple [] false))

  -- if there were not enough bytes right away, then wait for bytes to come in.
  let
    waitToRead _ = do
      removeReadable' <- onceReadable r do
        tryToRead waitToRead
      Ref.write removeReadable' removeReadable
  waitToRead unit

  -- canceller might by called while waiting for `onceReadable`
  pure $ effectCanceler do
    removeError
    removeEnd
    join $ Ref.read removeReadable

-- | Write to a stream.
-- |
-- | Will complete after the data is flushed to the stream.
write
  :: forall m w
   . MonadAff m
  => Writable w
  -> Array Buffer
  -> m Unit
write w bs = liftAff <<< makeAff $ \res -> do
  bufs <- liftST $ Array.ST.thaw bs
  removeDrain <- Ref.new (pure unit :: Effect Unit)

  removeError <- onceError w $ res <<< Left

  let
    callback = case _ of
      Just err -> res (Left err)
      Nothing -> pure unit

    callbackLast = case _ of
      Just err -> do
        removeError
        res (Left err)
      Nothing -> do
        removeError
        res (Right unit)

    oneWrite = do
      catchException (res <<< Left) do
        untilE do
          chunkMay <- liftST $ Array.ST.shift bufs
          case chunkMay of
            Nothing -> do
              pure true
            Just chunk -> do
              isLast <- liftST $ (_ == 0) <$> Array.length <$> Array.ST.unsafeFreeze bufs
              nobackpressure <- Stream.write w chunk (if isLast then callbackLast else callback)
              if nobackpressure then do
                pure false
              else do
                removeDrain' <- onceDrain w oneWrite
                void $ Ref.write removeDrain' removeDrain
                pure true

  oneWrite

  -- canceller might be called while waiting for `onceDrain`
  pure $ effectCanceler do
    removeError
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
end w = liftAff <<< makeAff $ \res -> do
  Stream.end w $ case _ of
    Nothing -> res (Right unit)
    Just err -> res (Left err)
  pure $ nonCanceler

-- | Concatenate an `Array` of UTF-8 encoded `Buffer`s into a `String`.
toStringUTF8 :: forall m. MonadEffect m => Array Buffer -> m String
toStringUTF8 bs = liftEffect $ Buffer.toString Encoding.UTF8 =<< Buffer.concat bs

-- | Encode a `String` as an `Array` containing one UTF-8 encoded `Buffer`.
fromStringUTF8 :: forall m. MonadEffect m => String -> m (Array Buffer)
fromStringUTF8 s = liftEffect $ map pure $ Buffer.fromString s Encoding.UTF8
