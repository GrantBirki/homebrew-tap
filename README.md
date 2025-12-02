# homebrew-tap

Personal Homebrew tap repo

## Add this Tap

```bash
brew tap grantbirki/tap
```

## Install a Formula

If the Formula has a name clash with a Formula in the homebrew-core repo, you will need to specify the tap name.

For example, I host my own version of the `crystal` formula here to install the exact version that I want to use since the homebrew-core version of `crystal` is not versioned with `crystal@<version>`.

```bash
brew install grantbirki/tap/crystal
```

## Update a Formula

If a Formula needs to be updated, push the changes to this repo. Then run `brew update` to update the local Homebrew cache. Then you can run `brew upgrade <formula>` to upgrade the formula.

## Pin a Version

If you want to pin an exact version of a Formula and add it to this repo do the following:

- Ensure the name of the file is `<formula>@<version>.rb` - Example: `foo@1.23.0.rb`
- Ensure the class name matches the file name - Example: `class FooAT1230 < Formula` ([commit](https://github.com/GrantBirki/homebrew-tap/commit/1dabf7980046740e4f00122f189693013ea47cb5))

## Bootstrap with Brewfile

To **bootstrap** a new machine with all GrantBirki's preferred packages, in this repo's `Brewfile`, simply run the following idempotent command:

```bash
script/bootstrap
```
