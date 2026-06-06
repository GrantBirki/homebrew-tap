class Gh < Formula
  desc "GitHub command-line tool"
  homepage "https://cli.github.com/"
  version "2.93.0"
  license "MIT"

  depends_on :macos

  on_macos do
    on_arm do
      url "https://github.com/cli/cli/releases/download/v#{version}/gh_#{version}_macOS_arm64.zip"
      sha256 "a86be4e0a86c26456cf71177d6572d6f1165cf1679e532b72f7f15918ee51fd2"
    end

    on_intel do
      url "https://github.com/cli/cli/releases/download/v#{version}/gh_#{version}_macOS_amd64.zip"
      sha256 "009425b9d175c482037fe25181817fd6b1ea3ae1f51cfae0e18f29f33d3152ac"
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
