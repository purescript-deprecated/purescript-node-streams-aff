-- | Asynchronous I/O with [*Node.js* Stream](https://nodejs.org/docs/latest/api/stream.html).
-- |
-- | Open file streams with
-- | [__Node.FS.Stream__](https://pursuit.purescript.org/packages/purescript-node-fs/docs/Node.FS.Stream).
-- |
-- | Open process streams with
-- | [__Node.Process__](https://pursuit.purescript.org/packages/purescript-node-process/docs/Node.Process).
-- |
-- | All I/O errors will be thrown through the `Aff` `MonadError` class
-- | instance.
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
-- | #### Results
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
-- | The `snd` element of the result `Tuple` is a `Boolean` flag which
-- | is `true` if the stream has not reached End-Of-File (and also if the stream
-- | has not errored or been destroyed.) If the flag is `false` then
-- | no more bytes will ever be produced by the stream.
-- |
-- | #### Canceller argument
-- |
-- | The reading functions suffixed with underscore take a canceller argument.
-- |
-- | The canceller argument is an action to perform in the event that
-- | this `Aff` is cancelled. For example, to destroy the stream
-- | in the event that the `Aff` is cancelled pass `Node.Stream.destroy`
-- | as the canceller.
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
-- | #### Canceller argument
-- |
-- | The writing functions suffixed with underscore take a canceller argument.
-- |
-- | The canceller argument is an action to perform in the event that
-- | this `Aff` is cancelled.
module Node.Stream.Aff
  ( readSome
  , readSome_
  , readAll
  , readAll_
  , readN
  , readN_
  , write
  , write_
  , writableClose
  )
  where

import Prelude

import Control.Monad.ST.Class (liftST)
import Control.Monad.ST.Ref as STRef
import Data.Array as Array
import Data.Array.ST as Array.ST
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import Effect (Effect, untilE)
import Effect.Aff (effectCanceler, makeAff, nonCanceler)
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Exception (catchException)
import Node.Buffer (Buffer)
import Node.Buffer as Buffer
import Node.Stream (Readable, Writable)
import Node.Stream as Stream
import Node.Stream.Aff.Internal (onceDrain, onceEnd, onceError, onceReadable, readable, writeStreamClose)


-- | Wait until there is some data available from the stream, then read it.
-- |
-- | This function is useful for streams like __stdin__ which never
-- | reach End-Of-File.
-- |
readSome
  :: forall m r
   . MonadAff m
  => Readable r
  -> m (Tuple (Array Buffer) Boolean)
readSome r = readSome_ r (\_ -> pure unit)

-- | __readSome__ with a canceller argument.
readSome_
  :: forall m r
   . MonadAff m
  => Readable r
  -> (Readable r -> Effect Unit)
  -> m (Tuple (Array Buffer) Boolean)
readSome_ r canceller = liftAff <<< makeAff $ \res -> do
  bufs <- liftST $ Array.ST.new

  removeError <- onceError r $ res <<< Left

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
        res (Right (Tuple [] false))


  ret1 <- liftST $ Array.ST.unsafeFreeze bufs
  if Array.length ret1 == 0 then do
    -- if we couldn't read anything right away, then wait until the stream is readable.
    -- “The 'readable' event will also be emitted once the end of the
    -- stream data has been reached but before the 'end' event is emitted.”
    -- We already checked the `readable` property so we don't have to check again.
    void $ onceReadable r do
      catchException (res <<< Left) do
        untilE do
          Stream.read r Nothing >>= case _ of
            Nothing -> pure true
            Just chunk -> do
              void $ liftST $ Array.ST.push chunk bufs
              pure false
        ret2 <- liftST $ Array.ST.unsafeFreeze bufs
        removeError
        readagain <- readable r
        res (Right (Tuple ret2 readagain))

    -- return what we read right away
  else do
    removeError
    readagain <- readable r
    res (Right (Tuple ret1 readagain))

  pure $ effectCanceler (canceller r)


-- | Read all data until the end of the stream. Note that __stdin__ will never end.
readAll
  :: forall m r
   . MonadAff m
  => Readable r
  -> m (Tuple (Array Buffer) Boolean)
readAll r = readAll_ r (\_ -> pure unit)

-- | __readAll__ with a canceller argument.
readAll_
  :: forall m r
   . MonadAff m
  => Readable r
  -> (Readable r -> Effect Unit)
  -> m (Tuple (Array Buffer) Boolean)
readAll_ r canceller = liftAff <<< makeAff $ \res -> do
  bufs <- liftST $ Array.ST.new

  removeError <- onceError r $ res <<< Left

  removeEnd <- onceEnd r do
    removeError
    ret <- liftST $ Array.ST.unsafeFreeze bufs
    res (Right (Tuple ret false))

  let
    cleanupRethrow err = do
      removeError
      removeEnd
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
      void $ onceReadable r do
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

  waitToRead
  pure $ effectCanceler (canceller r)


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
readN r n = readN_ r (\_ -> pure unit) n

-- | __readN__ with a canceller argument.
readN_
  :: forall m r
   . MonadAff m
  => Readable r
  -> (Readable r -> Effect Unit)
  -> Int
  -> m (Tuple (Array Buffer) Boolean)
readN_ r canceller n = liftAff <<< makeAff $ \res -> do
  redRef <- liftST $ STRef.new 0
  bufs <- liftST $ Array.ST.new

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
      res (Left err)

    -- try to read N bytes and then either return N bytes or run a continuation
    tryToRead continuation = do
      catchException cleanupRethrow do
        untilE do
          red <- liftST $ STRef.read redRef
          -- https://nodejs.org/docs/latest-v15.x/api/stream.html#stream_readable_read_size
          -- “If size bytes are not available to be read, null will be returned
          -- unless the stream has ended, in which case all of the data remaining
          -- in the internal buffer will be returned.”
          Stream.read r (Just (n-red)) >>= case _ of
            Nothing -> pure true
            Just chunk -> do
              _ <- liftST $ Array.ST.push chunk bufs
              s <- Buffer.size chunk
              red' <- liftST $ STRef.modify (_+s) redRef
              if red' >= n then
                pure true
              else
                pure false
        red <- liftST $ STRef.read redRef
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
      void $ onceReadable r do
        tryToRead waitToRead
  waitToRead unit

  pure $ effectCanceler (canceller r)


-- | Write to a stream.
-- |
-- | Will complete after the data is flushed to the stream.
write
  :: forall m w
   . MonadAff m
  => Writable w
  -> Array Buffer
  -> m Unit
write w bs = write_ w (\_ -> pure unit) bs

-- | __write__ with a canceller argument.
write_
  :: forall m w
   . MonadAff m
  => Writable w
  -> (Writable w -> Effect Unit)
  -> Array Buffer
  -> m Unit
write_ w canceller bs = liftAff <<< makeAff $ \res -> do
  bufs <- liftST $ Array.ST.thaw bs

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
              isLast <- liftST $ (_==0) <$> Array.length <$> Array.ST.unsafeFreeze bufs
              nobackpressure <- Stream.write w chunk (if isLast then callbackLast else callback)
              if nobackpressure then do
                pure false
              else do
                _ <- onceDrain w oneWrite
                pure true

  oneWrite
  pure $ effectCanceler (canceller w)

-- | Close a `Writable` file stream.
-- |
-- | Will complete after the file stream is closed.
writableClose
  :: forall m w
   . MonadAff m
  => Writable w
  -> m Unit
writableClose w = liftAff <<< makeAff $ \res -> do

  removeError <- onceError w $ res <<< Left

  writeStreamClose w do
    removeError
    res (Right unit)

  pure nonCanceler
