cask "blender" do
  version "5.3.0"
  sha256 "2d802b54766741e612cead50b03ebbc8eb64dadc71eda932573d256b8a784720"

  url "https://download.blender.org/release/Blender#{version.major_minor}/blender-#{version}-macos-arm64.dmg"
  name "Blender"
  desc "3D creation suite"
  homepage "https://www.blender.org/"

  livecheck do
    url "https://download.blender.org/release/"
    regex(/href=.*?blender[._-]v?(\d+(?:\.\d+)+)(?:[._-]macos)?[._-]arm64\.dmg/i)
    strategy :page_match do |page, regex|
      major_minor_versions =
        page.scan(%r{href=["']?[^"' >]*?Blender[._-]?v?(\d+(?:\.\d+)+)/?["' >]}i)
            .flatten
            .uniq
            .sort_by { |v| Version.new(v) }
      next if major_minor_versions.blank?

      directory_page = Homebrew::Livecheck::Strategy.page_content(
        URI.join(@url, "Blender#{major_minor_versions.last}/").to_s,
      )[:content]
      next if directory_page.blank?

      directory_page.scan(regex).map { |match| match[0] }
    end
  end

  conflicts_with cask: "blender@lts"
  depends_on arch: :arm64
  depends_on macos: :ventura

  app "Blender.app"
  command_wrapper "blender",
                  executable: "#{appdir}/Blender.app/Contents/MacOS/Blender"

  preflight_steps do
    set_permissions "*.app/**/__pycache__", "u+w", recursive: false
  end

  zap trash: [
    "~/Library/Application Support/Blender",
    "~/Library/Caches/Blender",
    "~/Library/Saved Application State/org.blenderfoundation.blender.savedState",
  ]
end
