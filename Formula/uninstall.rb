class Uninstall < Formula
  desc "CLI tool for macOS to uninstall an app from your system"
  homepage "https://github.com/GrantBirki/uninstall"
  url "https://github.com/GrantBirki/uninstall/releases/download/v1.3.5/uninstall-1.3.5.tar.gz"
  version "1.3.5"
  sha256 "fcfa8a55f835a5bffebedf11f2e0cde56880825d3c1539d81d5e5f148bae5dba"
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
