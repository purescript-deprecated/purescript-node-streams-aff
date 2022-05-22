module Test.Main where

import Prelude

import Data.Array as Array
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Aff.Class (liftAff)
import Effect.Class (liftEffect)
import Effect.Class.Console (log)
import Node.Buffer (Buffer, concat)
import Node.Encoding (Encoding(..))
import Node.Process (stdin, stdout)
import Node.Stream (write, writeString)
import Node.Stream.Aff (readAll)
import Test.Spec (describe, it)
import Test.Spec.Reporter (consoleReporter)
import Test.Spec.Runner (runSpec)

main :: Effect Unit
main = launchAff_ $ runSpec [consoleReporter] do
  describe "Node.Stream.Aff" do
    it "read stdin" do
      -- input :: Buffer <- liftEffect <<< concat =<< readAll stdin
      -- void $ liftEffect $ write stdout input (\_ -> pure unit)
      inputs <- readAll stdin
      input :: Buffer <- liftEffect $ concat inputs
      -- void $ liftEffect $ write stdout input (\_ -> pure unit)
      void $ liftEffect $ writeString stdout UTF8 ("num " <> show (Array.length inputs)) (\_ -> pure unit)
      pure unit
