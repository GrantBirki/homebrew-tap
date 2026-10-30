class Gh < Formula
  desc "GitHub command-line tool"
  homepage "https://cli.github.com/"
  version "2.102.1"
  license "MIT"

  depends_on :macos

  on_macos do
    on_arm do
      url "https://github.com/cli/cli/releases/download/v#{version}/gh_#{version}_macOS_arm64.zip"
      sha256 "08bfef98b50c553df122bb34ee8dcf415cae7d3b108891488964a0df07aa2aeb"
    end

    on_intel do
      url "https://github.com/cli/cli/releases/download/v#{version}/gh_#{version}_macOS_amd64.zip"
      sha256 "91c5fbd493274b545b03ef32a89c2a21238393c0c0b1108210967199b3230d9d"
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
