# homebrew-tap

Personal Homebrew tap for reviewed, intentionally pinned machine-bootstrap
packages.

## Add this Tap

```bash
brew tap grantbirki/tap
```

## Install a Formula

Use the fully qualified tap name. Vendored formulae intentionally do not move
with upstream Homebrew metadata.

```bash
brew install grantbirki/tap/bash
```

## Update a Formula

Formulae in this tap are vendored direct roots. They do not move automatically with `homebrew/core`; transitive dependencies still do. Formula and cask updates use a 14-day release cooldown. Personal releases from the exact `GrantBirki/<token>` repository matching a formula or cask token may be adopted immediately, but still require exact upstream provenance, checksums, and explicit adoption reasons. See [SECURITY.md](SECURITY.md) before changing a version, checksum, resource, or bottle.

## Vendor a Formula

Import the direct formula recipe from an exact upstream commit, preserve its
source/resource/bottle checksums, and add its provenance before adding it to
the Brewfile. Do not vendor its transitive dependencies. The complete review
and cooldown workflow is in [SECURITY.md](SECURITY.md).

## Install with Brewfile

To install everything declared in this repo's `Brewfile`, including tap-specific formulae and casks, run:

```bash
script/install
```

Homebrew 6 is required. The Brewfile grants trust to its exact tap-qualified
formulae and casks and rejects casks without SHA-256 checksums; it does not
trust the whole tap. If this tap was broadly trusted before Homebrew 6, follow
the one-time migration in [SECURITY.md](SECURITY.md).

`script/bootstrap` only prepares the repo's vendored Ruby dependencies for local
development and CI. Use `script/install` for Homebrew lifecycle management.

Personal unsigned casks such as Espresso, OneShot, and Shit are intentionally
outside the default Brewfile. They preserve macOS quarantine and require manual
approval when installed.

## Development

Run the same checks used by CI:

```bash
script/lint
script/test
script/provenance check
```

These commands validate shell/Ruby syntax, Homebrew style, formula and cask
parsing, Brewfile policy, direct-root provenance, and exact-SHA GitHub Action
pins. They do not install formulae or casks.

If `homebrew-brew-vulns` is already installed, `script/vulns` runs a live,
high-severity scan of Brewfile formulae and their currently resolved
dependencies. It is intentionally not part of deterministic CI.
