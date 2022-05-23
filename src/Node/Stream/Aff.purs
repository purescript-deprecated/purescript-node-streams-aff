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

module Node.Stream.Aff
  ( readSome
  , readSome_
  , readAll
  , readAll_
  , readN
  , readN_
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
import Data.Tuple (Tuple(..))
import Effect (Effect, untilE)
import Effect.Aff (effectCanceler, makeAff)
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Exception (catchException)
import Node.Buffer (Buffer)
import Node.Buffer as Buffer
import Node.Stream (Readable)
import Node.Stream as Stream
import Node.Stream.Aff.Internal (onceReadable, readableEnded)


-- | Wait until there is some data available from the stream.
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

  onceReadable r do
    catchException (res <<< Left) do
      bufs <- liftST $ Array.ST.new
      untilE do
      -- flip tailRecM unit \_ -> do
        Stream.read r Nothing >>= case _ of
          -- “The 'readable' event will also be emitted once the end of the
          -- stream data has been reached but before the 'end' event is emitted.”
          Nothing -> pure true
          Just chunk -> do
            void $ liftST $ Array.ST.push chunk bufs
            pure false
      ended <- readableEnded r
      ret <- liftST $ Array.ST.unsafeFreeze bufs
      res $ Right (Tuple ret ended)

  pure $ effectCanceler (canceller r)


-- | Read all data until the end of a stream.
-- |
-- | After this action finishes, `readableEnded` will be `true`
-- | for this stream.
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

  let
    -- stepRead _ = do
    --   Stream.read r Nothing >>= case _ of
    --     Nothing -> pure $ Done unit
    --     Just chunk -> do
    --       _ <- liftST $ Array.ST.push chunk bufs
    --       pure $ Loop unit

    oneRead = do
      onceReadable r do
        -- “The 'readable' event will also be emitted once the end of the
        -- stream data has been reached but before the 'end' event is emitted.”
        catchException (res <<< Left) do
          -- tailRecM stepRead unit
          untilE do
            Stream.read r Nothing >>= case _ of
              Nothing -> pure true
              Just chunk -> do
                _ <- liftST $ Array.ST.push chunk bufs
                pure false
          ended <- readableEnded r
          if ended then do
            ret <- liftST $ Array.ST.unsafeFreeze bufs
            res $ Right (Tuple ret ended)
          else
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
  red <- liftST $ STRef.new 0
  bufs <- liftST $ Array.ST.new

  let
    -- stepRead _ = do
    --   want <- map (n-_) $ liftST $ STRef.read red
    --   -- https://nodejs.org/docs/latest-v15.x/api/stream.html#stream_readable_read_size
    --   -- “If size bytes are not available to be read, null will be returned
    --   -- unless the stream has ended, in which case all of the data remaining
    --   -- in the internal buffer will be returned.”
    --   Stream.read r (Just want) >>= case _ of
    --     Nothing -> pure $ Done unit
    --     Just chunk -> do
    --       _ <- liftST $ Array.ST.push chunk bufs
    --       s <- Buffer.size chunk
    --       red' <- liftST $ STRef.modify (_+s) red
    --       if red' >= n then
    --         pure $ Done unit
    --       else
    --         pure $ Loop unit

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
          ended <- readableEnded r
          if m >= n || ended then do
            ret <- liftST $ Array.ST.unsafeFreeze bufs
            res $ Right (Tuple ret ended)
          else
            oneRead -- this is not recursion

  oneRead
  pure $ effectCanceler (canceller r)
