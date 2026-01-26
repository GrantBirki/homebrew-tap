class Uninstall < Formula
  desc "CLI tool for macOS to uninstall an app from your system"
  homepage "https://github.com/GrantBirki/uninstall"
  version "1.0.0"
  url "https://github.com/GrantBirki/uninstall/releases/download/v#{version}/uninstall-#{version}.tar.gz"
  sha256 "6ac087a96c6cfc085c4a2e0257a57f3c9a1e5acb4666b69c8e448a462ece4486"
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
