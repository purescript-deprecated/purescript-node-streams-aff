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
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..), fst)
import Effect (Effect)
import Effect.Aff (Milliseconds(..), launchAff_)
import Effect.Class (liftEffect)
import Node.Buffer (Buffer, concat)
import Node.Buffer as Buffer
import Node.Encoding (Encoding(..))
import Node.FS.Stream (createReadStream, createWriteStream)
import Node.Stream.Aff (end, readAll, readN, readSome, toStringUTF8, write)
import Node.Stream.Aff.Internal (newReadableStringUTF8)
import Partial.Unsafe (unsafePartial)
import Test.Spec (describe, it)
import Test.Spec.Assertions (expectError, shouldEqual)
import Test.Spec.Reporter (consoleReporter)
import Test.Spec.Runner (defaultConfig, runSpec')

main :: Effect Unit
main = unsafePartial $ do
  launchAff_ do
    runSpec' (defaultConfig { timeout = Just (Milliseconds 40000.0) }) [ consoleReporter ] do
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
          shouldEqual inputSize (10 * magnitude)
        it "writes and closes" do
          let outfilename = "/tmp/test2.txt"
          outfile <- liftEffect $ createWriteStream outfilename
          b <- liftEffect $ Buffer.fromString "test" UTF8
          write outfile [ b ]
          end outfile
          expectError $ write outfile [ b ]
        it "reads from a zero-length Readable" do
          r <- liftEffect $ newReadableStringUTF8 ""
          b1 <- toStringUTF8 =<< (fst <$> readSome r)
          shouldEqual "" b1
          b2 <- toStringUTF8 =<< (fst <$> readAll r)
          shouldEqual "" b2
          b3 <- toStringUTF8 =<< (fst <$> readN r 0)
          shouldEqual "" b3

    pure unit
