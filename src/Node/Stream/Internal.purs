module Node.Stream.Internal
  (onceReadable)
where

import Prelude

import Effect (Effect)
import Node.Stream (Readable)

-- | Listen for one `readable` event, then detach the event listener.
foreign import onceReadable
  :: forall w
   . Readable w
  -> Effect Unit
  -> Effect Unit