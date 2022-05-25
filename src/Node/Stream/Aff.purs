-- | Asynchronous I/O with *Node.js* streams.
-- |
-- | Open file streams with
-- | [__Node.FS.Stream__](https://pursuit.purescript.org/packages/purescript-node-fs/docs/Node.FS.Stream).
-- |
-- | Open process streams with
-- | [__Node.Process__](https://pursuit.purescript.org/packages/purescript-node-process/docs/Node.Process).
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
-- | To concatenate the result into a single `Buffer`, use
-- | `Node.Buffer.concat :: Array Buffer -> Buffer`.
-- |
-- | ```
-- | input :: Buffer <- liftEffect <<< concat =<< readSome stdin
-- | ```
-- |
-- | To calculate the number of bytes read, use
-- | `Node.Buffer.size :: Buffer -> m Int`.
-- |
-- | ```
-- | inputs :: Array Buffer <- readSome stdin
-- | bytesRead :: Int
-- |     <- liftEffect $ Array.foldM (\a b -> (a+_) <$> size b) 0 inputs
-- | ```
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
-- | #### EOF
-- |
-- | There doesn’t seem to be any way to reliably detect when a stream has reached
-- | its end? If any one of these reading functions is called on a stream
-- | which has already reached its end, then the reading function will never complete.
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
-- | asychronously waiting if there is backpressure from the stream.
-- |
-- | The writing functions will complete after the data is flushed to the
-- | stream.
-- |
-- | #### Canceller argument
-- |
-- | The writing functions suffixed with underscore take a canceller argument.
-- |
-- | The canceller argument is an action to perform in the event that
-- | this `Aff` is cancelled.
module Node.Stream.Aff
  ( module Reexport
  , readAll
  , readAll_
  , readN
  , readN_
  , readSome
  , readSome_
  , write
  , write'
  , write_
  , noExit
  )
  where

import Prelude

import Control.Monad.ST.Class (liftST)
import Control.Monad.ST.Ref as STRef
import Data.Array as Array
import Data.Array.ST as Array.ST
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect, untilE)
import Effect.Aff (effectCanceler, makeAff)
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Exception (catchException)
import Node.Buffer (Buffer)
import Node.Buffer as Buffer
import Node.Encoding (Encoding(..))
import Node.Stream (Readable, Writable)
import Node.Stream as Stream
import Node.Stream.Aff.Internal (clearInterval, hasRef, onceReadable, setInterval)
import Node.Stream.Aff.Internal (onceDrain, onceEnd, onceError, onceReadable)
import Node.Stream.Aff.Internal (unbuffer) as Reexport


-- | Wait until there is some data available from the stream.
-- |
-- | This function is not currently very useful because there is no way to
-- | know when a stream has already reached its end, and if this
-- | function is called after the stream has ended then the call will
-- | never complete. So we can `readSome` one time and it will complete, but
-- | then we don’t know if the next call to `readSome` will complete.
readSome
  :: forall m r
   . MonadAff m
  => Readable r
  -> m (Array Buffer)
readSome r = readSome_ r (\_ -> pure unit)


-- | __readSome__ with a canceller argument.
readSome_
  :: forall m r
   . MonadAff m
  => Readable r
  -> (Readable r -> Effect Unit)
  -> m (Array Buffer)
readSome_ r canceller = liftAff <<< makeAff $ \res -> do
  bufs <- liftST $ Array.ST.new

  removeError <- onceError r $ res <<< Left

  -- try to read right away.
  catchException (res <<< Left) do
    untilE do
      Stream.read r Nothing >>= case _ of
        Nothing -> pure true
        Just chunk -> do
          void $ liftST $ Array.ST.push chunk bufs
          pure false

  ret1 <- liftST $ Array.ST.unsafeFreeze bufs
  if Array.length ret1 == 0 then do
    -- if we couldn't read anything right away, then wait until the stream is readable.
    -- “The 'readable' event will also be emitted once the end of the
    -- stream data has been reached but before the 'end' event is emitted.”
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
        res (Right ret2)

    -- return what we read right away
  else do
    removeError
    res (Right ret1)

  pure $ effectCanceler (canceller r)


-- | Read all data until the end of the stream. Note that `stdin` will never end.
readAll
  :: forall m r
   . MonadAff m
  => Readable r
  -> m (Array Buffer)
readAll r = readAll_ r (\_ -> pure unit)


-- | __readAll__ with a canceller argument.
readAll_
  :: forall m r
   . MonadAff m
  => Readable r
  -> (Readable r -> Effect Unit)
  -> m (Array Buffer)
readAll_ r canceller = liftAff <<< makeAff $ \res -> do
  bufs <- liftST $ Array.ST.new

  removeError <- onceError r $ res <<< Left

  removeEnd <- onceEnd r do
    removeError
    ret <- liftST $ Array.ST.unsafeFreeze bufs
    res (Right ret)

  let
    cleanupRethrow err = do
      removeError
      removeEnd
      res (Left err)

  -- try to read right away.
  catchException cleanupRethrow do
    untilE do
      Stream.read r Nothing >>= case _ of
        Nothing -> pure true
        Just chunk -> do
          void $ liftST $ Array.ST.push chunk bufs
          pure false

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
  -> m (Array Buffer)
readN r n = readN_ r (\_ -> pure unit) n

-- | __readN__ with a canceller argument.
readN_
  :: forall m r
   . MonadAff m
  => Readable r
  -> (Readable r -> Effect Unit)
  -> Int
  -> m (Array Buffer)
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
    res (Right ret)

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
          res (Right ret)
        else
          continuation unit

  -- try to read right away.
  tryToRead (\_ -> pure unit)

  -- if there were not enough bytes right away, then wait for bytes to come in.
  let
    waitToRead _ = do
      void $ onceReadable r do
        tryToRead waitToRead
  waitToRead unit

  -- fix \waitToRead -> do
  --   void $ onceReadable r do
  --     tryToRead waitToRead
  -- let
  --   waitToRead = do
  --     void $ onceReadable r do
  --       tryToRead waitToRead -- this is not recursion


  -- let
  --   oneRead = do
  --     void $ onceReadable r do
  --       catchException cleanupRethrow do
  --         untilE do
  --           red <- liftST $ STRef.read redRef
  --           -- https://nodejs.org/docs/latest-v15.x/api/stream.html#stream_readable_read_size
  --           -- “If size bytes are not available to be read, null will be returned
  --           -- unless the stream has ended, in which case all of the data remaining
  --           -- in the internal buffer will be returned.”
  --           Stream.read r (Just (n-red)) >>= case _ of
  --             Nothing -> pure true
  --             Just chunk -> do
  --               _ <- liftST $ Array.ST.push chunk bufs
  --               s <- Buffer.size chunk
  --               red' <- liftST $ STRef.modify (_+s) redRef
  --               if red' >= n then
  --                 pure true
  --               else
  --                 pure false
  --         red <- liftST $ STRef.read redRef
  --         if red >= n then do
  --           ret <- liftST $ Array.ST.unsafeFreeze bufs
  --           res $ Right ret
  --         else
  --           oneRead -- this is not recursion

  -- waitToRead
  pure $ effectCanceler (canceller r)


-- | Write to a stream. Will complete after the data is flushed to the stream.
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
      Just err -> res $ Left err
      Nothing -> pure unit

    callbackLast = case _ of
      Just err -> res $ Left err
      Nothing -> res $ Right unit

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
  removeError
  pure $ effectCanceler (canceller w)


-- TODO Remove all listeners before returning
-- https://nodejs.org/api/events.html#emitterremovelistenereventname-listener
--
-- (node:483527) MaxListenersExceededWarning: Possible EventEmitter memory leak detected. 11 end listeners added to [Socket]. Use emitter.setMaxListeners() to increase limit
-- (Use `node --trace-warnings ...` to show where the warning was created)
--
-- Buffer.size 28
--
-- (node:483527) MaxListenersExceededWarning: Possible EventEmitter memory leak detected. 11 error listeners added to [Socket]. Use emitter.setMaxListeners() to increase limit



-- | https://github.com/purescript-contrib/pulp/blob/79dd954c86a5adc57051cad127c8888756f680a6/src/Pulp/System/Stream.purs#L41
write' :: forall m w. MonadAff m => Writable w -> String -> m Unit
write' stream str = liftAff $ makeAff (\cb -> mempty <* void (Stream.writeString stream UTF8 str (\_ -> cb (Right unit))))


-- | Prevent Node.js from exiting while an `Effect` is running.
noExit :: Effect (Effect Unit)
-- noExit :: forall a. (Effect unit -> Effect a) -> Effect a
noExit = do
  -- Idea from
  -- https://stackoverflow.com/a/62869265/187223

  id <- setInterval 1000 (pure unit)
  pure (clearInterval id)

  -- id <- setInterval 1 (Console.log "INTERVAL\n")
  -- h <- hasRef id
  -- Console.log $ "TIMEOUT " <> show h
  -- pure do
  --   Console.log "INTERVAL END\n"
  --   clearInterval id

  -- id <- setTimeout 1 do
  --   Console.log "TIMEOUT\n"