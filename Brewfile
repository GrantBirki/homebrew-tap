# Brewfile for GrantBirki's bootstrap tap
# Use this with `brew bundle --file=Brewfile`

# Ensure the tap is available locally so tap-specific formulae and casks can be installed
tap "grantbirki/tap"

# Refuse casks without a pinned checksum. Trust is granted per tap item below,
# not to every formula and cask the tap may contain in the future.
cask_args require_sha: true

# Shell
brew "grantbirki/tap/bash", trusted: true

### Personal Tools I Maintain ###

# CLI tool for macOS to uninstall an app from your system
brew "grantbirki/tap/uninstall", trusted: true

### Pinned CLI Tools ###

# YAML parser library
brew "grantbirki/tap/libyaml", trusted: true
# Display directories as trees
brew "grantbirki/tap/tree", trusted: true
# Infrastructure automation
brew "grantbirki/tap/ansible", trusted: true
# Display file contents with syntax highlighting
brew "grantbirki/tap/bat", trusted: true
# Device firmware update utility
brew "grantbirki/tap/dfu-programmer", trusted: true
# Modern, maintained replacement for ls
brew "grantbirki/tap/eza", trusted: true
# GitHub command-line tool
brew "grantbirki/tap/gh", trusted: true
# Audio/video processing toolkit
brew "grantbirki/tap/ffmpeg", trusted: true
# GNU Pretty Good Privacy package
brew "grantbirki/tap/gnupg", trusted: true
# Static site generator
brew "grantbirki/tap/hugo", trusted: true
# Network discovery and security scanner
brew "grantbirki/tap/nmap", trusted: true
# Vulnerability scanner backed by OSV
brew "grantbirki/tap/osv-scanner", trusted: true
# Pinentry for GPG on Mac
brew "grantbirki/tap/pinentry-mac", trusted: true
# Fast recursive search
brew "grantbirki/tap/ripgrep", trusted: true
# Reverse engineering framework
brew "grantbirki/tap/rizin", trusted: true
# Rust toolchain installer
brew "grantbirki/tap/rustup", trusted: true
# Swift formatter
brew "grantbirki/tap/swiftformat", trusted: true
# Swift linter
brew "grantbirki/tap/swiftlint", trusted: true
# Terraform version manager
brew "grantbirki/tap/tfenv", trusted: true
# Observability data pipeline (ARM macOS only)
if OS.mac? && RbConfig::CONFIG["host_cpu"] == "arm64"
  brew "grantbirki/tap/vector", trusted: true
end
# YAML processor
brew "grantbirki/tap/yq", trusted: true

### Version Managers ###

# Go version management
brew "goenv"
# Node.js version manager
brew "nodenv"
# Python version management
brew "pyenv"
# Ruby version manager
brew "rbenv"

### Casks ###

# GPU-accelerated terminal emulator
cask "grantbirki/tap/alacritty", trusted: true
# Persistence monitor
cask "grantbirki/tap/blockblock", trusted: true
# Endpoint instrumentation and scheduled host queries
cask "grantbirki/tap/osquery", trusted: true
# Reverse engineering platform powered by Rizin
cask "grantbirki/tap/cutter", trusted: true
# Pinned keyboard customiser from this tap
cask "grantbirki/tap/karabiner-elements", trusted: true
# Password manager app
cask "grantbirki/tap/keepassxc", trusted: true
# Image compression GUI
cask "grantbirki/tap/imageoptim", trusted: true
# https://formulae.brew.sh/cask/raspberry-pi-imager#default
cask "raspberry-pi-imager"
# Pinned KnockKnock version from this tap
cask "grantbirki/tap/knockknock", trusted: true
# Secure Enclave SSH agent
cask "grantbirki/tap/secretive", trusted: true
# Pinned Santa version from this tap
cask "grantbirki/tap/santa", trusted: true
