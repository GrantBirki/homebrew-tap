# AGENTS.md

Guidance for agents working in this repository.

## Repository Purpose

This repository is Grant's personal Homebrew tap. Treat it as a packaging and
machine-bootstrap repository first:

- `Formula/` contains Homebrew formulae written in Ruby DSL.
- `Casks/` contains Homebrew casks written in Ruby DSL.
- `Brewfile` declares the packages that should be installed on a new machine.
- `script/install` is the one-shot installer for the Brewfile.
- `script/bootstrap` is a backward-compatible wrapper around `script/install`.
- `script/lint` and `script/test` are the local CI entrypoints.

The project may grow into more Ruby tooling over time, but the current public
contract is Homebrew behavior: formulae and casks must be installable, pinned
entries must stay pinned, and the Brewfile must install this tap's versions when
that is the intent.

## Reference Project

Use `/Users/birki/code/ruby-template` as the local Ruby style reference when
adding real Ruby project infrastructure. The important conventions from that
repo are:

- Use GitHub's "Scripts to Rule Them All" style through `script/*` commands.
- Prefer `script/bootstrap`, `script/test`, `script/lint`, and `script/build`
  as stable command entrypoints once the project has enough Ruby code to need
  them.
- Use `script/env` for shared environment setup instead of duplicating path,
  Ruby version, color, or bundler logic across scripts.
- Use `rbenv` and `.ruby-version` when the repo needs a project Ruby runtime.
- Vendor Ruby dependencies with Bundler when adding a Gemfile:
  `vendor/cache/`, `vendor/gems/`, `.bundle/config`, and `bundle install --local`.
- Use RuboCop with `rubocop-github` for linting and RSpec/SimpleCov for tests
  if this evolves beyond Homebrew DSL files.

Do not copy all of `ruby-template` preemptively. Add that machinery only when
there is Ruby application or helper code that needs it.

## Current Layout

- `Brewfile`
  - New-machine package list.
  - Tap-specific packages must use fully qualified names, for example
    `brew "grantbirki/tap/crystal"` and `cask "grantbirki/tap/santa"`.
  - Use the upstream cask name only when latest upstream is desired.

- `Formula/*.rb`
  - Formula class names must match Homebrew conventions for the filename.
  - Keep `desc`, `homepage`, `version` or `stable`, `url`, `sha256`, and
    `license` accurate.
  - Include a meaningful `test do` block whenever possible.

- `Casks/*.rb`
  - Cask token must match the filename.
  - Keep `version`, `sha256`, `url`, `name`, `desc`, `homepage`, install
    artifact, and uninstall/zap behavior accurate.
  - Pinned casks in this tap intentionally override newer upstream casks.

- `script/install`
  - Installs the root `Brewfile`.
  - Taps `grantbirki/tap`, runs `brew update`, then runs
    `brew bundle install --file=...`.
  - Do not run this during validation unless the user explicitly wants packages
    installed or upgraded on the machine.

- `script/bootstrap`
  - Compatibility alias. Keep it thin unless the user asks to restore separate
    bootstrap behavior.

- `.github/workflows/*.yml`
  - CI follows the `ruby-template` shape: workflow names and job names are
    `lint` and `test`, with `permissions: contents: read`.
  - All `uses:` references must be pinned to full commit SHAs. `script/lint`
    enforces this.
  - Do not add setup actions unless they are required; this repo currently uses
    the macOS runner's existing Homebrew/Ruby tooling.

## Homebrew Tap Rules

When adding or changing formulae and casks:

1. Prefer the smallest packaging change that satisfies the request.
2. Verify release URLs and checksums from primary sources.
3. Do not silently move a pinned cask or formula to latest upstream.
4. If a Brewfile entry should use this tap's version, use the fully qualified
   tap name.
5. Preserve existing user-facing app names and bundle identifiers in `zap`
   paths unless release notes or package contents prove they changed.
6. Keep Homebrew DSL style idiomatic. Use `brew style` instead of manually
   arguing with RuboCop alignment.
7. Treat casks that install privileged helpers, system extensions, launch
   daemons, or security tools with extra care. Include uninstall behavior when
   upstream Homebrew has a reliable pattern.

## Pinned Cask Workflow

For a pinned third-party cask:

1. Find the exact release tag requested by the user.
2. Identify the exact asset Homebrew should install.
3. Use the release asset checksum, preferably from the GitHub release API
   `digest` field when available.
4. Create or update `Casks/<token>.rb` with that fixed `version` and `sha256`.
5. Add `cask "grantbirki/tap/<token>"` to `Brewfile`.
6. Validate with Homebrew's parser and style tools.

Useful commands:

```bash
gh api repos/<owner>/<repo>/releases/tags/<tag>
brew ruby -e 'require "cask/cask_loader"; c = Cask::CaskLoader::FromContentLoader.new(File.read(ARGV.fetch(0))).load(config: nil); puts [c.token, c.version, c.sha256, c.url.to_s].join("\n")' Casks/<token>.rb
brew style Casks/<token>.rb
brew bundle list --file=Brewfile --cask
```

If `brew audit` refuses a path or says the repo is not a tapped checkout, fall
back to `brew style`, `ruby -c`, and the `Cask::CaskLoader::FromContentLoader`
parse check. Do not claim a full audit passed unless it actually did.

## Formula Workflow

For a formula update:

1. Read the existing formula and its release source before editing.
2. Verify whether the formula is source-built, bottle-based, or release-asset
   based.
3. Update all platform-specific URLs and checksums together.
4. Keep `test do` meaningful and cheap.
5. If a formula is pinned because upstream Homebrew does not provide the wanted
   version, preserve the pin unless the user explicitly asks to move it.

Useful commands:

```bash
ruby -c Formula/<name>.rb
brew style Formula/<name>.rb
brew test grantbirki/tap/<name>
brew install --build-from-source grantbirki/tap/<name>
```

Only run install or test commands that materially affect the local Homebrew
installation when the user asked for that level of validation or when it is
clearly necessary.

## Brewfile Workflow

The Brewfile is the new-machine install surface. When editing it:

- Keep comments short and useful.
- Prefer grouped entries over scattered one-off additions.
- Use fully qualified tap names for local pins and custom tap formulae/casks.
- Parse it after changes:

```bash
brew bundle list --file=Brewfile --all
brew bundle list --file=Brewfile --cask
```

Do not run `brew bundle install` as a routine validation step; it can install,
upgrade, or adopt software on the local machine.

## Script Conventions

Shell scripts in `script/` should follow the local pattern:

- `#!/usr/bin/env bash`
- `set -euo pipefail` for new scripts.
- Resolve paths relative to the script location, not the caller's current
  directory.
- Keep scripts idempotent where possible.
- Avoid hiding real failures with `|| true` unless the failure is explicitly
  expected and documented.
- Prefer one stable command per purpose instead of multiple divergent scripts.

If this repo gains Ruby helper code, introduce `script/env` before duplicating
environment setup across commands.

## Ruby Style

Current `.rb` files are Homebrew DSL, not general-purpose Ruby application code.
Follow Homebrew style first for those files.

If adding non-Homebrew Ruby code:

- Use `# frozen_string_literal: true`.
- Add a `Gemfile`, `Gemfile.lock`, `.bundle/config`, and vendored gems if
  external gems are needed.
- Add `script/bootstrap` behavior compatible with `bundle install --local`.
- Add `script/lint` with RuboCop and `script/test` with RSpec.
- Keep business logic in `lib/`, CLI entrypoints thin, and specs under `spec/`.
- Prefer standard library Ruby where it keeps the dependency surface smaller.

## Validation Matrix

Pick the smallest validation set that covers the change:

- Shell script edit:
  - `bash -n script/<name>`
- Brewfile edit:
  - `brew bundle list --file=Brewfile --all`
- Cask edit:
  - `ruby -c Casks/<token>.rb`
  - `brew style Casks/<token>.rb`
  - Homebrew cask loader parse check
- Formula edit:
  - `ruby -c Formula/<name>.rb`
  - `brew style Formula/<name>.rb`
  - `brew test grantbirki/tap/<name>` when appropriate
- Ruby project tooling edit, if added later:
  - `script/bootstrap`
  - `script/lint`
  - `script/test`
- Workflow edit:
  - `script/lint`
  - Confirm every `uses:` ref is a full 40-character commit SHA.

When validation cannot be run because it would install software, write outside
the workspace, require network access, or mutate local Homebrew state, say so
plainly and report the checks that were run instead.

## CI Design

The CI jobs are intentionally parse/lint-only. They should not install formulae,
casks, or Brewfile entries.

- `lint.yml` runs `script/lint`.
- `test.yml` runs `script/test`.
- Both workflows run on `macos-latest` because this is a Homebrew tap with cask
  validation.
- Both workflows set Homebrew environment variables to avoid analytics,
  auto-update, cleanup, and environment hints.
- The only action currently used is `actions/checkout`, pinned to an exact
  commit SHA.

## Dependency and Supply-Chain Posture

This repository is part of machine bootstrap, so be conservative:

- Do not add Ruby gems, npm packages, or other tooling unless the repo has a
  clear need for them.
- Prefer Homebrew's built-in Ruby APIs and CLI commands over custom parsers.
- Pin versions and checksums for local formulae/casks.
- Verify checksums against upstream release metadata, not arbitrary mirrors.
- Do not regenerate vendored dependencies or lockfiles unless the task is
  specifically about Ruby project infrastructure or dependency updates.

## Git and Local State

- Check `git status --short` before and after edits.
- Preserve user changes already present in the worktree.
- Do not revert unrelated files.
- Keep commits and PRs narrowly scoped if the user asks for them.
- If this repo is already mid-change, work with the existing edits instead of
  trying to reset to a clean baseline.

## Common Pitfalls

- `brew audit --changed` only works from a checkout Homebrew recognizes as an
  installed tap. In this workspace, direct path or changed audits may fail even
  when the cask parses correctly.
- `brew bundle list` prints sanitized cask names, so use Homebrew's Bundle DSL
  parse if you need to prove `full_name` stayed tap-qualified.
- Installing casks like Santa may prompt for privileges, install system
  extensions, or change security posture. Do not install them just to validate
  syntax.
- Latest upstream Homebrew cask metadata may not match a requested pin. The
  local cask is the source of truth for pinned bootstrap behavior.
