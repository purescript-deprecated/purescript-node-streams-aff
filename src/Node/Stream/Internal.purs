module Node.Stream.Internal
  ( onceReadable
  , readableEnded
  )
where

import Prelude

import Effect (Effect)
import Node.Stream (Readable)

-- | Listen for one `readable` event, call the callback, then detach
-- | the `readable` event listener.
foreign import onceReadable
  :: forall w
   . Readable w
  -> Effect Unit
  -> Effect Unit

-- | Test if the `Readable` stream has reached its end.
foreign import readableEnded :: forall w. Readable w -> Effect Boolean