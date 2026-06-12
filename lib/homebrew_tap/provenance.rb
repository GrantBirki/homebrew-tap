# frozen_string_literal: true

require "digest"
require "json"
require "time"
require "yaml"

module HomebrewTap
  class ProvenanceManifest
    SCHEMA_VERSION = 1
    COOLDOWN_SECONDS = 14 * 24 * 60 * 60
    OWNER_CONTROLLED_CASKS = {
      "espresso" => "grantbirki/espresso",
      "oneshot" => "grantbirki/oneshot",
      "shit" => "grantbirki/shit"
    }.freeze
    SHA40 = /\A[0-9a-f]{40}\z/i
    SHA256 = /\A[0-9a-f]{64}\z/i
    TOP_LEVEL_KEYS = %w[schema_version policy_effective_at formulae casks].freeze
    SOURCE_TYPES = %w[homebrew-core homebrew-cask upstream-release personal-release].freeze
    COMMON_ENTRY_KEYS = %w[
      source_type local_file_sha256 version release_published_at release_evidence
      adopted_at adoption_commit adoption_reason cooldown_exception legacy_baseline
      local_changes
    ].freeze
    RECIPE_KEYS = %w[recipe_repository recipe_commit recipe_path recipe_blob].freeze
    RELEASE_KEYS = %w[upstream_repository upstream_tag upstream_commit].freeze
    CORE_BOTTLE_ROOT = "https://ghcr.io/v2/homebrew/core"

    attr_reader :root, :path, :data

    def initialize(root:, path: nil)
      @root = root
      @path = path || File.join(root, "provenance.yml")
      @data = nil
    end

    def validate(allow_unverified: false)
      @allow_unverified = allow_unverified
      load!
      failures = validate_top_level
      failures.concat(validate_section("formulae", "Formula"))
      failures.concat(validate_section("casks", "Casks"))
      raise Error, failures.join("\n") unless failures.empty?

      true
    end

    def load!
      @data = YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
      raise Error, "#{relative(path)} must contain a mapping" unless data.is_a?(Hash)

      data
    rescue Errno::ENOENT
      raise Error, "provenance manifest not found: #{path}"
    rescue Psych::Exception => e
      raise Error, "invalid provenance manifest: #{e.message}"
    end

    def formula_entry(token)
      ensure_loaded
      data.fetch("formulae", {}).fetch(token) do
        raise Error, "formula provenance not found: #{token}"
      end
    end

    def formula_tokens
      ensure_loaded
      data.fetch("formulae", {}).keys.sort
    end

    def core_formula_tokens
      ensure_loaded
      data.fetch("formulae", {}).filter_map do |token, entry|
        token if entry["source_type"] == "homebrew-core"
      end.sort
    end

    def record_formula_verifications!(tokens, verified_at: Time.now.utc)
      ensure_loaded
      tokens.each do |token|
        entry = formula_entry(token)
        entry.fetch("bottles")["verified_at"] = verified_at.iso8601
      end
      File.write(path, YAML.dump(data))
    end

    def bottle_digests(entry)
      bottles = entry["bottles"]
      return {} unless bottles.is_a?(Hash)

      digests = bottles["digests"]
      digests.is_a?(Hash) ? digests.transform_keys(&:to_s) : {}
    end

    private

    def ensure_loaded
      load! unless data
    end

    def validate_top_level
      failures = []
      failures << "provenance.yml schema_version must be #{SCHEMA_VERSION}" unless data["schema_version"] == SCHEMA_VERSION
      failures << "provenance.yml has unknown keys: #{(data.keys - TOP_LEVEL_KEYS).join(", ")}" unless (data.keys - TOP_LEVEL_KEYS).empty?
      parse_time(data["policy_effective_at"], "policy_effective_at", failures)
      %w[formulae casks].each do |section|
        failures << "provenance.yml #{section} must be a mapping" unless data[section].is_a?(Hash)
      end
      failures
    end

    def validate_section(section, directory)
      entries = data[section]
      return [] unless entries.is_a?(Hash)

      expected = Dir[File.join(root, directory, "*.rb")].map { |file| File.basename(file, ".rb") }.sort
      actual = entries.keys.sort
      failures = (expected - actual).map { |token| "#{section} is missing #{token}" }
      failures.concat((actual - expected).map { |token| "#{section} has extra entry #{token}" })
      entries.each do |token, entry|
        failures.concat(validate_entry(section, directory, token, entry))
      end
      failures
    end

    def validate_entry(section, directory, token, entry)
      label = "#{section}.#{token}"
      return ["#{label} must be a mapping"] unless entry.is_a?(Hash)

      file = File.join(root, directory, "#{token}.rb")
      failures = []
      validate_entry_keys(section, label, entry, failures)
      validate_source(section, label, entry, failures)
      validate_string(entry["version"], "#{label}.version", failures)
      validate_string(entry["adoption_reason"], "#{label}.adoption_reason", failures)
      validate_sha(entry["adoption_commit"], SHA40, "#{label}.adoption_commit", failures)
      validate_release_evidence(entry["release_evidence"], label, failures)
      validate_sha(entry["local_file_sha256"], SHA256, "#{label}.local_file_sha256", failures)
      validate_local_hash(file, entry, label, failures)
      validate_dates(section, token, entry, label, failures)
      validate_legacy_baseline(entry, label, file, failures) if entry["legacy_baseline"].is_a?(Hash)
      validate_content(file, section, entry, label, failures)
      failures
    end

    def validate_entry_keys(section, label, entry, failures)
      source_keys = %w[homebrew-core homebrew-cask].include?(entry["source_type"]) ? RECIPE_KEYS : RELEASE_KEYS
      artifact_keys = section == "formulae" ? %w[bottles artifacts] : %w[artifacts platform_versions]
      unknown = entry.keys - COMMON_ENTRY_KEYS - source_keys - artifact_keys
      failures << "#{label} has unknown keys: #{unknown.join(", ")}" unless unknown.empty?
    end

    def validate_source(section, label, entry, failures)
      source_type = entry["source_type"]
      failures << "#{label}.source_type is invalid" unless SOURCE_TYPES.include?(source_type)
      if %w[homebrew-core homebrew-cask].include?(source_type)
        validate_string(entry["recipe_repository"], "#{label}.recipe_repository", failures)
        validate_sha(entry["recipe_commit"], SHA40, "#{label}.recipe_commit", failures)
        validate_string(entry["recipe_path"], "#{label}.recipe_path", failures)
        validate_sha(entry["recipe_blob"], SHA40, "#{label}.recipe_blob", failures)
        expected_repository = source_type == "homebrew-core" ? "Homebrew/homebrew-core" : "Homebrew/homebrew-cask"
        failures << "#{label}.recipe_repository must be #{expected_repository}" unless entry["recipe_repository"] == expected_repository
      else
        validate_string(entry["upstream_repository"], "#{label}.upstream_repository", failures)
        validate_sha(entry["upstream_commit"], SHA40, "#{label}.upstream_commit", failures)
        validate_string(entry["upstream_tag"], "#{label}.upstream_tag", failures)
      end
      if section == "formulae" && source_type == "homebrew-cask"
        failures << "#{label} cannot use homebrew-cask provenance"
      elsif section == "casks" && source_type == "homebrew-core"
        failures << "#{label} cannot use homebrew-core provenance"
      end
      changes = entry["local_changes"]
      return if changes.is_a?(Array) && changes.all? { |change| present?(change) }

      failures << "#{label}.local_changes must contain only non-empty strings"
    end

    def validate_release_evidence(evidence, label, failures)
      unless evidence.is_a?(Hash)
        failures << "#{label}.release_evidence must be a mapping"
        return
      end

      validate_string(evidence["description"], "#{label}.release_evidence.description", failures)
      failures << "#{label}.release_evidence.reference must be an HTTPS URL" unless https_url?(evidence["reference"])
    end

    def validate_local_hash(file, entry, label, failures)
      return unless File.file?(file)
      return unless entry["local_file_sha256"].to_s.match?(SHA256)

      actual = Digest::SHA256.file(file).hexdigest
      failures << "#{label}.local_file_sha256 does not match #{relative(file)}" unless actual == entry["local_file_sha256"]
    end

    def validate_dates(section, token, entry, label, failures)
      release_time = parse_time(entry["release_published_at"], "#{label}.release_published_at", failures)
      adopted_time = parse_time(entry["adopted_at"], "#{label}.adopted_at", failures)
      effective_time = parse_time(data["policy_effective_at"], "policy_effective_at", failures)
      return unless release_time && adopted_time && effective_time

      failures << "#{label}.adopted_at predates release_published_at" if adopted_time < release_time
      exception = entry["cooldown_exception"]
      if !exception.nil? && !(exception.is_a?(Hash) && present?(exception["reason"]) && https_url?(exception["reference"]))
        failures << "#{label}.cooldown_exception must contain a reason and primary-source HTTPS reference"
      end

      if entry["legacy_baseline"].is_a?(Hash)
        failures << "#{label}.legacy_baseline is only valid before policy_effective_at" unless adopted_time < effective_time
        return
      end
      failures << "#{label}.legacy_baseline must be a mapping or null" unless entry["legacy_baseline"].nil?

      return if owner_controlled_cask?(section, token, entry)
      return if adopted_time - release_time >= COOLDOWN_SECONDS

      return if exception.is_a?(Hash) && present?(exception["reason"]) && https_url?(exception["reference"])

      failures << "#{label} violates the 14-day cooldown without a documented exception"
    end

    def owner_controlled_cask?(section, token, entry)
      repository = OWNER_CONTROLLED_CASKS[token]
      section == "casks" && repository &&
        entry["source_type"] == "personal-release" &&
        entry["upstream_repository"].to_s.casecmp?(repository)
    end

    def validate_legacy_baseline(entry, label, file, failures)
      baseline = entry["legacy_baseline"]
      failures << "#{label}.legacy_baseline.version does not match" unless baseline["version"] == entry["version"]
      current = Digest::SHA256.hexdigest(direct_digest_set(file).join("\n"))
      recorded = baseline["artifact_fingerprint_sha256"]
      validate_sha(recorded, SHA256, "#{label}.legacy_baseline.artifact_fingerprint_sha256", failures)
      failures << "#{label}.legacy_baseline artifact fingerprint does not match" unless current == recorded
    end

    def direct_digest_set(file)
      return [] unless File.file?(file)

      File.read(file).scan(/\b[0-9a-f]{64}\b/i).map(&:downcase).uniq.sort
    end

    def validate_content(file, section, entry, label, failures)
      return unless File.file?(file)

      content = File.read(file)
      failures << "#{label}.version does not appear in #{relative(file)}" unless version_appears?(content, entry["version"])
      failures << "#{relative(file)} contains a mutable head spec" if content.match?(/^\s*head(?:\s|\()/)
      failures << "#{relative(file)} contains an insecure artifact URL" if content.match?(/^\s*url\s+"http:\/\//)
      failures << "#{relative(file)} uses sha256 :no_check" if content.include?("sha256 :no_check")
      validate_git_revisions(content, file, failures)
      if section == "formulae"
        validate_formula_artifacts(content, entry, label, failures) unless %w[homebrew-core].include?(entry["source_type"])
        validate_formula_bottles(content, entry, label, failures)
      else
        validate_cask_artifacts(content, entry, label, failures)
        failures << "#{relative(file)} removes or bypasses quarantine" if content.match?(/\b(?:xattr|quarantine|no-quarantine)\b/i)
      end
    end

    def version_appears?(content, version)
      return true if content.include?(version.to_s)

      match = version.to_s.match(/\A(.+)_([1-9]\d*)\z/)
      match && content.include?(match[1]) && content.match?(/^  revision\s+#{Regexp.escape(match[2])}\s*$/)
    end

    def validate_git_revisions(content, file, failures)
      lines = content.lines
      lines.each_with_index do |line, index|
        next unless line.match?(/^\s*url\s+"https:\/\/[^"]+\.git"/)

        block = lines[index, 4].join
        revision = block[/revision:\s*"([0-9a-f]+)"/i, 1]
        failures << "#{relative(file)} git source must use a full revision" unless revision&.match?(SHA40)
      end
    end

    def validate_formula_bottles(content, entry, label, failures)
      actual = formula_bottle_digests(content)
      expected = bottle_digests(entry)
      failures << "#{label}.bottles digests do not match the formula" unless actual == expected
      return if actual.empty?

      bottles = entry["bottles"]
      unless bottles.is_a?(Hash)
        failures << "#{label}.bottles must be a mapping"
        return
      end
      failures << "#{label}.bottles.repository must be Homebrew/homebrew-core" unless bottles["repository"] == "Homebrew/homebrew-core"
      parse_time(bottles["verified_at"], "#{label}.bottles.verified_at", failures) unless @allow_unverified && bottles["verified_at"].nil?
      failures << "#{label} bottle root must be #{CORE_BOTTLE_ROOT}" unless content.include?(%(root_url "#{CORE_BOTTLE_ROOT}"))
    end

    def validate_formula_artifacts(content, entry, label, failures)
      expected = entry["artifacts"]
      unless expected.is_a?(Hash) && !expected.empty? && expected.values.all? { |value| value.to_s.match?(SHA256) }
        failures << "#{label}.artifacts must map direct release assets to SHA-256 values"
        return
      end

      actual = formula_source_digests(content)
      failures << "#{label}.artifacts do not match the formula" unless actual == expected.values.map(&:downcase).sort
    end

    def validate_cask_artifacts(content, entry, label, failures)
      expected = entry["artifacts"]
      unless expected.is_a?(Hash) && !expected.empty? && expected.values.all? { |value| value.to_s.match?(SHA256) }
        failures << "#{label}.artifacts must map variants to SHA-256 values"
        return
      end
      actual = content.scan(/\b[0-9a-f]{64}\b/i).map(&:downcase).uniq.sort
      failures << "#{label}.artifacts do not match the cask" unless actual == expected.values.map(&:downcase).uniq.sort

      platform_versions = entry["platform_versions"]
      return if platform_versions.nil?

      unless platform_versions.is_a?(Hash) && !platform_versions.empty? &&
             platform_versions.values.all? { |version| present?(version) }
        failures << "#{label}.platform_versions must map platforms to versions"
        return
      end
      missing = platform_versions.values.reject { |version| content.include?(version) }
      failures << "#{label}.platform_versions are absent from the cask: #{missing.join(", ")}" unless missing.empty?
    end

    def formula_bottle_digests(content)
      block = content[/^  bottle do\n(?<body>.*?)^  end\n/m, :body]
      return {} unless block

      block.scan(/sha256\s+(?:cellar:\s*[^,]+,\s*)?(?<tag>[a-z0-9_]+):\s*"(?<sha>[0-9a-f]{64})"/i)
           .to_h
    end

    def formula_source_digests(content)
      without_bottles = content.sub(/^  bottle do\n.*?^  end\n/m, "")
      without_bottles.scan(/^\s*sha256\s+"([0-9a-f]{64})"/i).flatten.map(&:downcase).sort
    end

    def validate_string(value, label, failures)
      failures << "#{label} must be a non-empty string" unless present?(value)
    end

    def validate_sha(value, pattern, label, failures)
      failures << "#{label} is invalid" unless value.to_s.match?(pattern)
    end

    def parse_time(value, label, failures)
      Time.iso8601(value.to_s)
    rescue ArgumentError
      failures << "#{label} must be an ISO-8601 timestamp"
      nil
    end

    def present?(value)
      value.is_a?(String) && !value.strip.empty?
    end

    def https_url?(value)
      present?(value) && value.start_with?("https://")
    end

    def relative(file)
      file.delete_prefix("#{root}/")
    end
  end

  class ProvenanceVerifier
    CORE_REPOSITORY = "Homebrew/homebrew-core"
    CORE_SIGNER_WORKFLOWS = %w[
      dispatch-build-bottle.yml
      dispatch-rebottle.yml
      publish-commit-bottles.yml
    ].freeze

    attr_reader :manifest, :runner, :out, :verified_at

    def initialize(manifest:, runner: Runner.new, out: $stdout, verified_at: Time.now.utc)
      @manifest = manifest
      @runner = runner
      @out = out
      @verified_at = verified_at
    end

    # This is an imperative verification operation that records timestamps, not a predicate.
    def verify!(tokens) # rubocop:disable Naming/PredicateMethod
      manifest.validate(allow_unverified: true)
      require_commands!
      runner.run_quiet!("gh", "auth", "status", "--hostname", "github.com")
      tokens = manifest.core_formula_tokens if tokens == ["--all"]
      raise Error, "no formula token supplied" if tokens.empty?

      verified = tokens.map { |token| verify_formula(token) }
      manifest.record_formula_verifications!(verified, verified_at: verified_at)
      out.puts "Verified bottle provenance: #{verified.join(", ")}"
      true
    end

    private

    def require_commands!
      %w[brew gh].each do |command|
        raise Error, "#{command} is required for formula provenance verification" unless runner.command_available?(command)
      end
    end

    def verify_formula(token)
      entry = manifest.formula_entry(token)
      raise Error, "#{token} is not a homebrew-core formula" unless entry["source_type"] == "homebrew-core"

      digests = manifest.bottle_digests(entry)
      raise Error, "#{token} has no bottles to verify" if digests.empty?

      verify_recipe!(token, entry)
      info = core_info(token)
      if info["version"] == entry["version"] && info["digests"] == digests
        verify_current_core!(token, digests.values)
      else
        digests.each { |tag, digest| verify_pinned_bottle!(token, tag, digest) }
      end
      token
    end

    def verify_recipe!(token, entry)
      response = runner.capture(
        "gh", "api",
        "repos/#{entry.fetch("recipe_repository")}/contents/#{entry.fetch("recipe_path")}?ref=#{entry.fetch("recipe_commit")}",
      )
      payload = JSON.parse(response)
      raise Error, "#{token} recipe blob does not match provenance.yml" unless payload["sha"] == entry["recipe_blob"]

      content = payload.fetch("content", "").unpack1("m")
      upstream_version = entry.fetch("version").sub(/_[1-9]\d*\z/, "")
      raise Error, "#{token} version is absent from the recorded upstream recipe" unless content.include?(upstream_version)
      unless immutable_recipe_inputs(content) == immutable_recipe_inputs(File.read(File.join(manifest.root, "Formula", "#{token}.rb")))
        raise Error, "#{token} source, resource, patch, or checksum data differs from the recorded upstream recipe"
      end

      manifest.bottle_digests(entry).each_value do |digest|
        raise Error, "#{token} bottle digest is absent from the recorded upstream recipe" unless content.include?(digest)
      end
    rescue ArgumentError, JSON::ParserError, KeyError => e
      raise Error, "invalid recipe metadata for #{token}: #{e.message}"
    end

    def immutable_recipe_inputs(content)
      without_bottles = content.sub(/^  bottle do\n.*?^  end\n/m, "")
      without_head = without_bottles.gsub(/^  head do\n.*?^  end\n/m, "")
                                    .gsub(/^  head\s+.*\n/, "")
      urls = without_head.scan(/^\s*(url|mirror)\s+"([^"]+)"/i)
      git_refs = without_head.scan(/\b(tag|revision):\s*"([^"]+)"/i)
      hashes = without_head.scan(/\b[0-9a-f]{40}(?:[0-9a-f]{24})?\b/i).map { |value| ["hash", value] }
      urls + git_refs + hashes
    end

    def core_info(token)
      payload = JSON.parse(runner.capture("brew", "info", "--json=v2", "homebrew/core/#{token}"))
      formula = payload.fetch("formulae").fetch(0)
      files = formula.dig("bottle", "stable", "files") || {}
      digests = files.to_h do |tag, metadata|
        [tag.to_s, metadata.fetch("sha256")]
      end
      { "version" => formula.dig("versions", "stable"), "digests" => digests }
    rescue JSON::ParserError, IndexError => e
      raise Error, "invalid homebrew/core metadata for #{token}: #{e.message}"
    end

    def verify_current_core!(token, digests)
      output = runner.capture(
        "env", "HOMEBREW_NO_AUTO_UPDATE=1",
        "brew", "verify", "--os", "all", "--arch", "all", "--quiet", "--json", "homebrew/core/#{token}",
      )
      json = output.lines.reverse.find { |line| line.lstrip.start_with?("[") } || output
      validate_attestations!(JSON.parse(json), digests, token)
    rescue JSON::ParserError => e
      raise Error, "invalid attestation metadata for #{token}: #{e.message}"
    end

    def verify_pinned_bottle!(token, tag, digest)
      full_name = "#{TAP_NAME}/#{token}"
      runner.run!(
        "env", "HOMEBREW_NO_AUTO_UPDATE=1", "HOMEBREW_REQUIRE_TAP_TRUST=1",
        "brew", "fetch", "--force", "--bottle-tag=#{tag}", "--formula", full_name,
      )
      cache_path = runner.capture("brew", "--cache", "--bottle-tag=#{tag}", "--formula", full_name).strip
      raise Error, "brew did not return a cached bottle for #{token} #{tag}" if cache_path.empty? || !File.file?(cache_path)
      raise Error, "#{token} #{tag} bottle checksum does not match provenance.yml" unless Digest::SHA256.file(cache_path).hexdigest == digest

      attestation = runner.capture(
        "gh", "attestation", "verify", cache_path,
        "--repo", CORE_REPOSITORY,
        "--format", "json",
      )
      payload = JSON.parse(attestation)
      validate_attestations!(payload, [digest], "#{token} #{tag}")
    rescue JSON::ParserError => e
      raise Error, "invalid attestation metadata for #{token} #{tag}: #{e.message}"
    end

    def validate_attestations!(payload, expected_digests, label)
      expected = expected_digests.map(&:downcase).uniq
      attestations = payload.is_a?(Array) ? payload : [payload]
      relevant = attestations.select do |attestation|
        attested_digests(attestation).map(&:downcase).intersect?(expected)
      end
      found = relevant.flat_map { |attestation| attested_digests(attestation) }.map(&:downcase).uniq
      missing = expected - found
      raise Error, "#{label} attestation subject digest mismatch: #{missing.join(", ")}" unless missing.empty?

      relevant.each do |attestation|
        certificate = attestation.dig("verificationResult", "signature", "certificate") || {}
        repository = certificate["githubWorkflowRepository"]
        identity = certificate["subjectAlternativeName"].to_s
        workflow = identity[%r{\Ahttps://github\.com/Homebrew/homebrew-core/\.github/workflows/([^@/]+)@}, 1]
        next if repository == CORE_REPOSITORY && CORE_SIGNER_WORKFLOWS.include?(workflow)

        raise Error, "#{label} was attested by an unexpected repository or workflow"
      end
    end

    def attested_digests(value)
      case value
      when Hash
        own = value["sha256"] ? [value["sha256"]] : []
        own + value.values.flat_map { |child| attested_digests(child) }
      when Array
        value.flat_map { |child| attested_digests(child) }
      else
        []
      end
    end
  end

  class ProvenanceCommand
    USAGE = <<~USAGE
      Usage:
        script/provenance check
        script/provenance verify-formula <token>
        script/provenance verify-formula --all
    USAGE

    def initialize(argv:, runner: Runner.new, out: $stdout, err: $stderr, root: ROOT)
      @argv = argv.dup
      @runner = runner
      @out = out
      @err = err
      @root = root
    end

    def run
      return help(0) if @argv.empty? || %w[--help -h].include?(@argv.first)

      manifest = ProvenanceManifest.new(root: @root)
      case @argv.shift
      when "check"
        raise Error, "unexpected arguments: #{@argv.join(" ")}" unless @argv.empty?

        manifest.validate
        TestChecks::FormulaParsing.new(root: @root, runner: @runner).validate
        TestChecks::CaskParsing.new(root: @root, runner: @runner).validate
        @out.puts "Provenance metadata is valid."
      when "verify-formula"
        ProvenanceVerifier.new(manifest: manifest, runner: @runner, out: @out).verify!(@argv)
      else
        return help(2)
      end
      0
    rescue Error => e
      @err.puts e.message
      1
    end

    private

    def help(status)
      @out.puts USAGE
      status
    end
  end
end
