module Node.Stream.Aff.Internal
  ( onceReadable
  , onceEnd
  , onceDrain
  , onceError
  , unbuffer
  )
where

import Prelude

import Effect (Effect)
import Effect.Exception (Error)
import Node.Stream (Readable, Stream, Writable)

-- | Listen for one `readable` event, call the callback, then detach
-- | the `readable` event listener.
foreign import onceReadable
  :: forall r
   . Readable r
  -> Effect Unit
  -> Effect Unit

-- | Listen for one `end` event, call the callback, then detach
-- | the `end` event listener.
foreign import onceEnd
  :: forall r
   . Readable r
  -> Effect Unit
  -> Effect Unit

-- | Listen for one `drain` event, call the callback, then detach
-- | the `drain` event listener.
foreign import onceDrain
  :: forall w
   . Writable w
  -> Effect Unit
  -> Effect Unit

foreign import onceError
  :: forall r
   . Stream r
  -> (Error -> Effect Unit)
  -> Effect Unit

-- | Issue:
-- | https://github.com/nodejs/node/issues/6379
-- |
-- | Implementation:
-- | https://github.com/nodejs/node/issues/6456
foreign import unbuffer
  :: forall w
   . Writable w
  -> Effect Unit
-- foreign import stdoutUnbuffer :: Effect Unit
