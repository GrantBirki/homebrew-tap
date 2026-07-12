# frozen_string_literal: true

require "bundler"
require "tmpdir"
require "yaml"

module HomebrewTap
  module TestChecks
    HOMEBREW_ENV = [
      "HOMEBREW_NO_AUTO_UPDATE=1",
      "HOMEBREW_REQUIRE_TAP_TRUST=1",
      "HOMEBREW_CACHE=#{File.join(Dir.tmpdir, "homebrew-tap-cache")}"
    ].freeze
    LOCAL_CONTENT_ENV = (HOMEBREW_ENV + ["HOMEBREW_NO_INSTALL_FROM_API=1"]).freeze

    FORMULA_TOKENS = %w[
      ansible bash bat dfu-programmer eza ffmpeg gh gnupg hugo libyaml nmap
      osv-scanner pinentry-mac ripgrep rizin rustup swiftformat swiftlint tart tfenv tree
      uninstall vector yq
    ].freeze
    CASK_TOKENS = %w[
      alacritty blockblock cutter imageoptim karabiner-elements keepassxc knockknock osquery santa secretive
    ].freeze
    RUBOCOP_PATHS = %w[lib spec].freeze

    class BundlerSupplyChain
      def initialize(root:)
        @root = root
      end

      def validate
        failures = validate_config + validate_lockfile
        raise Error, failures.join("\n") unless failures.empty?

        true
      end

      private

      def validate_config
        config = YAML.safe_load_file(
          File.join(@root, ".bundle/config"),
          permitted_classes: [],
          permitted_symbols: [],
          aliases: false
        )
        required = {
          "BUNDLE_FROZEN" => "true",
          "BUNDLE_PATH" => "vendor/gems",
          "BUNDLE_CACHE_PATH" => "vendor/cache",
          "BUNDLE_NO_INSTALL" => "true",
          "BUNDLE_DISABLE_SHARED_GEMS" => "true"
        }
        required.filter_map { |key, value| ".bundle/config must set #{key}: #{value.inspect}" unless config[key] == value }
      end

      def validate_lockfile
        text = File.read(File.join(@root, "Gemfile.lock"))
        failures = []
        failures << "Gemfile.lock is missing CHECKSUMS" unless text.match?(/\ACHECKSUMS\n|\nCHECKSUMS\n/)
        specs = Bundler::LockfileParser.new(text).specs
        failures.concat(validate_spec_checksums(text, specs))
        failures.concat(validate_cached_gems(specs))
        failures
      end

      def validate_spec_checksums(text, specs)
        specs.filter_map do |spec|
          version = spec.platform.to_s == "ruby" ? spec.version.to_s : "#{spec.version}-#{spec.platform}"
          next if text.include?("  #{spec.name} (#{version}) sha256=")

          "missing checksum for #{spec.name} (#{version})"
        end
      end

      def validate_cached_gems(specs)
        expected = specs.map { |spec| "#{spec.full_name}.gem" }.sort
        actual = Dir[File.join(@root, "vendor/cache/*.gem")].map { |path| File.basename(path) }.sort
        (expected - actual).map { |gem| "missing cached gem: vendor/cache/#{gem}" } +
          (actual - expected).map { |gem| "extra cached gem: vendor/cache/#{gem}" }
      end
    end

    class WorkflowPins
      def initialize(root:)
        @root = root
      end

      def validate
        failures = []
        Dir[File.join(@root, ".github/workflows/*.{yml,yaml}")].sort.each do |path|
          File.readlines(path).each_with_index do |line, index|
            match = line.match(/\buses:\s*['"]?(?<uses>[^'"\s#]+)['"]?/)
            next unless match

            uses = match[:uses]
            next if uses.start_with?("./")
            next if uses.match?(/@[0-9a-f]{40}\z/i) || uses.match?(/@sha256:[0-9a-f]{64}\z/i)

            failures << "#{relative(path)}:#{index + 1} action is not SHA-pinned: #{uses}"
          end
        end
        raise Error, failures.join("\n") unless failures.empty?

        true
      end

      private

      def relative(path)
        path.delete_prefix("#{@root}/")
      end
    end

    class RubySyntax
      def initialize(root:, runner:, quiet: false)
        @root = root
        @runner = runner
        @quiet = quiet
      end

      def validate
        ruby_files.each { |path| run!("ruby", "-c", path) }
        true
      end

      private

      def run!(*cmd)
        @quiet ? @runner.run_quiet!(*cmd) : @runner.run!(*cmd)
      end

      def ruby_files
        Dir[File.join(@root, "{lib,spec}/**/*.rb")] +
          Dir[File.join(@root, "Formula/**/*.rb")] +
          Dir[File.join(@root, "Casks/**/*.rb")]
      end
    end

    class ShellSyntax
      def initialize(root:, runner:, quiet: false)
        @root = root
        @runner = runner
        @quiet = quiet
      end

      def validate
        scripts.each { |path| run!("bash", "-n", path) }
        true
      end

      private

      def run!(*cmd)
        @quiet ? @runner.run_quiet!(*cmd) : @runner.run!(*cmd)
      end

      def scripts
        Dir[File.join(@root, "script/*")].select do |path|
          File.file?(path) && File.open(path, &:readline).include?("bash")
        rescue EOFError
          false
        end
      end
    end

    class FormulaParsing
      def initialize(root:, runner:)
        @root = root
        @runner = runner
      end

      def validate
        script = <<~'RUBY'
          require "formulary"
          require "pathname"
          require "simulate_system"
          require "yaml"

          manifest = YAML.safe_load_file(ARGV.shift, permitted_classes: [], permitted_symbols: [], aliases: false)

          systems = [
            { os: :tahoe, arch: :arm },
            { os: :tahoe, arch: :intel },
            { os: :linux, arch: :arm },
            { os: :linux, arch: :intel },
          ]

          ARGV.each do |path|
            contents = File.read(path)
            name = File.basename(path, ".rb")
            provenance = manifest.fetch("formulae").fetch(name)
            macos_only = contents.include?("depends_on :macos")
            arm_only = contents.include?("depends_on arch: :arm64")
            systems.each do |system|
              next if macos_only && system[:os] == :linux
              next if arm_only && system[:arch] == :intel

              Homebrew::SimulateSystem.with(**system) do
                formula = Formulary.from_contents(name, Pathname(path), contents)
                raise "#{path}: missing stable URL for #{system}" if formula.stable.url.blank?
                raise "#{path}: mutable head spec" if formula.head
                unless formula.pkg_version.to_s == provenance.fetch("version")
                  raise "#{path}: stable version does not match provenance.yml"
                end

                stable = formula.stable.resource
                raise "#{path}: stable URL must use HTTPS" unless stable.url.start_with?("https://")
                if stable.url.end_with?(".git")
                  revision = stable.specs[:revision]
                  unless revision&.match?(/\A[0-9a-f]{40}\z/i)
                    raise "#{path}: stable Git source must use a full revision"
                  end
                elsif stable.checksum.blank?
                  raise "#{path}: missing stable checksum for #{system}"
                end

                formula.stable.resources.each_value do |resource|
                  raise "#{path}: resource URL must use HTTPS" unless resource.url.start_with?("https://")
                  raise "#{path}: resource #{resource.name} is missing a checksum" if resource.checksum.blank?
                end

                formula.stable.patches.each do |patch|
                  next unless patch.respond_to?(:resource)

                  resource = patch.resource
                  raise "#{path}: patch URL must use HTTPS" unless resource.url.start_with?("https://")
                  raise "#{path}: external patch is missing a checksum" if resource.checksum.blank?
                end
                collector = formula.bottle_specification.collector
                bottles = collector.tags.to_h do |tag|
                  [tag.to_s, collector.specification_for(tag).checksum.to_s]
                end
                expected_bottles = provenance.dig("bottles", "digests") || {}
                raise "#{path}: bottle digests do not match provenance.yml" unless bottles == expected_bottles
                next if collector.tags.empty?

                expected = "https://ghcr.io/v2/homebrew/core"
                unless formula.bottle_specification.root_url == expected
                  raise "#{path}: bottle root must be #{expected}"
                end
              end
            end
          end
        RUBY
        @runner.run!(
          "env",
          *LOCAL_CONTENT_ENV,
          "brew",
          "ruby",
          "-e",
          script,
          File.join(@root, "provenance.yml"),
          *Dir[File.join(@root, "Formula/**/*.rb")].sort,
        )
        true
      end
    end

    class CaskParsing
      def initialize(root:, runner:)
        @root = root
        @runner = runner
      end

      def validate
        script = <<~'RUBY'
          require "simulate_system"
          require "cask/cask_loader"
          require "yaml"

          manifest = YAML.safe_load_file(ARGV.shift, permitted_classes: [], permitted_symbols: [], aliases: false)

          [:arm, :intel].each do |arch|
            Homebrew::SimulateSystem.with(os: :tahoe, arch: arch) do
              ARGV.each do |path|
                cask = Cask::CaskLoader::FromContentLoader.new(File.read(path)).load(config: nil)
                provenance = manifest.fetch("casks").fetch(cask.token)
                raise "#{path}: missing version for #{arch}" if cask.version.blank?
                raise "#{path}: missing sha256 for #{arch}" if cask.sha256.blank? || cask.sha256.to_s == "no_check"
                unless cask.version.to_s == provenance.fetch("version")
                  raise "#{path}: selected version does not match provenance.yml for #{arch}"
                end
                unless provenance.fetch("artifacts").value?(cask.sha256.to_s)
                  raise "#{path}: selected sha256 does not match provenance.yml for #{arch}"
                end
                raise "#{path}: missing URL for #{arch}" if cask.url.to_s.blank?
                raise "#{path}: URL must use HTTPS" unless cask.url.to_s.start_with?("https://")
                install_classes = %w[App Artifact Binary Installer Pkg Suite]
                unless cask.artifacts.any? { |artifact| install_classes.include?(artifact.class.name.split("::").last) }
                  raise "#{path}: missing install artifact for #{arch}"
                end
                if File.read(path).match?(/\b(?:xattr|quarantine|no-quarantine)\b/i)
                  raise "#{path}: quarantine removal is prohibited"
                end
              end
            end
          end
        RUBY
        @runner.run!(
          "env",
          *LOCAL_CONTENT_ENV,
          "brew",
          "ruby",
          "-e",
          script,
          File.join(@root, "provenance.yml"),
          *Dir[File.join(@root, "Casks/**/*.rb")].sort,
        )
        true
      end
    end

    class HomebrewStyle
      def initialize(root:, runner:, quiet: false)
        @root = root
        @runner = runner
        @quiet = quiet
      end

      def validate
        files = Dir[File.join(@root, "{Formula,Casks}/**/*.rb")].sort
        run!(
          "env",
          *HOMEBREW_ENV,
          "brew",
          "style",
          "--except-cops",
          "Layout/HashAlignment,FormulaAudit/BottleDigestIndentation",
          *files,
        )
        true
      end

      private

      def run!(*cmd)
        @quiet ? @runner.run_quiet!(*cmd) : @runner.run!(*cmd)
      end
    end

    class RuboCop
      def initialize(root:, runner:, quiet: false)
        @root = root
        @runner = runner
        @quiet = quiet
      end

      def validate
        run!(
          "env",
          "RUBOCOP_CACHE_ROOT=#{File.join(@root, "tmp/rubocop_cache")}",
          "bundle",
          "exec",
          "rubocop",
          "-c",
          File.join(@root, ".rubocop.yml"),
          *RUBOCOP_PATHS.map { |path| File.join(@root, path) },
        )
        true
      end

      private

      def run!(*cmd)
        @quiet ? @runner.run_quiet!(*cmd) : @runner.run!(*cmd)
      end
    end

    class BrewfileParsing
      def initialize(root:, runner:)
        @root = root
        @runner = runner
      end

      def validate
        script = <<~RUBY
          require "bundle/dsl"
          require "pathname"

          brewfile = Pathname(ARGV.fetch(0))
          entries = Homebrew::Bundle::Dsl.new(brewfile).entries

          unless entries.any? { |entry| entry.type == :tap && entry.name == "grantbirki/tap" }
            raise "Brewfile must tap grantbirki/tap"
          end
        RUBY
        @runner.run!(
          "env",
          *HOMEBREW_ENV,
          "brew",
          "ruby",
          "-e",
          script,
          File.join(@root, "Brewfile"),
        )
        true
      end
    end

    class BrewfilePins
      def initialize(root:)
        @root = root
      end

      def validate
        entries = Brewfile.new(path: File.join(@root, "Brewfile")).tap_entries
        expected = FORMULA_TOKENS.map { |token| [:brew, token] } + CASK_TOKENS.map { |token| [:cask, token] }
        actual = entries.map { |entry| [entry.type, entry.token] }
        failures = (expected - actual).map { |type, token| "Brewfile is missing #{type} #{TAP_NAME}/#{token}" }
        failures.concat((actual - expected).map { |type, token| "Brewfile has unexpected #{type} #{TAP_NAME}/#{token}" })
        failures.concat(actual.tally.filter_map do |(type, token), count|
          "Brewfile duplicates #{type} #{TAP_NAME}/#{token}" if count > 1
        end)
        failures.concat(trust_failures)
        raise Error, failures.join("\n") unless failures.empty?

        true
      end

      private

      def trust_failures
        text = File.read(File.join(@root, "Brewfile"))
        failures = []
        failures << "Brewfile must set cask_args require_sha: true" unless text.match?(/^cask_args\s+require_sha:\s*true\s*$/)
        failures << "Brewfile must not trust the entire tap" if text.match?(/^\s*tap\s+["']#{Regexp.escape(TAP_NAME)}["'].*trusted:\s*true/)
        (FORMULA_TOKENS.map { |token| [:brew, token] } + CASK_TOKENS.map { |token| [:cask, token] }).each do |type, token|
          pattern = /^\s*#{type}\s+["']#{Regexp.escape(TAP_NAME)}\/#{Regexp.escape(token)}["'].*trusted:\s*true/
          failures << "Brewfile #{type} #{TAP_NAME}/#{token} must set trusted: true" unless text.match?(pattern)
        end
        failures
      end
    end
  end
end
