module Test.Main where

import Prelude

import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Aff.Class (liftAff)
import Effect.Class.Console (log)
import Node.Buffer (concat)
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
      input <- liftAff $ concat <$> readAll stdin
      -- void $ writeString stdout UTF8 input (\_ -> pure unit)
      void $ write stdout input (\_ -> pure unit)
      pure unit
