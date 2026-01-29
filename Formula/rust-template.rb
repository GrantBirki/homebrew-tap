class RustTemplate < Formula
  desc "Minimal hello-world Rust CLI template"
  homepage "https://github.com/GrantBirki/rust-template"
  version "0.2.0"
  license "MIT"

  on_macos do
    url "https://github.com/GrantBirki/rust-template/releases/download/v#{version}/rust-template_v#{version}_darwin-universal.tar.gz"
    sha256 "0e92863648891e58be2f668439550526b12e6867b8dbeea1d70ea05a7dcf300c"
  end

  on_linux do
    on_intel do
      url "https://github.com/GrantBirki/rust-template/releases/download/v#{version}/rust-template_v#{version}_linux-amd64.tar.gz"
      sha256 "9ed344b2eaec47f1820de277f13bfab0cf611c6d2511203f13727172142e7352"
    end
    on_arm do
      url "https://github.com/GrantBirki/rust-template/releases/download/v#{version}/rust-template_v#{version}_linux-arm64.tar.gz"
      sha256 "c2a75a054d1655944f971de81ca5230a651a355713894ef671d08bc754ba912e"
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
