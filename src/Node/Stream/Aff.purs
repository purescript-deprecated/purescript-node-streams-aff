-- | Asynchronous I/O with *Node.js* streams.
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
-- | Each reading function also returns a `Boolean` flag which is `true`
-- | if the end of the stream was reached.
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
-- | its end. If any one of these reading functions is called on a stream
-- | which has reached its end, then it will never return.
-- |
-- | ## Writing
-- |
-- | The writing functions in this module all operate on a `Writeable` stream.
-- |
-- | The writing functions will finish after the data is flushed.
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
  )

where

-- questions:
--
-- cancellation?
-- launchAff_ will wait for writes to end?
-- writes will be flushed?

import Prelude

import Control.Monad.ST.Class (liftST)
import Control.Monad.ST.Ref as STRef
import Data.Array.ST as Array.ST
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect, untilE)
import Effect.Aff (effectCanceler, makeAff)
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Exception (catchException)
import Node.Buffer (Buffer)
import Node.Buffer as Buffer
import Node.Stream (Readable, Writable)
import Node.Stream as Stream
import Node.Stream.Aff.Internal (onceDrain, onceEnd, onceReadable)


-- | Wait until there is some data available from the stream.
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

  onceReadable r do
    catchException (res <<< Left) do
      bufs <- liftST $ Array.ST.new
      untilE do
        Stream.read r Nothing >>= case _ of
          -- “The 'readable' event will also be emitted once the end of the
          -- stream data has been reached but before the 'end' event is emitted.”
          Nothing -> pure true
          Just chunk -> do
            void $ liftST $ Array.ST.push chunk bufs
            pure false
      ret <- liftST $ Array.ST.unsafeFreeze bufs
      res $ Right ret

  pure $ effectCanceler (canceller r)


-- | Read all data until the end of a stream.
-- |
-- | After this action finishes, `readableEnded` will be `true`
-- | for this stream.
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

  onceEnd r do
    ret <- liftST $ Array.ST.unsafeFreeze bufs
    res $ Right ret

  let
    oneRead = do
      onceReadable r do
        -- “The 'readable' event will also be emitted once the end of the
        -- stream data has been reached but before the 'end' event is emitted.”
        catchException (res <<< Left) do
          untilE do
            Stream.read r Nothing >>= case _ of
              Nothing -> pure true
              Just chunk -> do
                _ <- liftST $ Array.ST.push chunk bufs
                pure false
          oneRead -- this is not recursion

  oneRead
  pure $ effectCanceler (canceller r)


-- | Wait for *N* bytes to become available from the stream.
-- |
-- | If more than *N* bytes are available on the stream, then
-- | only return *N* bytes and leave the rest in the internal buffer.
-- |
-- | If the end of the stream is reached then returns all bytes read so far
-- | and the `Boolean` return value `true`.
-- |
-- | Note: if there are 10 bytes in the stream, and we `readN s 10`, then
-- | the end flag Boolean will be ? in the result?
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
  red <- liftST $ STRef.new 0
  bufs <- liftST $ Array.ST.new

  onceEnd r do
    ret <- liftST $ Array.ST.unsafeFreeze bufs
    res $ Right ret

  let
    oneRead = do
      onceReadable r do
        catchException (res <<< Left) do
          untilE do
            want <- map (n-_) $ liftST $ STRef.read red
            -- https://nodejs.org/docs/latest-v15.x/api/stream.html#stream_readable_read_size
            -- “If size bytes are not available to be read, null will be returned
            -- unless the stream has ended, in which case all of the data remaining
            -- in the internal buffer will be returned.”
            Stream.read r (Just want) >>= case _ of
              Nothing -> pure true
              Just chunk -> do
                _ <- liftST $ Array.ST.push chunk bufs
                s <- Buffer.size chunk
                red' <- liftST $ STRef.modify (_+s) red
                if red' >= n then
                  pure true
                else
                  pure false
          m <- liftST $ STRef.read red
          if m >= n then do
            ret <- liftST $ Array.ST.unsafeFreeze bufs
            res $ Right ret
          else
            oneRead -- this is not recursion

  oneRead
  pure $ effectCanceler (canceller r)


-- | Write to a stream. Will finish after the data is flushed to the stream.
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

  let
    callback = case _ of
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
              backpressure <- Stream.write w chunk callback
              if backpressure then do
                pure false
              else do
                -- TODO there is a race condition, what if we miss the drain event?
                onceDrain w oneWrite
                pure true

  oneWrite
  pure $ effectCanceler (canceller w)
