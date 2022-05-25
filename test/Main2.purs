-- | How to test:
-- |
-- | ```
-- | spago -x spago-dev.dhall test --main Test2 | wc -c
-- | ```
-- |
-- | We want to read from a file, not stdin, because stdin has no EOF.
module Test2 where

import Prelude

import Data.Array as Array
import Data.Either (Either(..), either)
import Effect (Effect)
import Effect.Aff (Error, Milliseconds(..), delay, runAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Node.Buffer (Buffer, concat)
import Node.Buffer as Buffer
import Node.Encoding (Encoding(..))
import Node.FS.Stream (createReadStream, createWriteStream)
import Node.Process (argv, stderr, stdout, stdoutIsTTY)
import Node.Stream.Aff (noExit, readAll, readN, readSome, unbuffer, write, write')
import Partial.Unsafe (unsafePartial)
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Reporter (consoleReporter)
import Test.Spec.Runner (runSpec)
import Unsafe.Coerce (unsafeCoerce)

completion :: Either Error (Effect Unit) -> Effect Unit
completion = case _ of
  Left e -> Console.error (unsafeCoerce e)
  Right f -> f


main :: Effect Unit
main = unsafePartial $ do
  -- Console.log $ unsafeCoerce stdout
  -- unbuffer stdout
  -- Console.log $ unsafeCoerce stdout

  -- runAff_ (either (unsafeCoerce >>> Console.error) (\_ -> pure unit)) do

  Console.log $ "stdoutIsTTY " <> show stdoutIsTTY <> "\n"

  exiter <- noExit

  runAff_ completion do
    -- write' stdout "ENTER \n"
    -- delay (Milliseconds 2000.0)
    do
      -- b <- liftEffect $ Buffer.create 0
      b <- liftEffect $ Buffer.fromString "aaaaaaaaaa" UTF8
      -- write stdout $ Array.replicate 100000 b
      write stdout $ Array.replicate 1 b
      -- write stdout [b]
    -- write' stdout "EXIT\n"
    liftEffect exiter
    -- pure $ Console.log "log completion"
    pure (pure unit)
