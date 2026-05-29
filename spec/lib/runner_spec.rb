# frozen_string_literal: true

require "spec_helper"

RSpec.describe HomebrewTap::Runner do
  it "runs commands, captures output, detects commands, and reports failures" do
    out = StringIO.new
    runner = described_class.new(out: out)

    expect(runner.run("ruby", "-e", "exit 0")).to be_success
    expect(runner.run!("ruby", "-e", "exit 0")).to be_success
    expect(out.string).to include("$ ruby -e exit\\ 0")
    expect(runner.capture("ruby", "-e", "puts :ok")).to eq("ok\n")
    expect(runner.capture("ruby", "-e", "abort :no", allow_failure: true)).to eq("")
    expect(runner.command_available?("ruby")).to eq(true)
    expect(runner.command_available?("definitely-not-a-command")).to eq(false)

    expect { runner.run!("ruby", "-e", "exit 1") }.to raise_error(HomebrewTap::Error, /command failed/)
    expect { runner.capture("ruby", "-e", "abort :no") }.to raise_error(HomebrewTap::Error, /no/)
  end
end
