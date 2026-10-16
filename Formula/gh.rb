class Gh < Formula
  desc "GitHub command-line tool"
  homepage "https://cli.github.com/"
  version "2.102.0"
  license "MIT"

  depends_on :macos

  on_macos do
    on_arm do
      url "https://github.com/cli/cli/releases/download/v#{version}/gh_#{version}_macOS_arm64.zip"
      sha256 "da922c20d1792e5b2cbf375593d7a658acf034c12c84e007e71c76ef959c337e"
    end

    on_intel do
      url "https://github.com/cli/cli/releases/download/v#{version}/gh_#{version}_macOS_amd64.zip"
      sha256 "b245f24eb2bf5f75b426b4c26da3651a107f8d5b6f4fddfbfccc5679041378b3"
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
