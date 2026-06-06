# frozen_string_literal: true

require "bundler"
require "tmpdir"
require "yaml"

module HomebrewTap
  module TestChecks
    HOMEBREW_ENV = [
      "HOMEBREW_NO_INSTALL_FROM_API=1",
      "HOMEBREW_CACHE=#{File.join(Dir.tmpdir, "homebrew-tap-cache")}"
    ].freeze

    FORMULA_TOKENS = %w[
      ansible bash bat dfu-programmer eza ffmpeg gh gnupg hugo libyaml nmap
      pinentry-mac ripgrep rizin rustup swiftformat swiftlint tfenv tree
      uninstall vector yq
    ].freeze
    CASK_TOKENS = %w[
      alacritty blockblock cutter imageoptim karabiner-elements keepassxc knockknock santa secretive
    ].freeze
    RUBOCOP_PATHS = %w[
      lib spec script/install script/lint script/test script/vendor
    ].freeze

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
          "BUNDLE_NO_INSTALL" => "true"
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
          Dir[File.join(@root, "Casks/**/*.rb")] +
          %w[script/install script/lint script/test script/vendor].map { |path| File.join(@root, path) }
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

          [:arm, :intel].each do |arch|
            Homebrew::SimulateSystem.with(os: :tahoe, arch: arch) do
              ARGV.each do |path|
                cask = Cask::CaskLoader::FromContentLoader.new(File.read(path)).load(config: nil)
                raise "#{path}: missing version for #{arch}" if cask.version.blank?
                raise "#{path}: missing sha256 for #{arch}" if cask.sha256.blank?
                raise "#{path}: missing URL for #{arch}" if cask.url.to_s.blank?
              end
            end
          end
        RUBY
        @runner.run!(
          "env",
          *HOMEBREW_ENV,
          "brew",
          "ruby",
          "-e",
          script,
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
        failures = FORMULA_TOKENS.filter_map { |token| missing(entries, :brew, token) }
        failures.concat(CASK_TOKENS.filter_map { |token| missing(entries, :cask, token) })
        raise Error, failures.join("\n") unless failures.empty?

        true
      end

      private

      def missing(entries, type, token)
        expected = "#{TAP_NAME}/#{token}"
        return if entries.any? { |entry| entry.type == type && entry.full_name == expected }

        "Brewfile is missing #{type} #{expected}"
      end
    end
  end
end
