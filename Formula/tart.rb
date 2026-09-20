# frozen_string_literal: true

class Tart < Formula
  desc "Run macOS and Linux VMs on Apple hardware"
  homepage "https://github.com/openai/tart"
  url "https://github.com/openai/tart/releases/download/2.32.1/tart.tar.gz"
  version "2.32.1"
  sha256 "8554ab4f7fc12afe52f9b7e3093a935673cbac737a83973d2db7a0683c814529"
  license "Fair Source"

  depends_on macos: :ventura

  def install
    libexec.install Dir["*"]
    bin.write_exec_script libexec/"tart.app/Contents/MacOS/tart"
  end

  post_install_steps do
    run "tart.app/Contents/MacOS/tart", base: :libexec,
        args: ["--generate-completion-script", "bash"], env: { "SHELL" => "bash" },
        stdout_path: "etc/bash_completion.d/tart"
    run "tart.app/Contents/MacOS/tart", base: :libexec,
        args: ["--generate-completion-script", "zsh"], env: { "SHELL" => "zsh" },
        stdout_path: "share/zsh/site-functions/_tart"
    run "tart.app/Contents/MacOS/tart", base: :libexec,
        args: ["--generate-completion-script", "fish"], env: { "SHELL" => "fish" },
        stdout_path: "share/fish/vendor_completions.d/tart.fish"
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
