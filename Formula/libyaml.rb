class Libyaml < Formula
  desc "YAML Parser"
  homepage "https://github.com/yaml/libyaml"
  url "https://github.com/yaml/libyaml/archive/refs/tags/0.2.5.tar.gz"
  sha256 "fa240dbf262be053f3898006d502d514936c818e422afdcf33921c63bed9bf2e"
  license "MIT"
  compatibility_version 1

  livecheck do
    url :stable
    strategy :github_latest
  end

  bottle do
    root_url "https://ghcr.io/v2/homebrew/core"
    sha256 cellar: :any,                 arm64_tahoe:    "5cd5a1875da18599e25283465b2fb8735eb8717ee7158ef17f8f4260205404f2"
    sha256 cellar: :any,                 arm64_sequoia:  "0ec9bf8082245c008803b42dcae3e6a0c8cd7a67aed589d9b6482b115c0a543b"
    sha256 cellar: :any_skip_relocation, arm64_linux:    "c725eb08fc7ab6aad7f744a30b230f9b9efa33f8d694849a2d4aadfabb203df3"
  end

  depends_on "autoconf" => :build
  depends_on "automake" => :build
  depends_on "libtool" => :build

  def install
    system "./bootstrap"
    system "./configure", "--disable-dependency-tracking", "--prefix=#{prefix}"
    system "make", "install"
  end

  test do
    (testpath/"test.c").write <<~C
      #include <yaml.h>

      int main()
      {
        yaml_parser_t parser;
        yaml_parser_initialize(&parser);
        yaml_parser_delete(&parser);
        return 0;
      }
    C
    system ENV.cc, "test.c", "-L#{lib}", "-lyaml", "-o", "test"
    system "./test"
  end
end
