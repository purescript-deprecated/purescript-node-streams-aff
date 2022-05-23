-- | How to test:
-- | ```
-- | spago -x spago-dev.dhall test --exec-args <(head --bytes 1000000 /dev/zero)
-- | ```
-- |
module Test.Main where

import Prelude

import Data.Array as Array
import Data.Array.Partial as Array.Partial
import Data.Either (either)
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Aff (launchAff_, runAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Node.Buffer (Buffer, concat)
import Node.Buffer as Buffer
import Node.FS.Stream (createReadStream)
import Node.Process (argv, stdout)
import Node.Stream (write)
import Node.Stream.Aff (readAll, readN, readSome)
import Partial.Unsafe (unsafePartial)
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Reporter (consoleReporter)
import Test.Spec.Runner (runSpec)
import Unsafe.Coerce (unsafeCoerce)

main :: Effect Unit
main = unsafePartial $ do
  -- We want to read from a file, not stdin, because stdin has no EOF
  -- Console.log =<< pure <<< show =<< argv
  infile <- createReadStream =<< pure <<< flip Array.unsafeIndex 2 =<< argv
  -- Console.log $ unsafeCoerce infile
  runAff_ (either (show >>> Console.log) (\_ -> pure unit)) $ runSpec [consoleReporter] do
    describe "Node.Stream.Aff" do
      it "reads" do
        Tuple inputs1 ended <- readSome infile
        Console.log $ unsafeCoerce infile
        -- Tuple inputs1 ended <- readN infile 30
        Console.log $ "ended " <> show ended
        -- Tuple inputs1 _ <- readAll infile
        -- Tuple inputs2 _ <- readSome infile
        -- Tuple inputs3 _ <- readAll infile
        -- let inputs = inputs1 <> inputs2 <> inputs3
        -- let inputs = inputs1 <> inputs2
        let inputs = inputs1
        input :: Buffer <- liftEffect $ concat inputs
        -- _ <- liftEffect $ write stdout input (\_ -> pure unit)
        inputSize <- liftEffect $ Buffer.size input
        shouldEqual 1000000 inputSize
