class Uninstall < Formula
  desc "CLI tool for macOS to uninstall an app from your system"
  homepage "https://github.com/GrantBirki/uninstall"
  version "1.2.0"
  url "https://github.com/GrantBirki/uninstall/releases/download/v#{version}/uninstall-#{version}.tar.gz"
  sha256 "ab9f58dfdac6d5d3413a260c1b59c17f5fca63e3b9ec4535abf28ae73bc6941f"
  license "MIT"

  livecheck do
    url :url
    strategy :github_latest
  end

  def install
    bin.install "uninstall"
  end

  test do
    system "#{bin}/uninstall", "--help"
  end
end
