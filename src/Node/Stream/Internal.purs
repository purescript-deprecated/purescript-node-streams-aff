module Node.Stream.Aff.Internal
  ( onceReadable
  , onceEnd
  , onceDrain
  )
where

import Prelude

import Effect (Effect)
import Node.Stream (Readable, Writable)

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