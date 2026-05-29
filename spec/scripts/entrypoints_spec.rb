# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Ruby script entrypoints" do
  it "loads help paths without side effects" do
    %w[install lint test vendor].each do |name|
      result = run_script(File.join(ROOT, "script", name), ["--help"])
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("Usage: script/#{name}")
    end
  end
end
