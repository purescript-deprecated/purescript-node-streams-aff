-- | How to test:
-- |
-- | ```
-- | spago -x spago-dev.dhall test
-- | ```
-- |
-- | We want to read from a file, not stdin, because stdin has no EOF.
module Test.Main where

import Prelude

import Control.Parallel (parSequence, parSequence_)
import Data.Array ((..))
import Data.Array as Array
import Data.Foldable (for_)
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..), fst)
import Effect (Effect)
import Effect.Aff (Milliseconds(..), launchAff_)
import Effect.Class (liftEffect)
import Node.Buffer (Buffer, concat)
import Node.Buffer as Buffer
import Node.FS.Stream (createReadStream, createWriteStream)
import Node.Stream.Aff (end, fromStringUTF8, readAll, readN, readSome, toStringUTF8, write)
import Node.Stream.Aff.Internal (newReadableStringUTF8, newStreamPassThrough)
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
        it "PassThrough" do
          s <- newStreamPassThrough
          _ <- write s =<< fromStringUTF8 "test"
          end s
          b1 <- toStringUTF8 =<< (_.buffers <$> readAll s)
          shouldEqual b1 "test"
        it "overflow PassThrough" do
          s <- newStreamPassThrough
          let magnitude = 10000
          -- let magnitude = 10
          [ outstring ] <- fromStringUTF8 "aaaaaaaaaa"
          parSequence_
            [ write s $ Array.replicate magnitude outstring
            , void $ readSome s
            ]

          -- Tuple input1 _ <- readSome s
          -- Tuple input2 _ <- readN s (5 * magnitude)
          -- Tuple input3 readagain <- readAll s
          -- shouldEqual readagain false
          -- _ :: Buffer <- liftEffect <<< concat <<< fst =<< readSome s
          -- void $ readN s 1
          -- void $ readAll s
          -- let inputs = input1 <> input2 <> input3
          -- input :: Buffer <- liftEffect $ concat inputs
          -- inputSize <- liftEffect $ Buffer.size input
          -- shouldEqual inputSize (10 * magnitude)
        it "reads from a zero-length Readable" do
          r <- newReadableStringUTF8 ""
          b1 <- toStringUTF8 =<< (_.buffers <$> readSome r)
          shouldEqual "" b1
          b2 <- toStringUTF8 =<< (_.buffers <$> readAll r)
          shouldEqual "" b2
          b3 <- toStringUTF8 =<< (_.buffers <$> readN r 0)
          shouldEqual "" b3
        it "readN cleans up event handlers" do
          s <- newReadableStringUTF8 ""
          for_ (0 .. 100) \_ -> void $ readN s 0
        it "readSome cleans up event handlers" do
          s <- newReadableStringUTF8 ""
          for_ (0 .. 100) \_ -> void $ readSome s
        it "readAll cleans up event handlers" do
          s <- newReadableStringUTF8 ""
          for_ (0 .. 100) \_ -> void $ readAll s
        it "write cleans up event handlers" do
          s <- newStreamPassThrough
          [ b ] <- fromStringUTF8 "x"
          for_ (0 .. 100) \_ -> void $ write s [ b ]
        it "writes and reads to file" do
          let outfilename = "/tmp/test1.txt"
          let magnitude = 100000
          outfile <- liftEffect $ createWriteStream outfilename
          [ outstring ] <- fromStringUTF8 "aaaaaaaaaa"
          write outfile $ Array.replicate magnitude outstring
          infile <- liftEffect $ createReadStream outfilename
          {buffers:input1} <- readSome infile
          {buffers: input2} <- readN infile (5 * magnitude)
          {buffers: input3, readagain} <- readAll infile
          shouldEqual readagain false
          _ :: Buffer <- liftEffect <<< concat <<< _.buffers =<< readSome infile
          void $ readN infile 1
          void $ readAll infile
          let inputs = input1 <> input2 <> input3
          input :: Buffer <- liftEffect $ concat inputs
          inputSize <- liftEffect $ Buffer.size input
          shouldEqual inputSize (10 * magnitude)
        it "writes and closes file" do
          let outfilename = "/tmp/test2.txt"
          outfile <- liftEffect $ createWriteStream outfilename
          write outfile =<< fromStringUTF8 "test"
          end outfile
          expectError $ write outfile =<< fromStringUTF8 "test2"

    pure unit
