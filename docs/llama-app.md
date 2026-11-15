# Llama menu bar app

The optional `llama-app` cask pins the official Llama 0.47.0 app. It stays outside the default Brewfile. Installing this cask copies the app; it does not launch it or install model weights. The separate `llama.cpp` formula supplies the reviewed engine.

## Release review

The [0.47.0 release](https://github.com/ggml-org/Llama-macOS/releases/tag/0.47.0) resolves to commit `eadd54671e2dd61311e039852e8eba5cced2e463`. The downloaded DMG matches GitHub's published SHA-256. Native verification confirmed bundle `app.llama.Llama`, Apple silicon, macOS 15 minimum, hardened runtime, a secure signing timestamp, and Developer ID Application Caret.io OOD (`V89L745MNN`). The previous 0.46.1 release has the same publisher and bundle identity.

Gatekeeper accepted both enclosed apps as `Notarized Developer ID`. Neither app carries a stapled ticket, so an offline first launch has not been established. GitHub returned no matching artifact attestation; this review does not establish a cryptographic source-to-binary mapping. Neither app nor any model was launched during verification. Exact artifact and recipe identities are recorded in `provenance.yml`.

## Telemetry

The [release startup code](https://github.com/ggml-org/Llama-macOS/blob/0.47.0/Llama/LlamaApp.swift#L80-L110) enables Sentry error reporting. No telemetry opt-out was found in the reviewed settings or startup code. [Download failures](https://github.com/ggml-org/Llama-macOS/blob/0.47.0/Llama/Downloads/ModelManager%2BTransfer.swift#L51-L65) can report model identifiers and URLs. This is source review, not a measurement of actual telemetry contents. Local model inference does not mean the app makes no external connections.

If error reporting is unacceptable, leave the app unlaunched and use the separate engine with its browser UI. A cask checksum cannot disable telemetry. This tap does not modify firewall rules or application preferences.

## App and engine updates

The app initializes Sparkle and enables update checks every two hours. It does not set `SUAutomaticallyUpdate`; [Sparkle defaults](https://sparkle-project.org/documentation/customization/) leave silent download and installation off unless enabled by the user. App updates can still replace the cask-pinned version.

To retain manual control, quit Llama and set these user preferences before its first launch:

```bash
defaults write app.llama.Llama SUEnableAutomaticChecks -bool false
defaults write app.llama.Llama SUAutomaticallyUpdate -bool false
```

These are Sparkle's documented preferences; their effect in this app has not been runtime-tested. Do not use the app's manual update action when the tap must remain the update authority. Keep Homebrew livecheck for discovery and adopt updates through a reviewed cask change. Retaining `auto_updates true` in the cask describes upstream behavior; removing it would not disable Sparkle.

The [engine selector](https://github.com/ggml-org/Llama-macOS/blob/0.47.0/Llama/Engine/LlamaBinaries.swift) accepts the Homebrew engine when its reported build is at least b9831; llama.cpp 1.0.0 reports build 12359. A missing, blocked, unreadable, or older engine triggers a separate managed-engine path. That path downloads an engine and decompression helper without an explicit digest or signature check in the [reviewed installer](https://github.com/ggml-org/Llama-macOS/blob/0.47.0/Llama/Engine/LlamaInstaller.swift). Managed-engine replacement is separate from Sparkle, and no disable switch was found. Sparkle preferences do not block those downloads.

Before future use, confirm the app reports the Homebrew engine. Quit if it falls back to an app-managed engine; that executable is outside this tap's verification. The cask deliberately does not zap the shared `~/.local/bin/llama` path, which can contain an independent user-owned CLI.

## Before first launch

The verified app has no App Sandbox entitlement. It and its engine run with the user's normal file permissions. Keep Agent mode and network sharing off; both are opt-in in this release. Launch at login is enabled on first launch and can be disabled in the app's General settings. Starting Llama starts its local server, even before a model is requested.

The app normally scans the Hugging Face cache. Preserved weights elsewhere require explicit configuration; see the [upstream custom model settings](https://github.com/ggml-org/Llama-macOS/tree/0.47.0#custom-model-settings). No account sign-in is needed for existing local weights.
