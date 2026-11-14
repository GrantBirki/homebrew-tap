class Gh < Formula
  desc "GitHub command-line tool"
  homepage "https://cli.github.com/"
  version "2.103.3"
  license "MIT"

  depends_on :macos

  on_macos do
    on_arm do
      url "https://github.com/cli/cli/releases/download/v#{version}/gh_#{version}_macOS_arm64.zip"
      sha256 "d700207eae9ae98fe2b89535c2c087c07823d4628c56364695a5a07ef311c062"
    end

    on_intel do
      url "https://github.com/cli/cli/releases/download/v#{version}/gh_#{version}_macOS_amd64.zip"
      sha256 "a2f86418f4350ae6e9ec60d5000bdf7665728436946a97fc27fe50e6ae752682"
    end
  end

  def install
    bin.install "bin/gh"
    man1.install Dir["share/man/man1/gh*.1"]
  end

  test do
    assert_match "gh version #{version}", shell_output("#{bin}/gh --version")
    assert_match "Work with GitHub issues", shell_output("#{bin}/gh issue 2>&1")
  end
end
