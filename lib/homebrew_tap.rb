# frozen_string_literal: true

module HomebrewTap
  ROOT = File.expand_path("..", __dir__)
  TAP_NAME = "grantbirki/tap"

  Error = Class.new(StandardError)
end
