class RustTemplate < Formula
  desc "Minimal hello-world Rust CLI template"
  homepage "https://github.com/GrantBirki/rust-template"
  version "0.1.0"
  license "MIT"

  on_macos do
    url "https://github.com/GrantBirki/rust-template/releases/download/v#{version}/rust-template_v#{version}_darwin-universal.tar.gz"
    sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  end

  on_linux do
    on_intel do
      url "https://github.com/GrantBirki/rust-template/releases/download/v#{version}/rust-template_v#{version}_linux-amd64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    end
    on_arm do
      url "https://github.com/GrantBirki/rust-template/releases/download/v#{version}/rust-template_v#{version}_linux-arm64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    end
  end

  def install
    bin.install "rust-template"

    bash_completion.install "completions/bash/rust-template" if File.exist?("completions/bash/rust-template")
    zsh_completion.install "completions/zsh/_rust-template" if File.exist?("completions/zsh/_rust-template")
    fish_completion.install "completions/fish/rust-template.fish" if File.exist?("completions/fish/rust-template.fish")
    man1.install "man/rust-template.1" if File.exist?("man/rust-template.1")
  end

  test do
    assert_match "Hello", shell_output("#{bin}/rust-template --name Homebrew")
  end
end
