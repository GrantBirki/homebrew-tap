# Security policy

This tap is a machine-bootstrap repository. Its security model deliberately
vendors selected direct formulae and casks so their updates can be reviewed and
adopted on an explicit schedule.

Report a suspected vulnerability through GitHub's private vulnerability
reporting for this repository. Do not open a public issue containing exploit
details, credentials, or private machine information.

## Trust boundary

The tap controls its direct roots:

- Formulae selected in `Brewfile` are installed from `grantbirki/tap` rather
  than silently following `homebrew/core`.
- Casks selected in `Brewfile` are exact versions with SHA-256 checksums.
- `provenance.yml` binds each checked-in formula and cask to its reviewed
  upstream recipe or release.

Transitive formula dependencies are intentionally outside this boundary. They
are not vendored, locked, recorded, or drift-checked and may change after a
Homebrew update. The Brewfile is therefore not a lockfile, and a complete
Homebrew installation is not hermetic.

The repository does not generate or commit Homebrew SBOMs, dependency
closures, vulnerability output, or machine package inventories. Operators may
enable `HOMEBREW_SBOM=1` locally when they need a machine-specific snapshot.

## Update policy

Ordinary formula and cask releases must age for 14 complete days after their primary-source publication time before adoption. The `uninstall` formula and the `espresso`, `oneshot`, and `shit` casks are explicitly owner-controlled and may be adopted immediately only when the provenance source type is `personal-release` and the upstream repository matches the exact token-to-repository pair in the executable allowlist. Other personal releases are not automatically exempt.

Owner-controlled releases still require an immutable tag and commit, primary-source release evidence, publication and adoption timestamps, an independently verified asset SHA-256, a whole-file hash, and review of installation behavior. Casks additionally require review of signing and quarantine behavior. Discovery is separate from adoption: livecheck may report a release immediately, but it does not change a pin. Their normal updates keep `cooldown_exception` empty because this is a standing ownership policy, not an incident exception.

A cooldown may be bypassed only for a verified vulnerability fix, compromised
release response, signing-certificate revocation, invalid attestation, or
malicious-version withdrawal. The provenance entry and pull request must name
the primary-source advisory or revocation and explain the exception. "Latest
version available" is not an exception.

For a vendored formula update:

1. Select the exact upstream release and exact 40-character
   `Homebrew/homebrew-core` recipe commit, never a moving branch.
2. Confirm the release publication time and wait through the cooldown unless a
   documented exception applies.
3. Review source URLs, checksums, resources, patches, dependency declarations,
   platform support, tests, and bottle changes.
4. Preserve local hardening: no `head` spec and an explicit
   `https://ghcr.io/v2/homebrew/core` bottle root for copied core bottles.
5. Update `provenance.yml` with the upstream commit/blob, local file hash,
   release and adoption times, and a specific adoption reason.
6. Verify every retained core bottle against Homebrew's attestation before
   adoption. If a bottle cannot be verified, remove that platform's bottle and
   build from the pinned source rather than falling back to checksum-only trust.

Run the networked verification only as an explicit operator step:

```bash
script/provenance verify-formula <token>
# or, for a full re-verification:
script/provenance verify-formula --all
```

The command requires an existing compatible `gh` installation and an
authenticated GitHub session. It never installs or upgrades `gh`. The offline
`script/provenance check` remains the CI-safe policy gate.

Prefer one formula update per pull request unless formulae are inseparably
coupled. Do not vendor a transitive dependency merely because a direct root
uses it.

For a cask update, apply the cooldown unless it is one of the explicitly allowlisted owner-controlled personal releases. Verify the exact primary-source asset and independently calculate its SHA-256. Prefer the GitHub release API digest when available. For signed applications, also verify Gatekeeper/notarization, Developer ID, and Team ID. Review package signatures, privileged helpers, system extensions, launch daemons, and uninstall behavior for privileged casks.

## Gatekeeper and application updates

This tap does not clear `com.apple.quarantine` or otherwise bypass Gatekeeper. The personal Espresso, OneShot, and Shit casks are not part of the default Brewfile. OneShot and Shit are Developer ID signed and notarized and must pass Gatekeeper normally; unsigned releases require explicit macOS approval after installation.

Alacritty remains scheduled for Homebrew disablement on September 1, 2026 because its current artifact fails Gatekeeper checks. The disable declaration must remain unless upstream fixes its signing and a replacement artifact is reviewed under the normal adoption policy.

Some applications can move independently of their cask pin:

- ImageOptim supports automatic Sparkle updates. Disable automatic updates in
  the application when this tap's pin must control the running version.
- Karabiner-Elements checks for updates on startup but does not currently
  install them silently. Its update check can be disabled in its settings.

The installer does not modify application preferences.

## Homebrew 6 item trust

`Brewfile` grants `trusted: true` only to the exact tap-qualified formulae and
casks it installs. It does not trust the entire tap, so a future item added to
the repository does not become executable merely because the tap is present.

For a machine that already trusts the whole tap, migrate once:

```bash
brew untrust grantbirki/tap
script/install
brew trust
```

Review the final list and confirm the whole `grantbirki/tap` is absent while
the expected formulae and casks are individually present.

## Automated dependency updates

Dependabot proposals for the vendored Ruby development bundle and SHA-pinned
GitHub Actions use a 45-day cooldown. A Dependabot security alert must be
handled manually and immediately; do not wait for the cooldown-generated pull
request. Automatic merging remains disabled.

The development Ruby bundle is exact-versioned, checksum-locked, fully cached,
and installed locally. End-user formula and cask installation does not use it.

## Vulnerability scanning

`script/vulns` is an optional operator check for high-severity findings in the
Brewfile's formula roots and their currently resolved dependencies. It uses an
already-installed `brew vulns` command and never installs the scanner.

Skipped packages are a coverage limitation, not evidence that they are safe.
The source-based scan also does not establish the safety of cask binaries;
checksum, signature, Gatekeeper, and release review remain separate controls.

For the June 2026 baseline scan, `pcre2` was a Homebrew-managed transitive of
selected roots including ripgrep and Nmap, while `p11-kit` was
Homebrew-managed through the GnuPG/GnuTLS dependency path. No fixed stable
release was identified for either reported issue during that audit, so neither
dependency is vendored here. The reported `icu4c@78`, OpenJPEG, Boost, jq, and
libheif packages belonged to other machine-level roots rather than this
Brewfile.

When Homebrew publishes a fixed transitive, take it through Homebrew. If a
high-impact issue has no fix, consider temporarily removing the affected
direct root instead of expanding this tap to own the vulnerable library.
