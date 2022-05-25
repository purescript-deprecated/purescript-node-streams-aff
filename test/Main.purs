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
import Data.Either (Either(..), either)
import Effect (Effect)
import Effect.Aff (Error, Milliseconds(..), delay, runAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Node.Buffer (Buffer, concat)
import Node.Buffer as Buffer
import Node.Encoding (Encoding(..))
import Node.FS.Stream (createReadStream, createWriteStream)
import Node.Process (argv, stderr, stdout)
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
  exiter <- noExit
  runAff_ completion do
    write' stdout "ENTER \n"
    runSpec [consoleReporter] do
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
    do
      -- b <- liftEffect $ Buffer.create 0
      b <- liftEffect $ Buffer.fromString "EXIT \n" UTF8
      write stdout $ Array.replicate 10 b
    -- delay (Milliseconds 2000.0)
    -- write' stdout "EXIT\n"
    -- liftEffect exiter
    -- pure $ Console.log "log completion"
    pure (pure unit)
