# frozen_string_literal: true

module HomebrewTap
  ROOT = File.expand_path("..", __dir__)
  TAP_NAME = "grantbirki/tap"

  Error = Class.new(StandardError)
end

require_relative "homebrew_tap/brewfile"
require_relative "homebrew_tap/commands"
require_relative "homebrew_tap/installer"
require_relative "homebrew_tap/receipts"
require_relative "homebrew_tap/runner"
require_relative "homebrew_tap/tap_checkout"
require_relative "homebrew_tap/test_checks"
require_relative "homebrew_tap/vendor"
