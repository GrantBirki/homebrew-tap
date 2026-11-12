cask "goreleaser" do
  arch arm: "arm64", intel: "x86_64"

  version "2.20.2"
  sha256 arm:   "4e68482f6bbdb2d3ce7f835be50a4eb7287ee999cefc563c49c5f42ad3778c78",
         intel: "58814536817f6ad787607ed7dfc9e774b3f1334dcffc87002ae2a54fd7b5c5c1"

  url "https://github.com/goreleaser/goreleaser/releases/download/v#{version}/goreleaser_Darwin_#{arch}.tar.gz"
  name "GoReleaser"
  desc "Release engineering, simplified"
  homepage "https://goreleaser.com/"

  livecheck do
    url :url
    strategy :github_latest
  end

  conflicts_with cask: "goreleaser-pro"

  depends_on :macos

  binary "goreleaser"
  manpage "manpages/goreleaser.1.gz"
  bash_completion "completions/goreleaser.bash"
  zsh_completion "completions/goreleaser.zsh"
  fish_completion "completions/goreleaser.fish"

  zap :not_required
end
