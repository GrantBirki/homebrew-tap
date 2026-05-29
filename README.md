# homebrew-tap

Personal Homebrew tap repo

## Add this Tap

```bash
brew tap grantbirki/tap
```

## Install a Formula

If the Formula has a name clash with a Formula in the homebrew-core repo, you will need to specify the tap name.

For example, this tap can host pinned formulae that should not move with upstream Homebrew metadata.

```bash
brew install grantbirki/tap/bash
```

## Update a Formula

If a Formula needs to be updated, push the changes to this repo. Then run `brew update` to update the local Homebrew cache. Then you can run `brew upgrade <formula>` to upgrade the formula.

## Pin a Version

If you want to pin an exact version of a Formula and add it to this repo do the following:

- Ensure the name of the file is `<formula>@<version>.rb` - Example: `foo@1.23.0.rb`
- Ensure the class name matches the file name - Example: `class FooAT1230 < Formula` ([commit](https://github.com/GrantBirki/homebrew-tap/commit/1dabf7980046740e4f00122f189693013ea47cb5))

## Install with Brewfile

To install everything declared in this repo's `Brewfile`, including tap-specific formulae and casks, run:

```bash
script/install
```

`script/bootstrap` only prepares the repo's vendored Ruby dependencies for local
development and CI. Use `script/install` for Homebrew lifecycle management.

## Development

Run the same checks used by CI:

```bash
script/lint
script/test
```

These commands validate shell/Ruby syntax, Homebrew style, cask parsing, Brewfile parsing, and exact-SHA pinning for GitHub Actions. They do not install formulae or casks.
