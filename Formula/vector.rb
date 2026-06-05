class Vector < Formula
  desc "High-performance observability data pipeline"
  homepage "https://vector.dev/"
  url "https://github.com/vectordotdev/vector/releases/download/v0.56.0/vector-0.56.0-arm64-apple-darwin.tar.gz"
  sha256 "9aa8b6772d7c887734d38c84eb721d3a067e08a4aa4dc0dcc809365da242ec16"
  license "MPL-2.0"

  depends_on arch: :arm64
  depends_on :macos

  def install
    bin.install "bin/vector"

    inreplace "config/vector.yaml",
              '# data_dir: "/var/lib/vector"',
              %Q(data_dir: "#{var}/lib/vector")
    (etc/"vector").install Dir["config/*"]
  end

  def post_install
    (var/"lib/vector").mkpath
    (var/"log/vector").mkpath
  end

  def caveats
    <<~EOS
      Data:    #{var}/lib/vector/
      Logs:    #{var}/log/vector/vector.log
      Config:  #{etc}/vector/
    EOS
  end

  service do
    run [opt_bin/"vector", "--config", etc/"vector/vector.yaml"]
    keep_alive false
    working_dir var
    log_path var/"log/vector/vector.log"
    error_log_path var/"log/vector/vector.log"
  end

  test do
    assert_match "vector #{version}", shell_output("#{bin}/vector --version")
  end
end
