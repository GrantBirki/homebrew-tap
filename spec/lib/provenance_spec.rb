# frozen_string_literal: true

require "spec_helper"

module ProvenanceSpecFixtures
  BOTTLE_SHA = "a" * 64
  CASK_SHA = "b" * 64
  COMMIT = "c" * 40
  BLOB = "d" * 40
end

RSpec.describe HomebrewTap::ProvenanceManifest do
  def formula_source(bottle_sha: ProvenanceSpecFixtures::BOTTLE_SHA)
    <<~RUBY
      class Foo < Formula
        url "https://example.com/foo-1.0.0.tar.gz"
        sha256 "#{'e' * 64}"

        bottle do
          root_url "https://ghcr.io/v2/homebrew/core"
          sha256 cellar: :any, arm64_tahoe: "#{bottle_sha}"
        end
      end
    RUBY
  end

  def cask_source(cask_sha: ProvenanceSpecFixtures::CASK_SHA)
    <<~RUBY
      cask "app" do
        version "2.0.0"
        sha256 "#{cask_sha}"
        url "https://example.com/app-2.0.0.zip"
        app "App.app"
      end
    RUBY
  end

  def base_data(bottle_sha: ProvenanceSpecFixtures::BOTTLE_SHA, cask_sha: ProvenanceSpecFixtures::CASK_SHA)
    formula_path = write("Formula/foo.rb", formula_source(bottle_sha: bottle_sha))
    cask_path = write("Casks/app.rb", cask_source(cask_sha: cask_sha))
    fingerprint = lambda do |path|
      digests = File.read(path).scan(/\b[0-9a-f]{64}\b/i).map(&:downcase).uniq.sort
      Digest::SHA256.hexdigest(digests.join("\n"))
    end
    {
      "schema_version" => 1,
      "policy_effective_at" => "2026-06-11T00:00:00Z",
      "formulae" => {
        "foo" => {
          "source_type" => "homebrew-core",
          "recipe_repository" => "Homebrew/homebrew-core",
          "recipe_commit" => ProvenanceSpecFixtures::COMMIT,
          "recipe_path" => "Formula/f/foo.rb",
          "recipe_blob" => ProvenanceSpecFixtures::BLOB,
          "local_file_sha256" => Digest::SHA256.file(formula_path).hexdigest,
          "version" => "1.0.0",
          "release_published_at" => "2026-01-01T00:00:00Z",
          "release_evidence" => { "description" => "Release", "reference" => "https://example.com/foo/1.0.0" },
          "adopted_at" => "2026-02-01T00:00:00Z",
          "adoption_commit" => ProvenanceSpecFixtures::COMMIT,
          "adoption_reason" => "Pin reviewed release",
          "cooldown_exception" => nil,
          "legacy_baseline" => {
            "version" => "1.0.0",
            "artifact_fingerprint_sha256" => fingerprint.call(formula_path)
          },
          "local_changes" => ["Removed head"],
          "bottles" => {
            "repository" => "Homebrew/homebrew-core",
            "verified_at" => "2026-06-11T01:00:00Z",
            "digests" => { "arm64_tahoe" => bottle_sha }
          }
        }
      },
      "casks" => {
        "app" => {
          "source_type" => "upstream-release",
          "upstream_repository" => "example/app",
          "upstream_tag" => "v2.0.0",
          "upstream_commit" => ProvenanceSpecFixtures::COMMIT,
          "local_file_sha256" => Digest::SHA256.file(cask_path).hexdigest,
          "version" => "2.0.0",
          "release_published_at" => "2026-01-01T00:00:00Z",
          "release_evidence" => { "description" => "Release", "reference" => "https://example.com/app/2.0.0" },
          "adopted_at" => "2026-02-01T00:00:00Z",
          "adoption_commit" => ProvenanceSpecFixtures::COMMIT,
          "adoption_reason" => "Pin reviewed app",
          "cooldown_exception" => nil,
          "legacy_baseline" => {
            "version" => "2.0.0",
            "artifact_fingerprint_sha256" => fingerprint.call(cask_path)
          },
          "local_changes" => [],
          "artifacts" => { "default" => cask_sha }
        }
      }
    }
  end

  def write_manifest(data)
    write("provenance.yml", YAML.dump(data))
  end

  def owner_controlled_cask_data(token, repository)
    data = base_data
    FileUtils.rm(File.join(@root, "Casks/app.rb"))
    source = cask_source
             .sub('cask "app"', %(cask "#{token}"))
             .sub("https://example.com/app-2.0.0.zip", "https://github.com/#{repository}/releases/download/v2.0.0/App.zip")
    cask_path = write("Casks/#{token}.rb", source)
    entry = data["casks"].delete("app")
    entry.merge!(
      "source_type" => "personal-release",
      "upstream_repository" => repository,
      "local_file_sha256" => Digest::SHA256.file(cask_path).hexdigest,
      "release_published_at" => "2026-06-10T00:00:00Z",
      "adopted_at" => "2026-06-12T00:00:00Z",
      "cooldown_exception" => nil,
      "legacy_baseline" => nil,
    )
    data["casks"][token] = entry
    data
  end

  def owner_controlled_formula_data(token, repository)
    data = base_data
    FileUtils.rm(File.join(@root, "Formula/foo.rb"))
    source = <<~RUBY
      class OwnerControlled < Formula
        url "https://github.com/#{repository}/releases/download/v1.0.0/#{token}-1.0.0.tar.gz"
        sha256 "#{'e' * 64}"
      end
    RUBY
    formula_path = write("Formula/#{token}.rb", source)
    entry = data["formulae"].delete("foo")
    entry.delete("recipe_repository")
    entry.delete("recipe_commit")
    entry.delete("recipe_path")
    entry.delete("recipe_blob")
    entry.delete("bottles")
    entry.merge!(
      "source_type" => "personal-release",
      "upstream_repository" => repository,
      "upstream_tag" => "v1.0.0",
      "upstream_commit" => ProvenanceSpecFixtures::COMMIT,
      "local_file_sha256" => Digest::SHA256.file(formula_path).hexdigest,
      "release_published_at" => "2026-06-10T00:00:00Z",
      "adopted_at" => "2026-06-12T00:00:00Z",
      "cooldown_exception" => nil,
      "legacy_baseline" => nil,
      "local_changes" => [],
      "artifacts" => { "asset_01" => "e" * 64 },
    )
    data["formulae"][token] = entry
    data
  end

  def manifest(data = base_data)
    write_manifest(data)
    described_class.new(root: @root)
  end

  def local_patch_data
    data = base_data
    path = "Patches/foo/build.patch"
    content = "--- a/source\n+++ b/source\n@@ -1 +1 @@\n-old\n+new\n"
    write(path, content)
    source = formula_source.sub(/\nend\n\z/, "\n  patch do\n    file \"#{path}\"\n  end\nend\n")
    formula = write("Formula/foo.rb", source)
    data["formulae"]["foo"].merge!(
      "local_file_sha256" => Digest::SHA256.file(formula).hexdigest,
      "recipe_patches" => {
        path => {
          "blob" => Digest::SHA1.hexdigest("blob #{content.bytesize}\0" + content),
          "sha256" => Digest::SHA256.hexdigest(content)
        }
      },
    )
    data
  end

  it "binds local patch paths, Git blobs and SHA-256 bytes before recipe parsing" do
    data = local_patch_data
    expect(manifest(data).validate).to eq(true)

    write("Patches/foo/build.patch", "changed bytes")
    expect { manifest(data).validate }.to raise_error(HomebrewTap::Error) do |error|
      expect(error.message).to include("blob does not match the local patch", "sha256 does not match the local patch")
    end
  end

  it "rejects missing, unrecorded, unreferenced, and dynamic local patches" do
    data = local_patch_data
    data["formulae"]["foo"].delete("recipe_patches")
    expect { manifest(data).validate }.to raise_error(HomebrewTap::Error, /do not match local patch declarations/)

    data = local_patch_data
    FileUtils.rm(File.join(@root, "Patches/foo/build.patch"))
    expect { manifest(data).validate }.to raise_error(HomebrewTap::Error, /regular file without symlinks/)

    data = local_patch_data
    write("Patches/foo/unrecorded.patch", "unrecorded")
    expect { manifest(data).validate }.to raise_error(HomebrewTap::Error, /unrecorded local patch file/)
    FileUtils.rm(File.join(@root, "Patches/foo/unrecorded.patch"))

    source = formula_source
    path = write("Formula/foo.rb", source)
    data["formulae"]["foo"]["local_file_sha256"] = Digest::SHA256.file(path).hexdigest
    expect { manifest(data).validate }.to raise_error(HomebrewTap::Error, /do not match local patch declarations/)

    source = source.sub(/\nend\n\z/, "\n  patch do\n    file ENV.fetch(\"PATCH\")\n  end\nend\n")
    path = write("Formula/foo.rb", source)
    data["formulae"]["foo"]["local_file_sha256"] = Digest::SHA256.file(path).hexdigest
    expect { manifest(data).validate }.to raise_error(HomebrewTap::Error, /unsupported local patch declarations/)
  end

  it "rejects malformed patch metadata, traversal, cross-formula paths, and symlinks" do
    data = local_patch_data
    entry = data["formulae"]["foo"]
    entry["recipe_patches"] = "bad"
    expect { manifest(data).validate }.to raise_error(HomebrewTap::Error, /recipe_patches must be a mapping/)

    metadata = local_patch_data["formulae"]["foo"]["recipe_patches"].values.first
    ["/tmp/build.patch", "Patches/foo/../build.patch", "Patches/bar/build.patch", 1].each do |invalid|
      entry["recipe_patches"] = { invalid => metadata }
      expect { manifest(data).validate }.to raise_error(HomebrewTap::Error, /contains an invalid path/)
    end
    entry["recipe_patches"] = { "Patches/foo/build.patch" => { "extra" => "unbound" } }
    expect { manifest(data).validate }.to raise_error(HomebrewTap::Error, /must contain only blob and sha256/)
    entry["recipe_patches"]["Patches/foo/build.patch"] = { "blob" => "bad", "sha256" => "bad" }
    expect { manifest(data).validate }.to raise_error(HomebrewTap::Error, /blob is invalid/)

    data = local_patch_data
    path = File.join(@root, "Patches/foo/build.patch")
    FileUtils.mv(path, File.join(@root, "outside.patch"))
    File.symlink(File.join(@root, "outside.patch"), path)
    expect { manifest(data).validate }.to raise_error(HomebrewTap::Error, /regular file without symlinks/)
    FileUtils.rm(path)
    FileUtils.mkdir_p(File.join(@root, "alternate"))
    FileUtils.mv(File.join(@root, "outside.patch"), File.join(@root, "alternate/build.patch"))
    FileUtils.rmdir(File.join(@root, "Patches/foo"))
    File.symlink(File.join(@root, "alternate"), File.join(@root, "Patches/foo"))
    expect { manifest(data).validate }.to raise_error(HomebrewTap::Error, /regular file without symlinks/)
  end

  it "rejects inline, parenthesized, dynamic, and extra unrecorded file patch declarations" do
    data = base_data
    [
      'patch do; file "unrecorded.patch"; end',
      'patch do; file ENV.fetch("PATCH"); end',
      'patch do; if true; file "unrecorded.patch"; end; end',
      'patch do; file("unrecorded.patch"); end'
    ].each do |declaration|
      source = formula_source.sub(/\nend\n\z/, "\n  #{declaration}\nend\n")
      path = write("Formula/foo.rb", source)
      data["formulae"]["foo"]["local_file_sha256"] = Digest::SHA256.file(path).hexdigest
      expect { manifest(data).validate }.to raise_error(HomebrewTap::Error, /unsupported local patch declarations/)
    end

    data = local_patch_data
    source = File.read(File.join(@root, "Formula/foo.rb"))
    source = source.sub(/\nend\n\z/, "\n  patch do\n    file \"Patches/foo/unrecorded.patch\"\n  end\nend\n")
    path = write("Formula/foo.rb", source)
    data["formulae"]["foo"]["local_file_sha256"] = Digest::SHA256.file(path).hexdigest
    expect { manifest(data).validate }.to raise_error(HomebrewTap::Error, /do not match local patch declarations/)
  end

  it "limits local patch provenance to core-derived formulae" do
    data = local_patch_data
    data["formulae"]["foo"]["source_type"] = "upstream-release"
    expect { manifest(data).validate }.to raise_error(HomebrewTap::Error, /recipe_patches require homebrew-core provenance/)
  end

  it "validates direct artifact provenance and records verification time" do
    subject = manifest

    expect(subject.validate).to eq(true)
    expect(subject.formula_tokens).to eq(["foo"])
    expect(subject.formula_entry("foo")["version"]).to eq("1.0.0")
    expect(subject.bottle_digests(subject.formula_entry("foo"))).to eq("arm64_tahoe" => ProvenanceSpecFixtures::BOTTLE_SHA)
    expect(subject.bottle_digests({})).to eq({})

    subject.record_formula_verifications!(["foo"], verified_at: Time.utc(2026, 6, 12))
    recorded = YAML.safe_load_file(File.join(@root, "provenance.yml"), aliases: false)
    expect(recorded.dig("formulae", "foo", "bottles", "verified_at")).to eq("2026-06-12T00:00:00Z")
  end

  it "reports missing, malformed, and structurally invalid manifests" do
    missing = described_class.new(root: @root)
    expect { missing.validate }.to raise_error(HomebrewTap::Error, /not found/)

    write("provenance.yml", "- nope\n")
    expect { described_class.new(root: @root).validate }.to raise_error(HomebrewTap::Error, /must contain a mapping/)

    write("provenance.yml", "bad: [\n")
    expect { described_class.new(root: @root).validate }.to raise_error(HomebrewTap::Error, /invalid provenance manifest/)

    data = base_data
    data["schema_version"] = 2
    data["policy_effective_at"] = "not-time"
    data["extra"] = true
    data["formulae"] = []
    write_manifest(data)
    expect { described_class.new(root: @root).validate }.to raise_error(HomebrewTap::Error) do |error|
      expect(error.message).to include("schema_version", "unknown keys", "ISO-8601", "formulae must be a mapping")
    end
  end

  it "reports coverage, source, checksum, timestamp, and cooldown drift" do
    data = base_data
    data["formulae"]["extra"] = "bad"
    data["formulae"].delete("foo")
    data["casks"]["app"].merge!(
      "source_type" => "invalid",
      "upstream_repository" => "",
      "upstream_commit" => "bad",
      "local_file_sha256" => "bad",
      "version" => "missing",
      "adoption_reason" => "",
      "release_published_at" => "bad",
      "adopted_at" => "bad",
      "local_changes" => "bad",
      "artifacts" => "bad",
      "dependencies" => ["transitive"],
    )
    write_manifest(data)

    expect { described_class.new(root: @root).validate }.to raise_error(HomebrewTap::Error) do |error|
      expect(error.message).to include(
        "formulae is missing foo",
        "formulae has extra entry extra",
        "formulae.extra must be a mapping",
        "source_type is invalid",
        "upstream_repository must be a non-empty string",
        "upstream_commit is invalid",
        "local_file_sha256 is invalid",
        "version does not appear",
        "adoption_reason must be a non-empty string",
        "release_published_at must be an ISO-8601 timestamp",
        "local_changes must contain only non-empty strings",
        "artifacts must map variants",
        "unknown keys: dependencies",
      )
    end

    data = base_data
    entry = data["formulae"]["foo"]
    legacy_baseline = entry["legacy_baseline"]
    entry["legacy_baseline"] = nil
    entry["release_published_at"] = "2026-06-10T00:00:00Z"
    entry["adopted_at"] = "2026-06-12T00:00:00Z"
    entry["cooldown_exception"] = { "reason" => "", "reference" => "" }
    write_manifest(data)
    expect { described_class.new(root: @root).validate }.to raise_error(HomebrewTap::Error, /14-day cooldown/)

    entry["cooldown_exception"] = { "reason" => "Security fix", "reference" => "https://example.com/advisory" }
    write_manifest(data)
    expect(described_class.new(root: @root).validate).to eq(true)

    entry["legacy_baseline"] = legacy_baseline
    write_manifest(data)
    expect { described_class.new(root: @root).validate }.to raise_error(HomebrewTap::Error, /legacy_baseline/)
  end

  it "allows immediate adoption of owner-controlled personal formulae" do
    expect(manifest(owner_controlled_formula_data("uninstall", "GrantBirki/uninstall")).validate).to eq(true)
  end

  it "allows immediate adoption of owner-controlled personal casks" do
    expect(manifest(owner_controlled_cask_data("espresso", "GrantBirki/espresso")).validate).to eq(true)
  end

  it "keeps unlisted personal releases on the cooldown" do
    expect { manifest(owner_controlled_formula_data("uninstall", "example/uninstall")).validate }
      .to raise_error(HomebrewTap::Error, /14-day cooldown/)

    expect { manifest(owner_controlled_formula_data("rust-template", "GrantBirki/rust-template")).validate }
      .to raise_error(HomebrewTap::Error, /14-day cooldown/)
  end

  it "binds owner-controlled personal releases to their source type and matching token" do
    wrong_repository = owner_controlled_formula_data("uninstall", "GrantBirki/renamed-uninstall")
    expect { manifest(wrong_repository).validate }.to raise_error(HomebrewTap::Error, /14-day cooldown/)

    wrong_source = owner_controlled_formula_data("uninstall", "GrantBirki/uninstall")
    wrong_source["formulae"]["uninstall"]["source_type"] = "upstream-release"
    expect { manifest(wrong_source).validate }.to raise_error(HomebrewTap::Error, /14-day cooldown/)
  end

  it "keeps timestamp and exception validation for owner-controlled personal releases" do
    data = owner_controlled_formula_data("uninstall", "GrantBirki/uninstall")
    entry = data["formulae"]["uninstall"]
    entry["adopted_at"] = "2026-06-09T00:00:00Z"
    entry["cooldown_exception"] = { "reason" => "", "reference" => "" }

    expect { manifest(data).validate }.to raise_error(HomebrewTap::Error) do |error|
      expect(error.message).to include("adopted_at predates", "cooldown_exception must contain")
    end
  end

  it "rejects mutable inputs and formula or cask digest drift" do
    data = base_data
    formula_path = File.join(@root, "Formula/foo.rb")
    File.write(formula_path, formula_source.sub("class Foo", "head \"https://example.com/foo.git\", branch: \"main\"\nclass Foo"))
    File.open(formula_path, "a") do |file|
      file.puts 'url "http://example.com/unsafe.tar.gz"'
      file.puts "sha256 :no_check"
      file.puts 'url "https://example.com/no-revision.git"'
    end
    data["formulae"]["foo"]["bottles"]["repository"] = "attacker/repo"
    data["formulae"]["foo"]["bottles"]["verified_at"] = "bad"
    data["formulae"]["foo"]["bottles"]["digests"]["arm64_tahoe"] = "f" * 64
    write_manifest(data)

    expect { described_class.new(root: @root).validate }.to raise_error(HomebrewTap::Error) do |error|
      expect(error.message).to include(
        "local_file_sha256 does not match",
        "mutable head spec",
        "insecure artifact URL",
        "sha256 :no_check",
        "git source must use a full revision",
        "bottles digests do not match",
        "bottles.repository",
        "bottles.verified_at",
      )
    end

    data = base_data
    data["formulae"]["foo"]["bottles"]["digests"] = {}
    data["formulae"]["foo"]["local_file_sha256"] = Digest::SHA256.file(File.join(@root, "Formula/foo.rb")).hexdigest
    data["casks"]["app"]["artifacts"]["default"] = "f" * 64
    write_manifest(data)
    expect { described_class.new(root: @root).validate }.to raise_error(HomebrewTap::Error, /digests do not match|artifacts do not match/)

    data = base_data
    data["formulae"]["foo"]["bottles"] = "bad"
    data["casks"]["app"]["platform_versions"] = []
    write_manifest(data)
    expect { described_class.new(root: @root).validate }.to raise_error(HomebrewTap::Error) do |error|
      expect(error.message).to include("bottles must be a mapping", "platform_versions must map platforms to versions")
    end

    data = base_data
    data["casks"]["app"]["platform_versions"] = { "future" => "9.9.9" }
    write_manifest(data)
    expect { described_class.new(root: @root).validate }.to raise_error(
      HomebrewTap::Error,
      /platform_versions are absent from the cask/,
    )
  end

  it "requires homebrew-derived recipe metadata" do
    data = base_data
    entry = data["formulae"]["foo"]
    entry["recipe_repository"] = ""
    entry["recipe_commit"] = "bad"
    entry["recipe_path"] = ""
    entry["recipe_blob"] = "bad"
    write_manifest(data)
    expect { described_class.new(root: @root).validate }.to raise_error(HomebrewTap::Error) do |error|
      expect(error.message).to include("recipe_repository", "recipe_commit", "recipe_path", "recipe_blob")
    end
  end

  it "rejects mismatched source kinds, missing release evidence, and unrecorded direct assets" do
    data = base_data
    formula = data["formulae"]["foo"]
    formula.merge!(
      "source_type" => "homebrew-cask",
      "recipe_repository" => "Homebrew/homebrew-cask",
      "release_evidence" => nil,
    )
    cask = data["casks"]["app"]
    cask.merge!(
      "source_type" => "homebrew-core",
      "recipe_repository" => "Homebrew/homebrew-core",
      "recipe_commit" => ProvenanceSpecFixtures::COMMIT,
      "recipe_path" => "Formula/a/app.rb",
      "recipe_blob" => ProvenanceSpecFixtures::BLOB,
    )
    write_manifest(data)

    expect { described_class.new(root: @root).validate }.to raise_error(HomebrewTap::Error) do |error|
      expect(error.message).to include(
        "cannot use homebrew-cask provenance",
        "cannot use homebrew-core provenance",
        "release_evidence must be a mapping",
      )
    end

    data = base_data
    formula = data["formulae"]["foo"]
    formula.merge!(
      "source_type" => "upstream-release",
      "upstream_repository" => "example/foo",
      "upstream_tag" => "v1.0.0",
      "upstream_commit" => ProvenanceSpecFixtures::COMMIT,
      "artifacts" => nil,
    )
    write_manifest(data)
    expect { described_class.new(root: @root).validate }.to raise_error(
      HomebrewTap::Error,
      /artifacts must map direct release assets/,
    )
  end

  it "reports unknown formula provenance" do
    subject = manifest
    expect { subject.formula_entry("missing") }.to raise_error(HomebrewTap::Error, /not found/)
  end
end

RSpec.describe HomebrewTap::ProvenanceVerifier do
  include FixtureHelpers

  def attestation_payload(digest, repository: "Homebrew/homebrew-core", workflow: "publish-commit-bottles.yml")
    JSON.generate([
                    {
                      "verificationResult" => {
                        "signature" => {
                          "certificate" => {
                            "githubWorkflowRepository" => repository,
                            "subjectAlternativeName" => "https://github.com/#{repository}/.github/workflows/#{workflow}@refs/heads/main"
                          }
                        },
                        "statement" => { "subject" => [{ "digest" => { "sha256" => digest } }] }
                      }
                    }
                  ])
  end

  def core_info_command
    ["env", "HOMEBREW_NO_AUTO_UPDATE=1", "brew", "ruby", "-e", described_class::CORE_INFO_SCRIPT, "foo"]
  end

  def core_fetch_command(recipe, sha:, version: "1.0.0", extra_bottles: {})
    digests = { "arm64_tahoe" => sha }.merge(extra_bottles)
    [
      "env", "HOMEBREW_NO_AUTO_UPDATE=1", "brew", "ruby", "-e", described_class::CORE_FETCH_SCRIPT,
      "foo", version, JSON.generate(digests), Digest::SHA256.hexdigest(recipe.unpack1("m0"))
    ]
  end

  def bottle_cache_path(tag)
    name = tag == "arm64_tahoe" ? "foo.bottle.tar.gz" : "foo.#{tag}.bottle.tar.gz"
    File.join(@root, "cache", name)
  end

  def core_fetch_payload(sha:, extra_bottles: {})
    bottles = { "arm64_tahoe" => sha }.merge(extra_bottles).map do |tag, digest|
      { "tag" => tag, "digest" => digest, "path" => bottle_cache_path(tag) }
    end
    JSON.generate(bottles)
  end

  def bottle_attestation_command(tag = "arm64_tahoe")
    ["gh", "attestation", "verify", bottle_cache_path(tag), "--repo", "Homebrew/homebrew-core", "--format", "json"]
  end

  def fake_core_api
    <<~RUBY
      require "digest"
      require "json"
      $LOADED_FEATURES.concat(%w[formulary.rb api/formula.rb])
      module Formulary
        def self.factory(_name) = nil
      end
      module Homebrew
        module API
          module Formula
            def self.source_download(_formula)
              Struct.new(:symlink_location).new(ARGV.fetch(4))
            end
            def self.source_download_formula(_formula)
              mode = ARGV.fetch(5)
              abort "UNREVIEWED RECIPE EVALUATED" if mode == "checksum"
              tap = Object.new
              tap.define_singleton_method(:core_tap?) { mode != "tap" }
              version = mode == "version" ? "2.0.0" : "1.0.0"
              files = mode == "map" ? {} : JSON.parse(ARGV.fetch(2)).transform_values { |sha| { "sha256" => sha } }
              Struct.new(:tap, :pkg_version, :bottle_hash).new(tap, version, { "files" => files })
            end
          end
        end
      end
    RUBY
  end

  def setup_manifest(bottle_path: nil, core_version: "1.0.0", revision: 0, core_revision: 0, extra_bottles: {}, source_type: "homebrew-core", bottles: true)
    bottle_path ||= write("cache/foo.bottle.tar.gz", "bottle")
    bottle_sha = Digest::SHA256.file(bottle_path).hexdigest
    bottle_shas = { "arm64_tahoe" => bottle_sha }.merge(extra_bottles)
    bottle_lines = bottle_shas.map { |tag, digest| "sha256 #{tag}: \"#{digest}\"" }.join("\n    ")
    version = revision.positive? ? "1.0.0_#{revision}" : "1.0.0"
    formula = <<~RUBY
      class Foo < Formula
        url "https://example.com/foo-1.0.0.tar.gz"
        sha256 "#{'e' * 64}"
        revision #{revision}
        bottle do
          root_url "https://ghcr.io/v2/homebrew/core"
          #{bottle_lines}
        end
      end
    RUBY
    formula_path = write("Formula/foo.rb", formula)
    digests = formula.scan(/\b[0-9a-f]{64}\b/i).map(&:downcase).uniq.sort
    entry = {
      "source_type" => source_type,
      "recipe_repository" => "Homebrew/homebrew-core",
      "recipe_commit" => "c" * 40,
      "recipe_path" => "Formula/f/foo.rb",
      "recipe_blob" => "d" * 40,
      "local_file_sha256" => Digest::SHA256.file(formula_path).hexdigest,
      "version" => version,
      "release_published_at" => "2026-01-01T00:00:00Z",
      "release_evidence" => { "description" => "Release", "reference" => "https://example.com/foo/1.0.0" },
      "adopted_at" => "2026-02-01T00:00:00Z",
      "adoption_commit" => "c" * 40,
      "adoption_reason" => "Pin",
      "cooldown_exception" => nil,
      "legacy_baseline" => {
        "version" => version,
        "artifact_fingerprint_sha256" => Digest::SHA256.hexdigest(digests.join("\n"))
      },
      "local_changes" => [],
      "bottles" => if bottles
                     {
                       "repository" => "Homebrew/homebrew-core",
                       "verified_at" => "2026-06-11T00:00:00Z",
                       "digests" => bottle_shas
                     }
                   else
                     { "repository" => "Homebrew/homebrew-core", "verified_at" => "2026-06-11T00:00:00Z", "digests" => {} }
                   end
    }
    data = {
      "schema_version" => 1,
      "policy_effective_at" => "2026-06-11T00:00:00Z",
      "formulae" => { "foo" => entry },
      "casks" => {}
    }
    write("provenance.yml", YAML.dump(data))
    recipe = [formula].pack("m0")
    info = JSON.generate(
      "formulae" => [{
        "versions" => { "stable" => core_version },
        "revision" => core_revision,
        "bottle" => { "stable" => { "files" => bottle_shas.transform_values { |digest| { "sha256" => digest } } } }
      }],
    )
    [HomebrewTap::ProvenanceManifest.new(root: @root), bottle_sha, recipe, info]
  end

  def setup_local_patch_manifest
    manifest, sha, recipe, info = setup_manifest
    path = "Patches/foo/build.patch"
    patch = "--- a/source\n+++ b/source\n@@ -1 +1 @@\n-old\n+new\n"
    write(path, patch)
    source = recipe.unpack1("m0").sub(/\nend\n\z/, "\n  patch do\n    file \"#{path}\"\n  end\nend\n")
    formula_path = write("Formula/foo.rb", source)
    data = manifest.load!
    metadata = {
      "blob" => Digest::SHA1.hexdigest("blob #{patch.bytesize}\0" + patch),
      "sha256" => Digest::SHA256.hexdigest(patch)
    }
    data["formulae"]["foo"].merge!(
      "local_file_sha256" => Digest::SHA256.file(formula_path).hexdigest,
      "recipe_patches" => { path => metadata },
    )
    write("provenance.yml", YAML.dump(data))
    patch_api = ["gh", "api", "repos/Homebrew/homebrew-core/contents/#{path}?ref=#{'c' * 40}"]
    payload = { "type" => "file", "sha" => metadata.fetch("blob"), "content" => [patch].pack("m0") }
    [HomebrewTap::ProvenanceManifest.new(root: @root), sha, [source].pack("m0"), info, patch_api, payload]
  end

  it "verifies local patches at the recorded recipe commit before bottle work" do
    manifest, sha, recipe, info, patch_api, payload = setup_local_patch_manifest
    captures = {
      ["gh", "api", "repos/Homebrew/homebrew-core/contents/Formula/f/foo.rb?ref=#{'c' * 40}"] => JSON.generate("sha" => "d" * 40, "content" => recipe),
      patch_api => JSON.generate(payload),
      core_info_command => info,
      core_fetch_command(recipe, sha: sha) => core_fetch_payload(sha: sha),
      bottle_attestation_command => attestation_payload(sha)
    }
    expect(described_class.new(manifest: manifest, runner: FakeRunner.new(captures: captures), out: StringIO.new).verify!(["foo"])).to eq(true)

    mutations = [
      payload.merge("sha" => "f" * 40),
      payload.merge("content" => ["changed patch bytes"].pack("m0")),
      payload.merge("type" => "symlink")
    ]
    mutations.each do |changed|
      fake = FakeRunner.new(captures: captures.merge(patch_api => JSON.generate(changed)))
      allow(fake).to receive(:capture).and_call_original
      expect(fake).not_to receive(:capture).with(*core_info_command)
      expect { described_class.new(manifest: manifest, runner: fake).verify!(["foo"]) }.to raise_error(HomebrewTap::Error, /differs from the recorded upstream patch/)
    end
    ["not json", JSON.generate(payload.except("content"))].each do |invalid|
      fake = FakeRunner.new(captures: captures.merge(patch_api => invalid))
      expect { described_class.new(manifest: manifest, runner: fake).verify!(["foo"]) }.to raise_error(HomebrewTap::Error, /invalid recipe metadata/)
    end
  end

  it "uses native core verification when the current core bottle set matches" do
    manifest, sha, recipe, info = setup_manifest
    runner = FakeRunner.new(captures: {
                              ["gh", "api", "repos/Homebrew/homebrew-core/contents/Formula/f/foo.rb?ref=#{'c' * 40}"] => JSON.generate("sha" => "d" * 40, "content" => recipe),
                              core_info_command => info,
                              core_fetch_command(recipe, sha: sha) => core_fetch_payload(sha: sha),
                              bottle_attestation_command => attestation_payload(sha)
                            })
    out = StringIO.new
    verifier = described_class.new(manifest: manifest, runner: runner, out: out, verified_at: Time.utc(2026, 6, 13))

    expect(verifier.verify!(["foo"])).to eq(true)
    expect(runner.commands).to include(["gh", "auth", "status", "--hostname", "github.com"])
    expect(out.string).to include("Verified bottle provenance: foo")
  end

  it "uses native core verification when the current core formula revision matches" do
    manifest, sha, recipe, info = setup_manifest(revision: 1, core_revision: 1)
    verify_command = core_fetch_command(recipe, sha: sha, version: "1.0.0_1")
    runner = FakeRunner.new(captures: {
                              ["gh", "api", "repos/Homebrew/homebrew-core/contents/Formula/f/foo.rb?ref=#{'c' * 40}"] => JSON.generate("sha" => "d" * 40, "content" => recipe),
                              core_info_command => info,
                              verify_command => core_fetch_payload(sha: sha),
                              bottle_attestation_command => attestation_payload(sha)
                            })
    allow(runner).to receive(:capture).and_call_original
    expect(runner).to receive(:capture).with(*verify_command).and_call_original

    expect(described_class.new(manifest: manifest, runner: runner).verify!(["foo"])).to eq(true)
  end

  it "merges all platform bottle variations before using native core verification" do
    linux_path = write("cache/foo.x86_64_linux.bottle.tar.gz", "linux bottle")
    linux_sha = Digest::SHA256.file(linux_path).hexdigest
    manifest, sha, recipe, info = setup_manifest(extra_bottles: { "x86_64_linux" => linux_sha })
    payload = JSON.parse(info)
    formula = payload.fetch("formulae").first
    files = formula.dig("bottle", "stable", "files")
    linux_file = files.delete("x86_64_linux")
    formula["variations"] = {
      "x86_64_linux" => { "bottle" => { "stable" => { "files" => { "x86_64_linux" => linux_file } } } },
      "arm64_tahoe" => { "bottle" => { "stable" => { "files" => files } } },
      "arm64_linux" => { "dependencies" => ["example"] }
    }
    verify_command = core_fetch_command(recipe, sha: sha, extra_bottles: { "x86_64_linux" => linux_sha })
    runner = FakeRunner.new(captures: {
                              ["gh", "api", "repos/Homebrew/homebrew-core/contents/Formula/f/foo.rb?ref=#{'c' * 40}"] => JSON.generate("sha" => "d" * 40, "content" => recipe),
                              core_info_command => JSON.generate(payload),
                              verify_command => core_fetch_payload(sha: sha, extra_bottles: { "x86_64_linux" => linux_sha }),
                              bottle_attestation_command => attestation_payload(sha),
                              bottle_attestation_command("x86_64_linux") => attestation_payload(linux_sha)
                            })
    allow(runner).to receive(:capture).and_call_original
    expect(runner).to receive(:capture).with(*verify_command).and_call_original

    expect(described_class.new(manifest: manifest, runner: runner).verify!(["foo"])).to eq(true)
  end

  it "rejects conflicting bottle digests across core variations" do
    manifest, _sha, recipe, info = setup_manifest
    payload = JSON.parse(info)
    payload.fetch("formulae").first["variations"] = {
      "x86_64_linux" => {
        "bottle" => { "stable" => { "files" => { "arm64_tahoe" => { "sha256" => "b" * 64 } } } }
      }
    }
    runner = FakeRunner.new(captures: {
                              ["gh", "api", "repos/Homebrew/homebrew-core/contents/Formula/f/foo.rb?ref=#{'c' * 40}"] => JSON.generate("sha" => "d" * 40, "content" => recipe),
                              core_info_command => JSON.generate(payload)
                            })

    expect { described_class.new(manifest: manifest, runner: runner).verify!(["foo"]) }.to raise_error(
      HomebrewTap::Error,
      /conflicting homebrew\/core bottle digests for foo arm64_tahoe/,
    )
  end

  it "rejects changed cached recipe bytes before evaluating the core recipe" do
    source_path = write("cache/foo.rb", "unreviewed recipe")
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-e", fake_core_api + described_class::CORE_FETCH_SCRIPT,
      "foo", "1.0.0", JSON.generate("arm64_tahoe" => "a" * 64), "e" * 64, source_path, "checksum",
    )

    expect(status.success?).to eq(false)
    expect(stderr).to include("foo current core recipe differs from the reviewed recipe")
    expect(stderr).not_to include("UNREVIEWED RECIPE EVALUATED")
  end

  it "rejects a non-core recipe and changed versions or incomplete bottle maps in the child" do
    source_path = write("cache/foo.rb", "reviewed recipe")
    source_sha = Digest::SHA256.file(source_path).hexdigest
    %w[tap version map].each do |mode|
      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, "-e", fake_core_api + described_class::CORE_FETCH_SCRIPT,
        "foo", "1.0.0", JSON.generate("arm64_tahoe" => "a" * 64), source_sha, source_path, mode,
      )

      expect(status.success?).to eq(false)
      message = mode == "tap" ? "did not load from homebrew/core" : "current core version or bottle map changed"
      expect(stderr).to include(message)
    end
  end

  it "verifies an older pinned bottle and attested digest" do
    bottle_path = write("cache/foo.bottle.tar.gz", "bottle")
    manifest, bottle_sha, recipe, info = setup_manifest(bottle_path: bottle_path, core_version: "2.0.0")
    api_command = ["gh", "api", "repos/Homebrew/homebrew-core/contents/Formula/f/foo.rb?ref=#{'c' * 40}"]
    cache_command = ["brew", "--cache", "--bottle-tag=arm64_tahoe", "--formula", "grantbirki/tap/foo"]
    attestation_command = [
      "gh", "attestation", "verify", bottle_path,
      "--repo", "Homebrew/homebrew-core",
      "--format", "json"
    ]
    runner = FakeRunner.new(captures: {
                              api_command => JSON.generate("sha" => "d" * 40, "content" => recipe),
                              core_info_command => info,
                              cache_command => bottle_path,
                              attestation_command => attestation_payload(bottle_sha)
                            })

    expect(described_class.new(manifest: manifest, runner: runner).verify!(["--all"])).to eq(true)
    expect(runner.commands).to include([
                                         "env", "HOMEBREW_NO_AUTO_UPDATE=1", "HOMEBREW_REQUIRE_TAP_TRUST=1",
                                         "brew", "fetch", "--force", "--bottle-tag=arm64_tahoe", "--formula", "grantbirki/tap/foo"
                                       ])
  end

  it "verifies the pinned bottle when only the current core revision differs" do
    bottle_path = write("cache/foo.bottle.tar.gz", "bottle")
    manifest, bottle_sha, recipe, info = setup_manifest(bottle_path: bottle_path, revision: 1, core_revision: 2)
    runner = FakeRunner.new(captures: {
                              ["gh", "api", "repos/Homebrew/homebrew-core/contents/Formula/f/foo.rb?ref=#{'c' * 40}"] => JSON.generate("sha" => "d" * 40, "content" => recipe),
                              core_info_command => info,
                              ["brew", "--cache", "--bottle-tag=arm64_tahoe", "--formula", "grantbirki/tap/foo"] => bottle_path,
                              [
                                "gh", "attestation", "verify", bottle_path,
                                "--repo", "Homebrew/homebrew-core",
                                "--format", "json"
                              ] => attestation_payload(bottle_sha)
                            })

    expect(described_class.new(manifest: manifest, runner: runner).verify!(["foo"])).to eq(true)
    expect(runner.commands).to include([
                                         "env", "HOMEBREW_NO_AUTO_UPDATE=1", "HOMEBREW_REQUIRE_TAP_TRUST=1",
                                         "brew", "fetch", "--force", "--bottle-tag=arm64_tahoe", "--formula", "grantbirki/tap/foo"
                                       ])
  end

  it "fails closed on missing commands, invalid selections, recipes, metadata, bottles, and attestations" do
    manifest, bottle_sha, = setup_manifest(core_version: "2.0.0")
    unavailable = FakeRunner.new(available: false)
    expect { described_class.new(manifest: manifest, runner: unavailable).verify!(["foo"]) }.to raise_error(HomebrewTap::Error, /brew is required/)
    expect { described_class.new(manifest: manifest, runner: FakeRunner.new).verify!([]) }.to raise_error(HomebrewTap::Error, /no formula token/)

    data = YAML.safe_load_file(File.join(@root, "provenance.yml"), aliases: false)
    data["formulae"]["foo"]["source_type"] = "upstream-release"
    data["formulae"]["foo"]["upstream_repository"] = "example/foo"
    data["formulae"]["foo"]["upstream_tag"] = "v1.0.0"
    data["formulae"]["foo"]["upstream_commit"] = "c" * 40
    data["formulae"]["foo"]["artifacts"] = { "source" => "e" * 64 }
    data["formulae"]["foo"].delete_if { |key, _value| key.start_with?("recipe_") }
    write("provenance.yml", YAML.dump(data))
    expect { described_class.new(manifest: HomebrewTap::ProvenanceManifest.new(root: @root), runner: FakeRunner.new).verify!(["foo"]) }.to raise_error(HomebrewTap::Error, /not a homebrew-core formula/)

    manifest, _sha, recipe, info = setup_manifest(core_version: "2.0.0")
    base = {
      core_info_command => info,
      ["gh", "api", "repos/Homebrew/homebrew-core/contents/Formula/f/foo.rb?ref=#{'c' * 40}"] => JSON.generate("sha" => "wrong", "content" => recipe)
    }
    expect { described_class.new(manifest: manifest, runner: FakeRunner.new(captures: base)).verify!(["foo"]) }.to raise_error(HomebrewTap::Error, /recipe blob/)

    base[base.keys.last] = "not-json"
    expect { described_class.new(manifest: manifest, runner: FakeRunner.new(captures: base)).verify!(["foo"]) }.to raise_error(HomebrewTap::Error, /invalid recipe metadata/)

    base[base.keys.last] = JSON.generate("sha" => "d" * 40, "content" => ["no version"].pack("m0"))
    expect { described_class.new(manifest: manifest, runner: FakeRunner.new(captures: base)).verify!(["foo"]) }.to raise_error(HomebrewTap::Error, /version is absent/)

    recipe_without_digest = recipe.unpack1("m0").sub(bottle_sha, "f" * 64).then { |content| [content].pack("m0") }
    base[base.keys.last] = JSON.generate("sha" => "d" * 40, "content" => recipe_without_digest)
    expect { described_class.new(manifest: manifest, runner: FakeRunner.new(captures: base)).verify!(["foo"]) }.to raise_error(HomebrewTap::Error, /bottle digest is absent/)

    base[base.keys.last] = JSON.generate("sha" => "d" * 40, "content" => recipe)
    base[core_info_command] = "bad"
    expect { described_class.new(manifest: manifest, runner: FakeRunner.new(captures: base)).verify!(["foo"]) }.to raise_error(HomebrewTap::Error, /invalid homebrew\/core metadata/)

    empty_bottle = YAML.safe_load_file(File.join(@root, "provenance.yml"), aliases: false)
    empty_bottle["formulae"]["foo"]["bottles"]["digests"] = {}
    File.write(File.join(@root, "Formula/foo.rb"), "class Foo < Formula\n  version \"1.0.0\"\nend\n")
    empty_bottle["formulae"]["foo"]["local_file_sha256"] = Digest::SHA256.file(File.join(@root, "Formula/foo.rb")).hexdigest
    empty_bottle["formulae"]["foo"]["legacy_baseline"]["artifact_fingerprint_sha256"] = Digest::SHA256.hexdigest("")
    write("provenance.yml", YAML.dump(empty_bottle))
    expect { described_class.new(manifest: HomebrewTap::ProvenanceManifest.new(root: @root), runner: FakeRunner.new).verify!(["foo"]) }.to raise_error(HomebrewTap::Error, /has no bottles/)
  end

  it "rejects malformed attestation output" do
    bottle_path = write("cache/foo.bottle.tar.gz", "bottle")
    manifest, _bottle_sha, recipe, info = setup_manifest(bottle_path: bottle_path, core_version: "2.0.0")
    runner = FakeRunner.new(captures: {
                              ["gh", "api", "repos/Homebrew/homebrew-core/contents/Formula/f/foo.rb?ref=#{'c' * 40}"] => JSON.generate("sha" => "d" * 40, "content" => recipe),
                              core_info_command => info,
                              ["brew", "--cache", "--bottle-tag=arm64_tahoe", "--formula", "grantbirki/tap/foo"] => bottle_path,
                              [
                                "gh", "attestation", "verify", bottle_path,
                                "--repo", "Homebrew/homebrew-core",
                                "--format", "json"
                              ] => "not-json"
                            })

    expect { described_class.new(manifest: manifest, runner: runner).verify!(["foo"]) }.to raise_error(HomebrewTap::Error, /invalid attestation metadata/)
  end

  it "rejects recipe input drift and malformed current-core attestation output" do
    manifest, bottle_sha, recipe, info = setup_manifest
    api_command = ["gh", "api", "repos/Homebrew/homebrew-core/contents/Formula/f/foo.rb?ref=#{'c' * 40}"]
    verify_command = core_fetch_command(recipe, sha: bottle_sha)
    drifted = recipe.unpack1("m0").sub("e" * 64, "f" * 64).then { |content| [content].pack("m0") }
    runner = FakeRunner.new(captures: {
                              api_command => JSON.generate("sha" => "d" * 40, "content" => drifted),
                              core_info_command => info
                            })
    expect { described_class.new(manifest: manifest, runner: runner).verify!(["foo"]) }.to raise_error(
      HomebrewTap::Error,
      /source, resource, patch, or checksum data differs/,
    )

    runner = FakeRunner.new(captures: {
                              api_command => JSON.generate("sha" => "d" * 40, "content" => recipe),
                              core_info_command => info,
                              verify_command => "not-json"
                            })
    expect { described_class.new(manifest: manifest, runner: runner).verify!(["foo"]) }.to raise_error(
      HomebrewTap::Error,
      /invalid attestation metadata/,
    )

    [[], JSON.parse(core_fetch_payload(sha: bottle_sha)) * 2].each do |fetched|
      runner = FakeRunner.new(captures: {
                                api_command => JSON.generate("sha" => "d" * 40, "content" => recipe),
                                core_info_command => info,
                                verify_command => JSON.generate(fetched)
                              })
      expect { described_class.new(manifest: manifest, runner: runner).verify!(["foo"]) }.to raise_error(
        HomebrewTap::Error,
        /fetched core bottle map differs/,
      )
    end

    runner = FakeRunner.new(captures: {
                              api_command => JSON.generate("sha" => "d" * 40, "content" => recipe),
                              core_info_command => info,
                              verify_command => core_fetch_payload(sha: bottle_sha),
                              bottle_attestation_command => attestation_payload(bottle_sha, repository: "attacker/repo", workflow: "release.yml")
                            })
    expect { described_class.new(manifest: manifest, runner: runner).verify!(["foo"]) }.to raise_error(
      HomebrewTap::Error,
      /unexpected repository or workflow/,
    )
  end
end

RSpec.describe HomebrewTap::ProvenanceCommand do
  it "prints help and reports unknown commands" do
    out = StringIO.new
    expect(described_class.new(argv: [], out: out, err: StringIO.new, root: @root).run).to eq(0)
    expect(out.string).to include("script/provenance check")

    expect(described_class.new(argv: ["wat"], out: StringIO.new, err: StringIO.new, root: @root).run).to eq(2)
  end

  it "runs checks and reports validation failures" do
    out = StringIO.new
    err = StringIO.new
    expect(described_class.new(argv: ["check"], out: out, err: err, root: @root).run).to eq(1)
    expect(err.string).to include("not found")

    expect(described_class.new(argv: ["check", "extra"], out: out, err: err, root: @root).run).to eq(1)
    expect(err.string).to include("unexpected arguments")
  end

  it "runs successful checks and formula verification" do
    write("provenance.yml", YAML.dump(
                              "schema_version" => 1,
                              "policy_effective_at" => "2026-06-11T00:00:00Z",
                              "formulae" => {},
                              "casks" => {},
                            ))
    out = StringIO.new
    runner = FakeRunner.new
    expect(described_class.new(argv: ["check"], runner: runner, out: out, err: StringIO.new, root: @root).run).to eq(0)
    expect(out.string).to include("Provenance metadata is valid")
    expect(runner.commands.count { |command| command.include?("brew") }).to eq(2)

    verifier = instance_double(HomebrewTap::ProvenanceVerifier, verify!: true)
    allow(HomebrewTap::ProvenanceVerifier).to receive(:new).and_return(verifier)
    expect(described_class.new(argv: ["verify-formula", "foo"], out: out, err: StringIO.new, root: @root).run).to eq(0)
    expect(verifier).to have_received(:verify!).with(["foo"])
  end
end
