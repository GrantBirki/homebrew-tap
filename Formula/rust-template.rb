class RustTemplate < Formula
  desc "Minimal hello-world Rust CLI template"
  homepage "https://github.com/GrantBirki/rust-template"
  version "0.1.7"
  license "MIT"

  on_macos do
    url "https://github.com/GrantBirki/rust-template/releases/download/v#{version}/rust-template_v#{version}_darwin-universal.tar.gz"
    sha256 "05398a85be971589099437cc79035ba4306fe9ea3ee52297f5d900ebce8c0b4a"
  end

  on_linux do
    on_intel do
      url "https://github.com/GrantBirki/rust-template/releases/download/v#{version}/rust-template_v#{version}_linux-amd64.tar.gz"
      sha256 "94d882051083b18e91c66ba88e48f5c12712fbcc212327a117fb397638a485af"
    end
    on_arm do
      url "https://github.com/GrantBirki/rust-template/releases/download/v#{version}/rust-template_v#{version}_linux-arm64.tar.gz"
      sha256 "738e48bff7009c6cc60dbef88cd11674eab50c4d3267dc854354680343c736a9"
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
