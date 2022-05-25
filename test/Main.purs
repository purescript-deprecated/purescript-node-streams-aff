-- | How to test:
-- |
-- | ```
-- | spago -x spago-dev.dhall test
-- | ```
-- |
-- | We want to read from a file, not stdin, because stdin has no EOF.
module Test.Main where

import Prelude

import Data.Array as Array
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..), fst)
import Effect (Effect)
import Effect.Aff (Error, Milliseconds(..), runAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Node.Buffer (Buffer, concat)
import Node.Buffer as Buffer
import Node.Encoding (Encoding(..))
import Node.FS.Stream (createReadStream, createWriteStream)
import Node.Stream.Aff (readAll, readN, readSome, write)
import Partial.Unsafe (unsafePartial)
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Reporter (consoleReporter)
import Test.Spec.Runner (defaultConfig, runSpecT)
import Unsafe.Coerce (unsafeCoerce)

completion :: Either Error (Effect Unit) -> Effect Unit
completion = case _ of
  Left e -> Console.error (unsafeCoerce e)
  Right f -> f

main :: Effect Unit
main = unsafePartial $ do
  runAff_ completion do
    void $ runSpecT (defaultConfig {timeout = Just (Milliseconds 10000.0)}) [consoleReporter] do
      describe "Node.Stream.Aff" do
        it "writes and reads" do
          let outfilename = "/tmp/test1.txt"
          let magnitude = 100000
          outfile <- liftEffect $ createWriteStream outfilename
          outstring <- liftEffect $ Buffer.fromString "aaaaaaaaaa" UTF8
          write outfile $ Array.replicate magnitude outstring
          infile <- liftEffect $ createReadStream outfilename
          Tuple input1 _ <- readSome infile
          Tuple input2 _ <- readN infile (5 * magnitude)
          Tuple input3 readagain <- readAll infile
          shouldEqual readagain false
          _ :: Buffer <- liftEffect <<< concat <<< fst =<< readSome infile
          void $ readN infile 1
          void $ readAll infile
          let inputs = input1 <> input2 <> input3
          input :: Buffer <- liftEffect $ concat inputs
          inputSize <- liftEffect $ Buffer.size input
          shouldEqual (10 * magnitude) inputSize

    pure (pure unit)
