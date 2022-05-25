module Node.Stream.Aff.Internal
  ( onceDrain
  , onceEnd
  , onceError
  , onceReadable
  )
  where

import Prelude

import Effect (Effect)
import Effect.Exception (Error)
import Node.Stream (Readable, Stream, Writable)

-- | Listen for one `readable` event, call the callback, then remove
-- | the event listener.
-- |
-- | Returns an effect for removing the event listener even if no event
-- | was raised.
foreign import onceReadable
  :: forall r
   . Readable r
  -> Effect Unit
  -> Effect (Effect Unit)

-- | Listen for one `end` event, call the callback, then remove
-- | the event listener.
-- |
-- | Returns an effect for removing the event listener even if no event
-- | was raised.
foreign import onceEnd
  :: forall r
   . Readable r
  -> Effect Unit
  -> Effect (Effect Unit)

-- | Listen for one `drain` event, call the callback, then remove
-- | the event listener.
-- |
-- | Returns an effect for removing the event listener even if no event
-- | was raised.
foreign import onceDrain
  :: forall w
   . Writable w
  -> Effect Unit
  -> Effect (Effect Unit)

-- | Listen for one `error` event, call the callback, then remove
-- | the event listener.
-- |
-- | Returns an effect for removing the event listener even if no event
-- | was raised.
foreign import onceError
  :: forall r
   . Stream r
  -> (Error -> Effect Unit)
  -> Effect (Effect Unit)
