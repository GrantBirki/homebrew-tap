class Uninstall < Formula
  desc "CLI tool for macOS to uninstall an app from your system"
  homepage "https://github.com/GrantBirki/uninstall"
  url "https://github.com/GrantBirki/uninstall/releases/download/v1.3.0/uninstall-1.3.0.tar.gz"
  version "1.3.0"
  sha256 "11d43cbd698d21972f67e99f7ecf20e0b56e20204de2846a41520a836f542046"
  license "MIT"

  livecheck do
    url :url
    strategy :github_latest
  end

  def install
    bin.install "uninstall"
  end

  test do
    system bin / "uninstall", "--help"
  end
end
