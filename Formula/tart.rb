# frozen_string_literal: true

class Tart < Formula
  desc "Run macOS and Linux VMs on Apple hardware"
  homepage "https://github.com/openai/tart"
  url "https://github.com/openai/tart/releases/download/2.32.1/tart.tar.gz"
  sha256 "8554ab4f7fc12afe52f9b7e3093a935673cbac737a83973d2db7a0683c814529"
  version "2.32.1"
  license "Fair Source"

  depends_on macos: :ventura

  def install
    libexec.install Dir["*"]
    bin.write_exec_script libexec/"tart.app/Contents/MacOS/tart"
  end

  def post_install
    generate_completions_from_executable(libexec/"tart.app/Contents/MacOS/tart", "--generate-completion-script")
  end

  def caveats
    <<~EOS
      This formula intentionally omits the optional Softnet dependency. Tart's
      default shared networking remains available, but --net-softnet requires a
      separately reviewed Softnet installation.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/tart --version")
  end
end
