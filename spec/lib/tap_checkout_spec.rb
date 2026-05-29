# frozen_string_literal: true

require "spec_helper"

RSpec.describe HomebrewTap::TapCheckout do
  it "only reports in dry-run mode" do
    out = StringIO.new
    yielded = false

    described_class.new(runner: FakeRunner.new, repo_root: @root, out: out).with_current_checkout(dry_run: true) do
      yielded = true
    end

    expect(yielded).to eq(true)
    expect(out.string).to include("would use current checkout")
  end

  it "does nothing when the installed tap path is this checkout" do
    runner = FakeRunner.new(captures: { ["brew", "--repo", "grantbirki/tap"] => @root })

    described_class.new(runner: runner, repo_root: @root).with_current_checkout(dry_run: false) {}

    expect(runner.commands).to eq([])
  end

  it "does nothing when the installed tap already points at this commit" do
    tap_path = File.join(@root, "tap")
    runner = FakeRunner.new(captures: {
      ["brew", "--repo", "grantbirki/tap"] => tap_path,
      ["git", "-C", @root, "rev-parse", "HEAD"] => "abc\n",
      ["git", "-C", tap_path, "rev-parse", "HEAD"] => "abc\n"
    })

    described_class.new(runner: runner, repo_root: @root).with_current_checkout(dry_run: false) {}

    expect(runner.commands).to eq([])
  end

  it "temporarily detaches the tap and restores a branch" do
    tap_path = File.join(@root, "tap")
    runner = FakeRunner.new(captures: {
      ["brew", "--repo", "grantbirki/tap"] => tap_path,
      ["git", "-C", @root, "rev-parse", "HEAD"] => "new\n",
      ["git", "-C", tap_path, "rev-parse", "HEAD"] => "old\n",
      ["git", "-C", tap_path, "symbolic-ref", "--quiet", "--short", "HEAD"] => "main\n"
    })

    described_class.new(runner: runner, repo_root: @root).with_current_checkout(dry_run: false) {}

    expect(runner.commands).to eq([
      ["git", "-C", tap_path, "fetch", "--quiet", @root, "HEAD"],
      ["git", "-C", tap_path, "checkout", "--quiet", "--detach", "FETCH_HEAD"],
      ["git", "-C", tap_path, "checkout", "--quiet", "main"]
    ])
  end

  it "restores a detached tap even if the install block fails" do
    tap_path = File.join(@root, "tap")
    runner = FakeRunner.new(captures: {
      ["brew", "--repo", "grantbirki/tap"] => tap_path,
      ["git", "-C", @root, "rev-parse", "HEAD"] => "new\n",
      ["git", "-C", tap_path, "rev-parse", "HEAD"] => "old\n",
      ["git", "-C", tap_path, "symbolic-ref", "--quiet", "--short", "HEAD"] => ""
    })

    expect do
      described_class.new(runner: runner, repo_root: @root).with_current_checkout(dry_run: false) { raise "boom" }
    end.to raise_error("boom")

    expect(runner.commands.last).to eq(["git", "-C", tap_path, "checkout", "--quiet", "--detach", "old"])
  end
end
