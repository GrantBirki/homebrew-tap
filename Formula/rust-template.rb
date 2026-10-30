class RustTemplate < Formula
  desc "Minimal hello-world Rust CLI template"
  homepage "https://github.com/GrantBirki/rust-template"
  version "0.4.0"
  license "MIT"

  on_macos do
    on_intel do
      url "https://github.com/GrantBirki/rust-template/releases/download/v#{version}/rust-template_v#{version}_darwin-universal.tar.gz"
      sha256 "3de93c15e1b7f9f06eb4680e1ace37eb53d2e1b020b5d88494688128906d43ed"
    end

    on_arm do
      url "https://github.com/GrantBirki/rust-template/releases/download/v#{version}/rust-template_v#{version}_darwin-universal.tar.gz"
      sha256 "3de93c15e1b7f9f06eb4680e1ace37eb53d2e1b020b5d88494688128906d43ed"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/GrantBirki/rust-template/releases/download/v#{version}/rust-template_v#{version}_linux-amd64.tar.gz"
      sha256 "e718214ad30759e8b237ace1ce242470cfcd3bd7415d8d7411e6643156267b7a"
    end
    on_arm do
      url "https://github.com/GrantBirki/rust-template/releases/download/v#{version}/rust-template_v#{version}_linux-arm64.tar.gz"
      sha256 "b91b6aef3af32084b537be990ea085a9d20b7e6737bf8b4554bda0c28617af93"
    end
  end

  def install
    bin.install "rust-template"

    bash_completion.install "completions/bash/rust-template" if File.exist?("completions/bash/rust-template")
    zsh_completion.install "completions/zsh/_rust-template" if File.exist?("completions/zsh/_rust-template")
    if File.exist?("completions/fish/rust-template.fish")
      fish_completion.install "completions/fish/rust-template.fish"
    end
    man1.install "man/rust-template.1" if File.exist?("man/rust-template.1")
  end

  test do
    assert_match "Hello", shell_output("#{bin}/rust-template --name Homebrew")
  end
end
