# frozen_string_literal: true

require "spec_helper"

RSpec.describe HomebrewTap::Vendor do
  it "prints help and rejects unknown options" do
    stdout = StringIO.new
    expect(described_class.new(argv: ["--help"], out: stdout, err: StringIO.new).run).to eq(0)
    expect(stdout.string).to include("Usage: script/vendor")

    expect do
      described_class.new(argv: ["--wat"], out: StringIO.new, err: StringIO.new).run
    end.to raise_error(SystemExit)
  end

  it "dry-runs and executes the vendoring commands" do
    stdout = StringIO.new
    fake = FakeRunner.new

    expect(described_class.new(argv: ["--dry-run"], runner: fake, out: stdout, err: StringIO.new).run).to eq(0)
    expect(fake.commands).to eq([])
    expect(stdout.string).to include("would run: bundle lock --add-checksums")

    expect(described_class.new(argv: [], runner: fake, out: StringIO.new, err: StringIO.new).run).to eq(0)
    expect(fake.commands).to eq(HomebrewTap::Vendor::COMMANDS)

    failing = FakeRunner.new(failures: [HomebrewTap::Vendor::COMMANDS.first])
    stderr = StringIO.new
    expect(described_class.new(argv: [], runner: failing, out: StringIO.new, err: stderr).run).to eq(1)
    expect(stderr.string).to include("command failed")
  end
end
