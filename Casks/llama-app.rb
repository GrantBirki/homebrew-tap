cask "llama-app" do
  version "0.47.0"
  sha256 "7fa356591ab1f37639cfa1f5e50b2eba52940f578965c1427b2d4eaa1571350b"

  url "https://github.com/ggml-org/Llama-macOS/releases/download/#{version}/Llama.dmg"
  name "Llama"
  desc "Menu bar app for running local LLMs"
  homepage "https://github.com/ggml-org/Llama-macOS"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "Llama.app"

  uninstall quit: "app.llama.Llama"

  zap trash: [
    "~/.llama-app",
    "~/Library/Application Support/Llama",
    "~/Library/Application Support/LlamaBarn",
    "~/Library/Caches/app.llama.Llama",
    "~/Library/Caches/app.llamabarn.LlamaBarn",
    "~/Library/Caches/SentryCrash/Llama",
    "~/Library/HTTPStorages/app.llama.Llama",
    "~/Library/HTTPStorages/app.llamabarn.LlamaBarn",
    "~/Library/HTTPStorages/app.llamabarn.LlamaBarn.binarycookies",
    "~/Library/Logs/Llama",
    "~/Library/Preferences/app.llama.Llama.plist",
    "~/Library/Preferences/app.llamabarn.LlamaBarn.plist",
    "~/Library/WebKit/app.llamabarn.LlamaBarn",
  ]

  caveats <<~EOS
    Llama enables Sentry error reporting without an in-app opt-out.
    In-app updates and fallback engine downloads are separate from this cask pin.
    Review https://github.com/GrantBirki/homebrew-tap/blob/main/docs/llama-app.md before first launch.
  EOS
end
