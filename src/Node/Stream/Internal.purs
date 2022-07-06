-- | Maybe the stuff in here should be moved into the
-- | [__Node.Stream__](https://pursuit.purescript.org/packages/purescript-node-streams/docs/Node.Stream)
-- | module?
module Node.Stream.Aff.Internal
  ( onceDrain
  , onceEnd
  , onceError
  , onceReadable
  , readable
  , push
  , newReadable
  , newReadableStringUTF8
  )
  where

import Prelude

import Data.Nullable (Nullable, notNull, null)
import Effect (Effect)
import Effect.Exception (Error)
import Node.Buffer (Buffer)
import Node.Buffer as Buffer
import Node.Encoding as Encoding
import Node.Stream (Readable, Stream, Writable)

-- | Listen for one `readable` event, call the callback, then remove
-- | the event listener.
-- |
-- | Returns an effect for removing the event listener before the event
-- | is raised.
foreign import onceReadable
  :: forall r
   . Readable r
  -> Effect Unit
  -> Effect (Effect Unit)

-- | Listen for one `end` event, call the callback, then remove
-- | the event listener.
-- |
-- | Returns an effect for removing the event listener before the event
-- | is raised.
foreign import onceEnd
  :: forall r
   . Readable r
  -> Effect Unit
  -> Effect (Effect Unit)

-- | Listen for one `drain` event, call the callback, then remove
-- | the event listener.
-- |
-- | Returns an effect for removing the event listener before the event
-- | is raised.
foreign import onceDrain
  :: forall w
   . Writable w
  -> Effect Unit
  -> Effect (Effect Unit)

-- | Listen for one `error` event, call the callback, then remove
-- | the event listener.
-- |
-- | Returns an effect for removing the event listener before the event
-- | is raised.
foreign import onceError
  :: forall r
   . Stream r
  -> (Error -> Effect Unit)
  -> Effect (Effect Unit)

-- | The [`readable.readable`](https://nodejs.org/api/stream.html#readablereadable)
-- | property of a stream.
-- |
-- | > Is true if it is safe to call `readable.read()`, which means the stream
-- | > has not been destroyed or emitted `'error'` or `'end'`.
foreign import readable
  :: forall r
   . Readable r
  -> Effect Boolean


-- | [`readable.push(chunk[, encoding])`](https://nodejs.org/api/stream.html#readablepushchunk-encoding)
foreign import push
  :: forall r
   . Readable r
  -> Nullable Buffer
  -> Effect Boolean

-- | `new stream.Readable()`
foreign import newReadable
  :: forall r
   . Effect (Readable r)

-- | Construct a `Readable` from a `String`.
newReadableStringUTF8
  :: forall r
   . String
  -> Effect (Readable r)
newReadableStringUTF8 strng = do
  rstream <- newReadable
  _ <- push rstream =<< (notNull <$> Buffer.fromString strng Encoding.UTF8)
  _ <- push rstream null -- the end of the stream
  pure rstream
