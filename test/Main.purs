-- | How to test:
-- |
-- | ```
-- | spago -x spago-dev.dhall test --exec-args <(head --bytes 1000000 /dev/zero)
-- | ```
-- |
-- | We want to read from a file, not stdin, because stdin has no EOF.
module Test.Main where

import Prelude

import Data.Array as Array
import Data.Either (either)
import Effect (Effect)
import Effect.Aff (runAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Node.Buffer (Buffer, concat)
import Node.Buffer as Buffer
import Node.Encoding (Encoding(..))
import Node.FS.Stream (createReadStream, createWriteStream)
import Node.Process (argv)
import Node.Stream.Aff (readAll, readN, readSome, write)
import Partial.Unsafe (unsafePartial)
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Reporter (consoleReporter)
import Test.Spec.Runner (runSpec)
import Unsafe.Coerce (unsafeCoerce)

main :: Effect Unit
main = unsafePartial $ do
  runAff_ (either (unsafeCoerce >>> Console.error) (\_ -> pure unit)) $ runSpec [consoleReporter] do
    describe "Node.Stream.Aff" do
      it "reads 1" do
        infile <- liftEffect $ createReadStream =<< pure <<< flip Array.unsafeIndex 2 =<< argv
        inputs1 <- readN infile 500000
        bytesRead1 :: Int <- liftEffect $ Array.foldM (\a b -> (a+_) <$> Buffer.size b) 0 inputs1
        shouldEqual 500000 bytesRead1
        inputs2 <- readSome infile
        inputs3 <- readAll infile
        let inputs = inputs1 <> inputs2 <> inputs3
        -- TODO read after EOF will hang
        -- inputs4 <- readAll infile
        -- inputs4 <- readSome infile
        -- inputs4 <- readN infile 10
        -- let inputs = inputs1 <> inputs2 <> inputs3 <> inputs4
        bytesRead :: Int
            <- liftEffect $ Array.foldM (\a b -> (a+_) <$> Buffer.size b) 0 inputs
        shouldEqual 1000000 bytesRead
        input :: Buffer <- liftEffect $ concat inputs
        inputSize <- liftEffect $ Buffer.size input
        shouldEqual 1000000 inputSize
      it "writes 1" do
        let outfilename = "outfile.txt"
        outfile <- liftEffect $ createWriteStream outfilename
        outstring <- liftEffect $ Buffer.fromString "aaaaaaaaaa" UTF8
        write outfile $ Array.replicate 1000 outstring
        infile <- liftEffect $ createReadStream outfilename
        inputs <- readAll infile
        input :: Buffer <- liftEffect $ concat inputs
        inputSize <- liftEffect $ Buffer.size input
        shouldEqual 10000 inputSize


