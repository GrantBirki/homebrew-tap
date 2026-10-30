class Vector < Formula
  desc "High-performance observability data pipeline"
  homepage "https://vector.dev/"
  url "https://github.com/vectordotdev/vector/releases/download/v0.60.0/vector-0.60.0-arm64-apple-darwin.tar.gz"
  sha256 "aa5c9d89416b39f1a90a7f1a088a9ecbb8c8c3a5669fb86609c9d4a958fe1a28"
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

  post_install_steps do
    mkdir_p "lib/vector", base: :var
    mkdir_p "log/vector", base: :var
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
