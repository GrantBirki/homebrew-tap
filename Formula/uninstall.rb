class Uninstall < Formula
  desc "CLI tool for macOS to uninstall an app from your system"
  homepage "https://github.com/GrantBirki/uninstall"
  version "1.1.0"
  url "https://github.com/GrantBirki/uninstall/releases/download/v#{version}/uninstall-#{version}.tar.gz"
  sha256 "942d11b9836de47daa6501fb8d32bac56d4c2c95b0207684ed58952e2a3df5d6"
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
