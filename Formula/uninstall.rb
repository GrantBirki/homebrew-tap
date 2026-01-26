class Uninstall < Formula
  desc "CLI tool for macOS to uninstall an app from your system"
  homepage "https://github.com/GrantBirki/uninstall"
  url "https://github.com/GrantBirki/uninstall.git", :branch => 'main'
  version "1.0"

  def install
    bin.install "uninstall"
  end

  test do
    system "#{bin}/uninstall", "--help"
  end
end
