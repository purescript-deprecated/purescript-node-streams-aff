-- Spago configuration for testing, benchmarking, development.
--
-- See:
-- * ./CONTRIBUTING.md
-- * https://github.com/purescript/spago#devdependencies-testdependencies-or-in-general-a-situation-with-many-configurations
--

let conf = ./spago.dhall

let packages_dev = ./packages.dhall

in

conf //
{ sources = [ "src/**/*.purs", "test/**/*.purs", ]
, dependencies = conf.dependencies #
  [ "spec"
  , "node-process"
  , "node-fs"
  , "console"
  , "foldable-traversable"
  , "parallel"
  , "partial"
  , "unsafe-coerce"
  , "control"
  ]
, packages = packages_dev
}
