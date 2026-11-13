class Uninstall < Formula
  desc "CLI tool for macOS to uninstall an app from your system"
  homepage "https://github.com/GrantBirki/uninstall"
  url "https://github.com/GrantBirki/uninstall/releases/download/v1.3.6/uninstall-1.3.6.tar.gz"
  version "1.3.6"
  sha256 "7bf4f44f573d57e8d9e4804c8391d3a3ec2d89692845d7839e52d8d01ce4a9d5"
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
