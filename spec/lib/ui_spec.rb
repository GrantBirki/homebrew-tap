# frozen_string_literal: true

require "spec_helper"

RSpec.describe HomebrewTap::UI do
  it "prints readable installer messages without colors by default" do
    out = StringIO.new
    err = StringIO.new
    ui = described_class.new(out: out, err: err)

    ui.step("Using Brewfile")
    ui.success("Install complete")
    ui.info("Summary")
    ui.warning("Needs repoint")
    ui.skip("Skipping update")
    ui.dry_run("brew update")
    ui.command(["ruby", "-e", "exit 0"])
    ui.command(["ruby", "-e", "puts :ok\nputs :done"])
    ui.error("boom")

    expect(out.string).to include("🍺 Using Brewfile")
    expect(out.string).to include("✅ Install complete")
    expect(out.string).to include("ℹ️  Summary")
    expect(out.string).to include("⚠️  Needs repoint")
    expect(out.string).to include("⏭️  Skipping update")
    expect(out.string).to include("📝 would run: brew update")
    expect(out.string).to include("$ ruby -e exit\\ 0")
    expect(out.string).to include("$ ruby -e puts\\ :ok\\ ...")
    expect(err.string).to include("❌ boom")
    expect(out.string).not_to include("\e[")
  end

  it "colors output when requested" do
    out = StringIO.new

    described_class.new(out: out, color: true).success("ok")

    expect(out.string).to include("\e[0;32m")
    expect(out.string).to include("\e[0m")
  end
end
