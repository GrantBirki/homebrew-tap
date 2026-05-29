# frozen_string_literal: true

module HomebrewTap
  class TapCheckout
    attr_reader :runner, :repo_root, :tap_name, :out

    def initialize(runner:, repo_root: ROOT, tap_name: TAP_NAME, out: $stdout)
      @runner = runner
      @repo_root = repo_root
      @tap_name = tap_name
      @out = out
    end

    def with_current_checkout(dry_run:)
      if dry_run
        out.puts "would use current checkout for #{tap_name} during install"
        yield
        return
      end

      tap_path = runner.capture("brew", "--repo", tap_name).strip
      return yield if tap_path == repo_root

      repo_head = runner.capture("git", "-C", repo_root, "rev-parse", "HEAD").strip
      tap_head = runner.capture("git", "-C", tap_path, "rev-parse", "HEAD").strip
      return yield if repo_head == tap_head

      restore_branch = runner.capture("git", "-C", tap_path, "symbolic-ref", "--quiet", "--short", "HEAD", allow_failure: true).strip
      out.puts "Using this checkout for #{tap_name} during this install..."
      runner.run!("git", "-C", tap_path, "fetch", "--quiet", repo_root, "HEAD")
      runner.run!("git", "-C", tap_path, "checkout", "--quiet", "--detach", "FETCH_HEAD")
      begin
        yield
      ensure
        out.puts "Restoring #{tap_name} tap checkout..."
        if restore_branch.empty?
          runner.run!("git", "-C", tap_path, "checkout", "--quiet", "--detach", tap_head)
        else
          runner.run!("git", "-C", tap_path, "checkout", "--quiet", restore_branch)
        end
      end
    end
  end
end
