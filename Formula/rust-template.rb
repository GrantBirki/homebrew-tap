class RustTemplate < Formula
  desc "Minimal hello-world Rust CLI template"
  homepage "https://github.com/GrantBirki/rust-template"
  version "0.1.6"
  license "MIT"

  on_macos do
    url "https://github.com/GrantBirki/rust-template/releases/download/v#{version}/rust-template_v#{version}_darwin-universal.tar.gz"
    sha256 "bb0ee285fcbdabbf6f483f39031a18e7b46d62017d4b360570b7e92cc70b86df"
  end

  on_linux do
    on_intel do
      url "https://github.com/GrantBirki/rust-template/releases/download/v#{version}/rust-template_v#{version}_linux-amd64.tar.gz"
      sha256 "b84607c7b8cccb68ee7453c37c8eeded5c395bb1f02626b84f9e42f09a256b44"
    end
    on_arm do
      url "https://github.com/GrantBirki/rust-template/releases/download/v#{version}/rust-template_v#{version}_linux-arm64.tar.gz"
      sha256 "d272ede47a3f4bd1931ed92579ca591af4bf9baa19ccac2d3b4c23339f84044c"
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
