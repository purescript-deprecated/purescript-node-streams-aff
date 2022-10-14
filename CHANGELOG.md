# Changelog

Notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Breaking changes:

New features:

Bugfixes:

Other improvements:

* Transferred to https://github.com/purescript-node org (#7 by @jamesdbrock)

## v4.0.0

Bugfixes:

* Read from zero-length `Readable`.

## v3.0.0

Breaking changes:

* Delete `writableClose` and add `end`.

New features:

* Add `toStringUTF8` and `fromStringUTF8`.

Bugfixes:

* Bugfix `onceError`.

## v2.0.0

* Aff cancellation is correctly handled.

## v1.1.0

* `write` will throw errors after `drain` event.
