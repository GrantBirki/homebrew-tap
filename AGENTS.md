# AGENTS.md

Guidance for agents and other automated contributors working in this public
repository.

## Repository Mission

This is Grant's personal Homebrew tap and machine-bootstrap repository. It is
not a mirror of the latest Homebrew metadata. Its purpose is to let the owner
choose direct formula and cask roots deliberately, review each update, and
control when that update reaches a new machine.

Treat this repository as security-sensitive bootstrap infrastructure:

- Formulae and casks can execute code or install privileged components.
- The root **Brewfile** is the desired new-machine package inventory.
- **script/install** can update Homebrew, install software, reinstall packages,
  invoke cask hooks, and repoint receipts.
- The repository is public. Assume every file, commit, branch, pull request,
  workflow log, and generated artifact can be seen by anyone.

The design follows these principles:

- Vendor and review intentionally selected direct roots.
- Pin direct artifacts and recipes to immutable versions, commits, and SHA-256
  values.
- Separate release discovery from release adoption.
- Prefer checks that are deterministic, local, and non-installing.
- Keep the dependency and automation surface small.
- Fail closed when package provenance is unknown.
- Preserve macOS Gatekeeper and quarantine.

Read **SECURITY.md** before changing a version, URL, checksum, resource, patch,
bottle, provenance record, trust declaration, or installer behavior.

## Non-Negotiable Architecture

The following are deliberate decisions, not cleanup opportunities:

1. **Keep vendored direct formula roots.**
   Do not replace copied formulae with unqualified homebrew/core entries.
   Vendoring is how this repository controls when a direct root changes, why
   it changes, and which upstream recipe and artifacts are accepted.
2. **Keep tap-qualified Brewfile entries.**
   If the tap owns the selected version, use grantbirki/tap/<token>. Do not
   repoint it back to an official tap.
3. **Do not vendor or lock transitive dependencies.**
   Formula dependencies continue to resolve through Homebrew and may change
   after a Homebrew update.
4. **Do not turn the Brewfile into a lockfile.**
   Do not add a checked-in dependency closure, transitive version snapshot,
   Homebrew SBOM, or machine inventory.
5. **Do not reintroduce mutable formula inputs.**
   Vendored formulae must not expose head specs, moving branches, or
   checksum-less archives.
6. **Do not broaden trust to the entire tap.**
   Trust belongs on the exact Brewfile formula or cask item, not on the tap
   declaration.
7. **Do not bypass Gatekeeper.**
   Do not clear quarantine, approve an app with xattr, use no-quarantine, or
   add an equivalent bypass.
8. **Do not add install-time bottle attestation or automatic SBOM behavior.**
   Core bottle attestations are checked when a formula is imported or updated.
9. **Do not update a package as collateral work.**
   Security infrastructure changes must not silently move pinned versions.
10. **Do not add package dependencies or GitHub Actions casually.**
    Use the standard library, Homebrew APIs, and the existing vendored Ruby
    toolchain whenever possible.

If a request conflicts with one of these decisions, surface the conflict and
ask rather than silently redesigning the tap.

## Current Direct-Root Boundary

**provenance.yml** must cover every file under **Formula/** and **Casks/**
exactly once.

The current formula provenance families are:

- Core recipe snapshots:
  ansible, bash, bat, dfu-programmer, eza, ffmpeg, gnupg, hugo, libyaml,
  nmap, osv-scanner, pinentry-mac, ripgrep, rizin, rustup, swiftformat,
  swiftlint, tfenv, tree, and yq.
- Direct upstream release assets:
  gh, tart, and vector.
- Personal upstream release assets:
  uninstall and rust-template.

The default Brewfile contains 24 tap formulae. **rust-template** remains
available from the tap but intentionally stays outside the default Brewfile.

The ten tap casks in the default Brewfile are:

- alacritty
- blockblock
- cutter
- imageoptim
- karabiner-elements
- keepassxc
- knockknock
- osquery
- santa
- secretive

The personal **espresso**, **oneshot**, and **shit** casks are also provenance
tracked but intentionally remain outside the default Brewfile.

The official unqualified Brewfile entries are the version managers goenv,
nodenv, pyenv, and rbenv, plus raspberry-pi-imager. Do not qualify those with
this tap unless the owner explicitly decides to vendor them.

When the intentional inventory changes, update all relevant policy surfaces:

- The formula or cask file.
- **provenance.yml**.
- **Brewfile**, when it belongs in the default bootstrap.
- **FORMULA_TOKENS** or **CASK_TOKENS** in
  **lib/homebrew_tap/test_checks.rb**.
- Tests and documentation that describe the boundary.

The Brewfile policy rejects missing, extra, or duplicate tap entries so the
34-item trust boundary cannot widen silently.

## Sources of Truth

Use the following hierarchy:

- Formula and cask files define what Homebrew installs.
- **provenance.yml** defines which upstream recipe/release and direct
  artifacts were reviewed.
- **SECURITY.md** defines update, cooldown, signing, and exception policy.
- **Brewfile** defines the default machine-bootstrap inventory and item trust.
- **lib/homebrew_tap/** implements executable checks and the installer.
- **script/** commands are the stable operator and CI interfaces.

If documentation and executable policy disagree, stop and reconcile them in
the same change. Do not weaken a check merely to make stale metadata pass.

## Repository Layout

- **Formula/*.rb**
  - Vendored Homebrew formula DSL.
  - Stable inputs and retained bottles are immutable and checksum bound.
  - Core-derived bottle blocks use an explicit core GHCR root.
- **Casks/*.rb**
  - Vendored Homebrew cask DSL.
  - Pinned casks may intentionally differ from current homebrew/cask.
  - Personal unsigned casks preserve quarantine.
- **Brewfile**
  - Default bootstrap inventory.
  - Grants trust to exact tap items and globally requires cask SHA-256.
- **provenance.yml**
  - Versioned direct-artifact provenance manifest.
  - Never contains transitive dependency inventories.
- **SECURITY.md**
  - Human-readable threat model and update policy.
- **lib/homebrew_tap/provenance.rb**
  - Manifest validation and networked core bottle verification.
- **lib/homebrew_tap/installer.rb**
  - Homebrew 6 update, bundle install, repoint, and final receipt checks.
- **lib/homebrew_tap/receipts.rb**
  - Fail-closed installed receipt classification.
- **lib/homebrew_tap/test_checks.rb**
  - Deterministic supply-chain, parser, Brewfile, and workflow checks.
- **script/install**
  - Fresh-machine Bash wrapper that launches the Ruby installer with
    Homebrew's Ruby.
- **script/provenance**
  - Offline policy checking and explicit networked formula verification.
- **script/vulns**
  - Optional live vulnerability scan using an already-installed brew-vulns
    command.
- **script/env**
  - Shared project Ruby and Bundler environment.
- **script/bootstrap**
  - Installs only cached, vendored Ruby development dependencies.
- **script/lint** and **script/test**
  - Local CI entrypoints.
- **.github/workflows/**
  - Parse, policy, lint, and unit-test CI only. CI must not install Brewfile
    packages.

## Provenance Manifest

**provenance.yml** has schema version 1 and covers direct formula/cask
artifacts only.

Every entry contains:

- source_type
- local_file_sha256
- version
- release_published_at
- Primary-source release_evidence
- adopted_at
- adoption_commit
- A non-empty adoption_reason
- cooldown_exception
- legacy_baseline
- local_changes

Homebrew-derived entries additionally record:

- recipe_repository
- Full 40-character recipe_commit
- Exact recipe_path
- Full 40-character Git recipe_blob

Direct release entries additionally record:

- upstream_repository
- upstream_tag
- Full 40-character upstream_commit
- Direct release-asset SHA-256 values

Core formula entries also record:

- The bottle repository, which must be Homebrew/homebrew-core
- verified_at
- The exact retained bottle tag-to-digest map

Important invariants:

- **local_file_sha256** binds the whole checked-in formula or cask file. Even a
  comment or livecheck-only edit requires recalculating it.
- The legacy artifact fingerprint binds the pre-policy direct digest set. A
  legacy baseline cannot be carried forward to a later version or digest
  adoption.
- **local_changes** explains intentional differences from a recorded Homebrew
  recipe, such as removing head, omitting autobump metadata, or adding the
  explicit bottle root.
- The schema intentionally rejects unknown dependency or transitive keys.
- Do not invent recipe commits, blobs, release times, adoption commits, or
  verification timestamps.
- Do not use a current core commit for an older vendored recipe merely because
  it is convenient.

The existing adoption commits are historical commits that introduced the
current legacy baseline. A Git commit cannot contain its own SHA. For a future
adoption, do not fabricate this field: use a deliberate local two-commit
sequence where the metadata follow-up references the package-change commit, or
discuss a schema change with the owner. Do not push an incomplete intermediate
state.

## Offline Provenance Check

Run:

~~~bash
script/provenance check
~~~

This command is intended to be deterministic, non-installing, and safe for CI.
It:

- Parses YAML safely with aliases disabled.
- Requires one manifest entry per formula and cask with no extras.
- Validates commit/blob SHA formats, timestamps, reasons, and cooldown data.
- Recalculates each local file SHA-256.
- Validates legacy artifact fingerprints.
- Uses Homebrew's formula content loader for macOS ARM, macOS Intel, Linux ARM,
  and Linux Intel.
- Uses Homebrew's cask content loader for ARM and Intel.
- Compares parsed versions, bottle maps, and selected cask SHA-256 values with
  the manifest.
- Rejects head specs, insecure URLs, missing checksums, mutable Git revisions,
  quarantine removal, and unrecorded digest changes.

The content-loader subprocesses scope **HOMEBREW_NO_INSTALL_FROM_API=1** so
they read the checked-in recipes without fetching Homebrew package metadata.
Do not promote that setting to the workflow or installer environment generally.

## Release Cooldown

The policy took effect on June 11, 2026. Ordinary formula and cask releases
must age for 14 complete days between primary-source publication and adoption.

The owner-controlled **uninstall** formula and **espresso**, **oneshot**, and **shit** casks may be adopted immediately. The executable policy binds each exemption to an explicit formula or cask token, the **personal-release** source type, and its exact **GrantBirki/<repository>** pair. Other personal releases are not automatically exempt and require an explicit policy, code, test, and documentation change.

Owner-controlled releases still require exact tags and commits, primary-source release evidence, publication and adoption timestamps, independent artifact checksums, whole-file hashes, and installation review. Casks additionally require signing review and preserved quarantine. Their normal updates keep **cooldown_exception** empty because this is a standing ownership policy, not an incident exception.

Permitted exceptions are narrow:

- A verified vulnerability fix
- A compromised release response
- A signing-certificate revocation
- An invalid attestation
- A malicious-version withdrawal

An exception must contain:

- A concrete reason
- An HTTPS primary-source advisory, revocation, or incident reference

“Latest version available,” “Dependabot opened a PR,” or “livecheck found it”
is not a valid exception.

Existing pre-policy versions are recorded as legacy baselines. Once any
version or direct digest changes, the legacy exemption is no longer valid.

Prefer one formula or cask adoption per pull request unless releases are
inseparably coupled.

## Formula Update Workflow

For a core-derived vendored formula:

1. Read the current formula, manifest entry, and **SECURITY.md**.
2. Identify the exact upstream software release.
3. Record its publication time from a primary source.
4. Wait 14 complete days unless the formula is an explicitly allowlisted owner-controlled personal release or a valid documented exception applies.
5. Identify the exact historical Homebrew core recipe commit whose version,
   sources, resources, patches, and bottles correspond to the candidate.
6. Fetch the recipe by full commit, never from main, master, or HEAD.
7. Review the complete upstream recipe diff:
   dependencies, sources, resources, patches, build logic, tests, platform
   restrictions, and bottle rebuilds.
8. Preserve local hardening:
   no head spec, immutable Git revisions, and the explicit core bottle root.
9. Update the formula and all associated manifest evidence together.
10. Run the offline provenance check.
11. Verify every retained bottle with:

    ~~~bash
    script/provenance verify-formula <token>
    ~~~

12. Run the relevant repository checks without installing the formula.

For gh, vector, uninstall, and rust-template, use the exact upstream
release/tag commit and direct release-asset SHA-256 values rather than
inventing a Homebrew core recipe relationship.

Vector is intentionally restricted to ARM macOS. Preserve that platform
boundary unless upstream artifacts and an explicit owner decision support
expanding it. Parser checks should skip unsupported systems rather than
pretending the formula has a stable artifact there.

Stable formula requirements:

- Archive, resource, and external patch URLs use HTTPS.
- Archives, resources, and patches have SHA-256 values.
- Git stable sources use a full 40-character revision.
- Branches, default-branch references, HEAD, and moving refs are prohibited.
- A meaningful and cheap test block should remain when possible.

Do not run Homebrew install, reinstall, test, or a source build merely to
validate metadata unless the user explicitly authorizes the resulting machine
mutation.

## Core Bottle Verification

Networked bottle verification is an explicit adoption/operator action:

~~~bash
script/provenance verify-formula <token>
script/provenance verify-formula --all
~~~

It requires:

- An existing compatible GitHub CLI
- An authenticated GitHub session
- Network access

It never installs or upgrades the GitHub CLI.

The verifier:

- Confirms the recorded core recipe commit, path, and blob.
- Compares immutable source/resource/patch inputs with the local formula.
- Verifies every digest in the local bottle block.
- Uses Homebrew 6's supported verification path when the retained formula
  still matches current core metadata.
- Otherwise fetches the exact SHA-pinned bottle and verifies its GitHub
  attestation against Homebrew/homebrew-core.
- Requires the expected Homebrew core repository and bottle workflows.
- Requires the attested subject digest to equal the formula and manifest.
- Writes verified_at only after every requested formula and bottle succeeds.

Do not hand-edit verification timestamps. Do not record partial success.

If a retained bottle cannot be strictly verified:

1. Remove only that platform bottle entry.
2. Record the reason in provenance and local-change documentation.
3. Recalculate the formula's local SHA-256 and bottle map.
4. Let Homebrew build from the pinned source on that platform.

Do not silently fall back to checksum-only trust.

### Current libyaml Exception

Ten historical libyaml bottles were removed because their available
attestations were third-party backfills rather than attestations issued by
Homebrew/homebrew-core:

- arm64_sonoma
- arm64_ventura
- arm64_monterey
- arm64_big_sur
- sonoma
- ventura
- monterey
- big_sur
- catalina
- x86_64_linux

The retained libyaml bottles are arm64_tahoe, arm64_sequoia, and arm64_linux.
Do not reintroduce a removed tag without a valid strict core attestation and a
reviewed provenance update.

Downloaded bottles, attestation JSON, and cache paths are operator artifacts.
Never commit them.

## Cask Update Workflow

For a pinned cask:

1. Read the current cask and manifest entry.
2. Identify the exact upstream release and exact install asset.
3. When an upstream release tag exists, resolve it to a full 40-character
   commit. If no upstream tag/release exists, record the exact historical
   Homebrew cask recipe commit/blob and primary artifact metadata instead.
   ImageOptim 1.9.3 is the current example. Never invent a tag or commit.
4. Confirm the primary-source publication time.
5. Apply the 14-day cooldown unless this is an explicitly allowlisted owner-controlled personal release or a valid incident exception exists.
6. Prefer the GitHub release API digest when available.
7. Independently calculate the downloaded asset SHA-256.
8. Review the cask diff, install artifacts, uninstall behavior, and zap paths.
9. For signed software, verify Developer ID/Team ID, Gatekeeper, and
   notarization state.
10. For packages and privileged software, inspect signatures, helpers, system
    extensions, launch daemons, and uninstall hooks.
11. Update the cask and provenance entry together.
12. Run parser, provenance, style, and repository tests without installing the
    cask.

Treat blockblock, karabiner-elements, osquery, and santa as privileged casks.
Their installation or reinstallation may prompt for privileges or modify
system security state.

Secretive has multiple OS-specific versions and checksums. Preserve and
validate every supported platform branch; the current supported
Sonoma-or-newer version is the scalar manifest version.

Preserve user-facing application names, bundle identifiers, uninstall
directives, and zap paths unless package contents or primary release notes
prove they changed.

## Livecheck Is Discovery, Not Adoption

An active livecheck block does not update a cask, rewrite the repository, or
upgrade installed software. It only lets Homebrew report a newer upstream
release.

For current supported cask branches:

- Keep a working active livecheck so new releases are visible for review.
- Do not use livecheck skip as a pin or cooldown mechanism.
- Do not use livecheck throttle as a 14-day release-age control.
- Keep livecheck skip only for intentionally frozen legacy OS branches, such
  as Secretive's legacy branch.

The checked-in version and SHA-256, plus provenance review and the cooldown,
control adoption. A new livecheck result does not change those values.

Homebrew's official autobump service applies to official repositories, not
this personal tap. This repository has no autobump workflow. Homebrew 6 also
rejects the no_autobump DSL in non-official taps, so do not add it here. If a
repository-specific bump bot is intentionally added later, configure that
automation itself to create proposal-only changes and require the provenance,
cooldown, and review gates. Keep active livecheck discovery.

Homebrew pinning is a separate, operator-local choice. This repository does
not run Homebrew pin commands. Use a local pin only when the operator wants to
block an installed package from moving even after a future reviewed tap update.

In-application updaters are separate from Homebrew livecheck and upgrade
behavior. The installer must not change application preferences:

- ImageOptim can update itself; disable its updater manually when the tap pin
  must control the running version.
- Karabiner-Elements can check for updates on startup; manage that preference
  in the application.

## Gatekeeper and Quarantine

The repository preserves macOS security decisions:

- Do not add quarantine-clearing postflight hooks.
- Do not run xattr approval commands.
- Do not replace those hooks with no-quarantine or another bypass.
- Personal unsigned casks require explicit operator approval after install.

Alacritty's September 1, 2026 disable declaration is intentional because the current pinned artifact fails Gatekeeper checks. Do not remove the declaration unless upstream signing is fixed and the new artifact is reviewed under the normal adoption policy.

## Brewfile Trust Model

The Brewfile must retain an untrusted tap declaration and:

~~~ruby
cask_args require_sha: true
~~~

The tap declaration must not set whole-tap trust.

Every tap-qualified formula and cask in the Brewfile must individually set:

~~~ruby
trusted: true
~~~

This gives Homebrew 6 permission to use the exact selected items without
trusting every future item added to the tap.

For an existing machine that trusts the whole tap, the documented migration is:

~~~bash
brew untrust grantbirki/tap
script/install
brew trust
~~~

Do not run the untrust step by itself during implementation. Without the real
installer immediately establishing item trust, that leaves the machine in a
partially migrated state.

Use Homebrew's Bundle DSL parser or the repository tests to prove tap
qualification and trust. Homebrew's bundle list output may sanitize names and
is not sufficient evidence by itself.

## Installer Design

**script/install** must work on a fresh machine before the project Ruby is
installed. It therefore:

- Is a small Bash wrapper.
- Checks that Homebrew exists.
- Launches repository Ruby code through Homebrew's Ruby.
- Passes the absolute Homebrew executable into the Ruby process.
- Requires Homebrew tap trust enforcement.

The wrapper scopes **HOMEBREW_NO_INSTALL_FROM_API=1** only to starting
Homebrew's Ruby, then deletes it inside the Ruby entrypoint before child
Homebrew commands. This avoids local-content bootstrap problems without
disabling Homebrew 6's API for normal metadata or installation operations. Do
not widen that environment setting without a demonstrated need.

The Ruby installer:

1. Parses arguments and validates Homebrew/Brewfile availability.
2. Inspects all tap-qualified receipts before mutation.
3. Refuses to continue if an existing receipt is malformed or lacks source
   provenance.
4. Runs a stable-tag Homebrew update unless no-update was selected.
5. Requires Homebrew 6 or newer after the update decision.
6. Ensures the tap is available. If the working repository is itself the
   active tap path, Homebrew uses it directly. Otherwise the installer
   temporarily checks out this repository's **committed HEAD** in the installed
   tap checkout and restores the previous tap state afterward. Uncommitted
   formula/cask changes are not transferred to a separate tap checkout.
7. Runs the Brewfile bundle install before repointing so item trust is
   established.
8. Reinstalls wrong-tap entries toward grantbirki/tap unless no-repoint was
   selected.
9. Rescans receipts and fails if a tap-qualified entry still resolves to
   another tap.

Supported operator flags are:

- **--dry-run** to report all actions without mutation
- **--no-repoint** to keep packages sourced from another tap
- **--no-update** to skip the tagged Homebrew update
- **--help** for usage

Receipt reporting includes:

- Installed version
- Current source tap
- Target version
- Target tap
- A downgrade marker when applicable
- A privileged marker for the four privileged casks

Do not add an interactive confirmation prompt to normal repointing. The
operator review surface is the dry run.

The dry run must not execute:

- A Homebrew update
- A tap mutation
- A Brewfile bundle install
- A reinstall
- Cask hooks or privileged operations

It may read Homebrew metadata and installed receipts to report the complete
plan.

Do not add installer-time attestation, vulnerability scanning, SBOM
generation, application preference changes, or transitive locking.

Never run the real installer as routine validation. Use:

~~~bash
script/install --dry-run
~~~

Only run a real install or repoint when the user explicitly authorizes machine
changes.

## Floating Transitive Dependencies

Formula dependencies resolve normally through Homebrew.

This means:

- Direct roots are pinned and review gated.
- Transitive formulae can move after a Homebrew update.
- Builds and complete machine installations are not hermetic.
- A direct root can begin using a changed transitive without a commit here.

This is an accepted limitation.

Do not respond to a transitive vulnerability by automatically vendoring that
library. When Homebrew publishes a fixed transitive, take the fix through
Homebrew. If a high-impact issue lacks a fix, consider temporarily removing
the affected direct root from the Brewfile rather than expanding ownership.

Homebrew SBOM generation remains an optional local operator choice. Do not set
it in the repository or commit its output.

## Vulnerability Operator Command

**script/vulns** is intentionally live, network dependent, and outside
ordinary CI.

It:

- Requires an already-installed brew-vulns command.
- Never installs or updates the scanner.
- Scans the absolute root Brewfile, resolved dependencies, and high severity.
- Preserves the scanner's exit status.
- Warns that skipped source URLs are a coverage gap.
- Warns that formula source scanning does not establish cask binary safety.

Preserve its exit-code contract:

- 0 means no findings
- 1 means findings
- 2 means the scan could not run

Do not commit raw scanner output or a complete machine package inventory. A
small, reviewed, non-sensitive policy summary may be documented when the owner
explicitly wants durable context, as in **SECURITY.md**. Include only facts
needed to explain repository decisions; omit host details and unrelated
package inventory.

The June 2026 baseline interpretation is documented in **SECURITY.md**. pcre2
and p11-kit remain Homebrew-managed transitives; they were not added to this
tap.

## Ruby Development Toolchain

This repository contains Ruby helper and installer code under **lib/** with
RSpec tests under **spec/**.

Use a sibling **ruby-template** checkout as an optional local style reference
when it is available, but follow this repository's existing interfaces first.

Project conventions:

- Use the frozen-string-literal comment.
- Keep command entrypoints thin and implementation under
  **lib/homebrew_tap/**.
- Use **script/env** for shared Ruby version, rbenv, and Bundler setup.
- Use standard-library Ruby where practical.
- Keep public command interfaces stable.
- Add focused RSpec coverage for behavioral changes.
- The suite enforces complete line coverage for loaded repository Ruby.

The Ruby development bundle is:

- Exact-version locked in **Gemfile.lock**
- Checksum locked
- Fully cached under **vendor/cache**
- Installed locally under **vendor/gems**
- Isolated from system gems
- Not used by end-user formula or cask installation

Do not add or update gems without explicit user consent. When dependency work
is authorized, use exact versions, update lockfile checksums and cached gems
together, and preserve offline bootstrap.

**script/bootstrap** may install only the already-vendored development bundle.
It must not install Homebrew formulae or casks.

Dependabot has a 45-day cooldown for the vendored Ruby toolchain and
SHA-pinned Actions. Security alerts require manual review; do not wait for a
cooldown-generated pull request.

## Script Conventions

New shell scripts should:

- Use the env bash shebang.
- Use strict Bash error handling.
- Resolve paths relative to the script, not the caller's current directory.
- Source **script/env** when using the project Ruby/Bundler environment.
- Remain idempotent where practical.
- Preserve meaningful exit codes.
- Avoid hiding errors unless the failure is expected and documented.
- Never install missing tools implicitly.

**script/install** is the exception to the project-Ruby rule because it must
use Homebrew's Ruby on a fresh machine.

## Stable Commands

Use these repository interfaces instead of ad hoc equivalents:

~~~bash
script/bootstrap
script/lint
script/test
script/provenance check
script/provenance verify-formula <token>
script/provenance verify-formula --all
script/install --dry-run
script/vulns
~~~

Mutation and network characteristics:

| Command | Network | Installs/repoints packages | Notes |
|---|---:|---:|---|
| script/lint | Normally no | No | Homebrew style may refresh Homebrew's own internal developer bundle. |
| script/test | No | No | Parses local recipes and runs policy/unit tests. |
| script/provenance check | No | No | Local manifest and content-loader policy gate. |
| script/provenance verify-formula | Yes | No | Fetches bottles, verifies attestations, and updates verified_at. |
| script/install --dry-run | No expected | No | Reads receipts and reports planned operations. |
| script/install | Yes | Yes | Explicit operator action only. |
| script/vulns | Yes | No | Live OSV-backed operator scan. |

If Homebrew style refreshes Homebrew's internal development gems, do not claim
the command was completely side-effect free. It does not change this
repository's bundle, but it can write under Homebrew and use the network.

## Validation Matrix

Choose the smallest non-mutating set that covers the change:

| Change | Required checks |
|---|---|
| Documentation only | Review rendered text and public-safety implications |
| Shell script | Bash syntax plus focused specs |
| Ruby helper/installer | Focused RSpec, then script/lint and script/test |
| Workflow | script/lint and exact external Action SHA review |
| Brewfile | script/test; verify exact item trust and no broad tap trust |
| Formula metadata | provenance check, lint, and test |
| Formula version/source/resource/bottle | Formula checks plus networked bottle verification |
| Cask metadata | provenance check, lint, and test |
| Cask version/artifact | Cask checks plus primary-source checksum/signing review |
| Installer | Focused specs and dry run; never a real install by default |
| Vendored Ruby dependencies | Explicit authorization, bootstrap, lint, and test |

**script/test** already performs:

- Bundler isolation, cache, and checksum checks
- Provenance manifest validation
- Exact GitHub Actions pin validation
- Ruby and shell syntax
- Formula parsing under macOS ARM, macOS Intel, Linux ARM, and Linux Intel
- Cask parsing under ARM and Intel
- Brewfile parsing and exact item-trust policy
- RSpec

Do not paste long successful validation transcripts into routine responses.
State what passed or what could not be run.

## CI Design

CI is intentionally non-installing.

- Workflows and jobs are named lint and test.
- Jobs intentionally run on GitHub's moving macos-latest label. The runner OS
  may change during GitHub's announced migration windows; keep the explicit
  stable Homebrew 6 update, exact project Ruby, local content parsing, and
  SHA-pinned Actions as the reproducibility boundary.
- Jobs have a 20-minute timeout.
- Workflow permissions are read-only contents.
- Checkout does not persist credentials.
- External Actions are full-SHA pinned.
- Homebrew is explicitly updated to a stable tag.
- CI asserts Homebrew 6 or newer.
- Automatic Homebrew updates are disabled after the explicit update.
- Formula/cask validation uses local content; CI does not install them.
- CI does not run a Brewfile bundle install.
- CI does not install or run brew-vulns.

The only allowed Actions are:

- actions/checkout
- ruby/setup-ruby

Do not add a runner-hardening or other third-party Action without a concrete
need and explicit review. Prefer shell or existing repository code.

## Live GitHub Repository Controls

These are external settings, not fully represented by checked-in files. Verify
them live before claiming their state.

The intended and currently observed controls are:

- Actions restricted to actions/checkout and ruby/setup-ruby
- Repository-wide SHA pinning required
- Read-only workflow token
- Workflow pull-request approval disabled
- Secret scanning enabled
- Push protection enabled
- Dependabot security updates enabled
- Private vulnerability reporting enabled
- Required signed commits
- Strict required lint and test checks
- Code-owner review and one approval
- Deletion and non-fast-forward protection

GitHub currently leaves non-provider secret patterns and secret validity
checks disabled for this user-owned public repository because those enhanced
Secret Protection features require eligible organization ownership and plans.
Do not claim they are enabled merely because an API update returned success.
Recheck eligibility if repository ownership or plan changes.

## Public Repository Safety

This repository is public. In addition to global personal-repository safety
rules:

- Never commit credentials, GitHub authentication output, private keys,
  tokens, or environment dumps.
- Never commit raw machine package inventories, Homebrew receipts, raw
  vulnerability output, SBOMs, downloaded bottles, attestation payloads,
  caches, or local absolute-path reports. A deliberately reviewed,
  non-sensitive policy summary is allowed when explicitly requested.
- Never copy non-public material from another repository or conversation.
- Keep examples generic and source only public upstream evidence.
- Review untracked files as carefully as tracked diffs.
- Review branch names, commit messages, authorship, trailers, pull-request
  text, and comments before publication.
- Do not use a codex/ branch prefix.
- Use the repository-local personal commit email. Do not rewrite published
  history or add a mailmap that republishes a private or employer address.

Before any commit, push, or pull request:

1. Review the complete staged diff and untracked files.
2. Search for secrets and private or internal references.
3. Confirm no machine inventory or scan output is included.
4. Review every commit in the branch, not only the final working-tree diff.
5. Review the branch name, commit metadata, PR title/body, and proposed
   comments.

Do not commit, push, or open a pull request unless the user asks.

## Git and Local State

- Run Git status before and after edits.
- Preserve existing user changes.
- Do not reset, revert, or overwrite unrelated work.
- Work with an existing dirty tree rather than pretending it is clean.
- Keep changes and commits narrowly scoped.
- Recalculate provenance local hashes after any formula or cask edit.
- Do not amend or rewrite published history without explicit authorization.

## Common Pitfalls

- **Livecheck is not an updater.**
  An active livecheck reports releases; it does not change the pin or install
  an update. Do not add a livecheck skip merely to preserve a pin.
- **Any formula or cask text edit changes provenance.**
  Comments, livecheck changes, and formatting change local_file_sha256.
- **Bottle verification timestamps are evidence.**
  Never set verified_at without a successful complete verification.
- **A removed bottle is not a removed formula.**
  Homebrew builds from the pinned source on that platform.
- **A checksum is not an attestation.**
  Retained core bottles need both the recorded digest and valid core
  provenance.
- **Homebrew audit may reject this checkout.**
  If Homebrew does not recognize it as an installed tap, use content-loader
  parsing, style, Ruby syntax, and repository policy checks. Do not claim an
  audit passed when it did not run.
- **Bundle list output can sanitize names.**
  Use the Bundle DSL or repository tests to prove full names and trust.
- **Secretive is platform conditional.**
  Do not collapse its legacy versions or checksums into the current branch.
- **Privileged casks are not syntax-only software.**
  Never install Santa, osquery, BlockBlock, or Karabiner-Elements solely for
  validation.
- **Homebrew APIs and local content are different surfaces.**
  Keep no-install-from-API behavior narrowly scoped to local parser/bootstrap
  cases rather than disabling Homebrew 6 APIs globally.
- **Homebrew style can have external tooling side effects.**
  It may refresh Homebrew's own internal developer gems.
- **The real installer mutates the machine.**
  Use the dry run unless real installation or repointing is requested.
- **Whole-tap untrust is a coordinated migration.**
  Do not run it without immediately establishing item trust through an
  authorized real install.
- **An upstream latest recipe is not historical provenance.**
  Match the exact recipe commit and blob for the vendored version.

## Design References

- [Homebrew 6.0.0](https://brew.sh/2026/06/11/homebrew-6.0.0/)
- [Homebrew Supply Chain Security](https://docs.brew.sh/Supply-Chain-Security)
- [Homebrew Tap Trust](https://docs.brew.sh/Tap-Trust)
- [Homebrew Livecheck](https://docs.brew.sh/Brew-Livecheck)
- [Homebrew Autobump](https://docs.brew.sh/Autobump)
- [Less is safer](https://obsidian.md/blog/less-is-safer/)
- [Hermetic Builds](https://software.birki.io/posts/hermetic-builds/)
