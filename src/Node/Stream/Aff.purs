-- | Asynchronous I/O with Node.js streams.
module Node.Stream.Aff
  ( readAll
  , readN
  )

where

-- questions:
--
-- cancellation?
-- launchAff_ will wait for writes to end?
-- writes will be flushed?

import Prelude

import Effect (Effect)
-- import Effect.Console (log)


-- | Read all input until end from a `Readable` stream.
-- |
-- | The result may be chunked into more than one `Buffer`.
-- | To concatenate the result into a single `Buffer`, use
-- | `Node.Buffer.concat :: Array Buffer -> Buffer`.
-- |
-- | It doesn't make sense to read concurrently?
readAll :: forall m r. MonadAff m => Readable r -> m (Array Buffer)
readAll r =
  -- inspired by https://dgopsq.space/blog/reading-from-stdin-using-purescript
  liftAff <<< makeAff
    $ \res -> do
        bufs <- liftST $ Array.ST.new

        onError r $ Left >>> res

        onEnd r do
          ret <- liftST $ Array.ST.unsafeFreeze bufs
          -- void $ writeString stderr UTF8 "end" (\_ -> pure unit)
          res $ Right ret


        -- “Adding a 'data' event handler [will] switched to flowing mode.”
        -- https://nodejs.org/docs/latest-v14.x/api/stream.html#stream_two_reading_modes
        onData r \chunk -> do
          void $ liftST $ Array.ST.push chunk bufs
          -- void $ writeString stderr UTF8 "data" (\_ -> pure unit)

        -- void $ writeString stderr UTF8 "onData" (\_ -> pure unit)

        -- Return a `Canceler` effect that will
        -- destroy the stream.
        -- TODO
        -- pure $ effectCanceler (destroy r)
        pure $ effectCanceler (pure unit)

-- | Read *N* bytes from a `Readable` stream.
-- |
-- | Will wait for *N* bytes to become available on the stream,
-- | but may return fewer than *N* bytes if the stream ends.
-- | If more than *N* bytes are available on the stream, then
-- | only return *N* bytes and leave the rest in the internal buffer...
-- | unless the stream has ended?
-- |
-- | The result may be chunked into more than one `Buffer`.
-- | To concatenate the result into a single `Buffer`, use
-- | `Node.Buffer.concat :: Array Buffer -> Buffer`.
readN :: forall m r. MonadAff m => Readable r -> Int -> m (Array Buffer)
readN r n = liftAff <<< makeAff \res -> do
  red <- STRef.new 0
  bufs <- liftST $ Array.ST.new

  let
    step _ = do
      want <- map (n-_) $ liftST $ STRef.read red
      -- https://nodejs.org/docs/latest-v15.x/api/stream.html#stream_readable_read_size
      -- “If size bytes are not available to be read, null will be returned
      -- unless the stream has ended, in which case all of the data remaining
      -- in the internal buffer will be returned.”
      read r (Just want) >>= case _ of
        Nothing -> Done unit
        Just chunk -> do
          s <- size chunk
          liftST $ Array.ST.push chunk bufs
          red' <- liftST $ STRef.modify red (_+s)
          if red' >= n then
            Done unit
          else
            Step unit

    oneRead = do
      onceReadable r do
        tailRecM step unit
        r <- STRef.read red
        if r >= n then do
          ret <- liftST $ Array.ST.unsafeFreeze bufs
          res $ Right ret
        else
          oneRead

  oneRead

