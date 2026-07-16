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

  it "allows immediate adoption of owner-controlled personal formulae and casks" do
    expect(manifest(owner_controlled_formula_data("uninstall", "GrantBirki/uninstall")).validate).to eq(true)
    expect(manifest(owner_controlled_cask_data("espresso", "GrantBirki/espresso")).validate).to eq(true)
  end

  it "keeps personal releases outside the owner-controlled account on the cooldown" do
    expect { manifest(owner_controlled_formula_data("uninstall", "example/uninstall")).validate }
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

  def setup_manifest(bottle_path: nil, core_version: "1.0.0", source_type: "homebrew-core", bottles: true)
    bottle_sha = bottle_path ? Digest::SHA256.file(bottle_path).hexdigest : "a" * 64
    formula = <<~RUBY
      class Foo < Formula
        url "https://example.com/foo-1.0.0.tar.gz"
        sha256 "#{'e' * 64}"
        bottle do
          root_url "https://ghcr.io/v2/homebrew/core"
          sha256 arm64_tahoe: "#{bottle_sha}"
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
      "version" => "1.0.0",
      "release_published_at" => "2026-01-01T00:00:00Z",
      "release_evidence" => { "description" => "Release", "reference" => "https://example.com/foo/1.0.0" },
      "adopted_at" => "2026-02-01T00:00:00Z",
      "adoption_commit" => "c" * 40,
      "adoption_reason" => "Pin",
      "cooldown_exception" => nil,
      "legacy_baseline" => {
        "version" => "1.0.0",
        "artifact_fingerprint_sha256" => Digest::SHA256.hexdigest(digests.join("\n"))
      },
      "local_changes" => [],
      "bottles" => if bottles
                     {
                       "repository" => "Homebrew/homebrew-core",
                       "verified_at" => "2026-06-11T00:00:00Z",
                       "digests" => { "arm64_tahoe" => bottle_sha }
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
        "bottle" => { "stable" => { "files" => { "arm64_tahoe" => { "sha256" => bottle_sha } } } }
      }],
    )
    [HomebrewTap::ProvenanceManifest.new(root: @root), bottle_sha, recipe, info]
  end

  it "uses brew verify when the current core bottle set matches" do
    manifest, sha, recipe, info = setup_manifest
    runner = FakeRunner.new(captures: {
                              ["gh", "api", "repos/Homebrew/homebrew-core/contents/Formula/f/foo.rb?ref=#{'c' * 40}"] => JSON.generate("sha" => "d" * 40, "content" => recipe),
                              ["brew", "info", "--json=v2", "homebrew/core/foo"] => info,
                              [
                                "env", "HOMEBREW_NO_AUTO_UPDATE=1",
                                "brew", "verify", "--os", "all", "--arch", "all", "--quiet", "--json", "homebrew/core/foo"
                              ] => attestation_payload(sha)
                            })
    out = StringIO.new
    verifier = described_class.new(manifest: manifest, runner: runner, out: out, verified_at: Time.utc(2026, 6, 13))

    expect(verifier.verify!(["foo"])).to eq(true)
    expect(runner.commands).to include(["gh", "auth", "status", "--hostname", "github.com"])
    expect(out.string).to include("Verified bottle provenance: foo")
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
                              ["brew", "info", "--json=v2", "homebrew/core/foo"] => info,
                              cache_command => bottle_path,
                              attestation_command => attestation_payload(bottle_sha)
                            })

    expect(described_class.new(manifest: manifest, runner: runner).verify!(["--all"])).to eq(true)
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
      ["brew", "info", "--json=v2", "homebrew/core/foo"] => info,
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
    base[["brew", "info", "--json=v2", "homebrew/core/foo"]] = "bad"
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
                              ["brew", "info", "--json=v2", "homebrew/core/foo"] => info,
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
    verify_command = [
      "env", "HOMEBREW_NO_AUTO_UPDATE=1",
      "brew", "verify", "--os", "all", "--arch", "all", "--quiet", "--json", "homebrew/core/foo"
    ]
    drifted = recipe.unpack1("m0").sub("e" * 64, "f" * 64).then { |content| [content].pack("m0") }
    runner = FakeRunner.new(captures: {
                              api_command => JSON.generate("sha" => "d" * 40, "content" => drifted),
                              ["brew", "info", "--json=v2", "homebrew/core/foo"] => info
                            })
    expect { described_class.new(manifest: manifest, runner: runner).verify!(["foo"]) }.to raise_error(
      HomebrewTap::Error,
      /source, resource, patch, or checksum data differs/,
    )

    runner = FakeRunner.new(captures: {
                              api_command => JSON.generate("sha" => "d" * 40, "content" => recipe),
                              ["brew", "info", "--json=v2", "homebrew/core/foo"] => info,
                              verify_command => "not-json"
                            })
    expect { described_class.new(manifest: manifest, runner: runner).verify!(["foo"]) }.to raise_error(
      HomebrewTap::Error,
      /invalid attestation metadata/,
    )

    runner = FakeRunner.new(captures: {
                              api_command => JSON.generate("sha" => "d" * 40, "content" => recipe),
                              ["brew", "info", "--json=v2", "homebrew/core/foo"] => info,
                              verify_command => attestation_payload(bottle_sha, repository: "attacker/repo", workflow: "release.yml")
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
