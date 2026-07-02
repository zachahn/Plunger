# Rakefile — Plunger release pipeline
#
# Ships a notarized, Sparkle-signed build and publishes it to GitHub Releases,
# then updates the raw-hosted appcast.xml on `main`.
#
# One-time notary setup (needed once before the first `rake release:notarize`):
#
#   rake notary_setup       # save a notarytool keychain profile (prompts for a password)
#
# Bump the version before a release:
#
#   rake bump VERSION=1.1   # set marketing version to 1.1 and increment the build number
#
# The steps are broken out so you can run them one at a time while learning the
# flow, or run `rake release` to do the whole thing:
#
#   rake release:preflight  # check tools, keys, and repo state before starting
#   rake release:archive    # archive (xcodebuild archive)
#   rake release:export     # export a Developer ID-signed .app (xcodebuild -exportArchive)
#   rake release:zip        # zip the .app
#   rake release:notarize   # notarize the zip and staple the ticket
#   rake release:appcast    # generate/update appcast.xml (EdDSA-signed) for this version
#   rake release:push       # commit and push the version bump + updated appcast.xml
#   rake release:github     # create the GitHub Release and upload the zip
#
# release:push pushes before release:github so the tag `gh release create` makes
# points at the commit that actually carries this version's appcast and bump.
#
#   rake release            # runs the seven steps above in order
#
# Each task is independently runnable and reads the version from the built
# product, so `rake release:notarize` works after `release:zip` in a later shell.
#
# Configuration lives in release.json (gitignored); every key is required, with
# no defaults. Override any value on the command line, e.g. `rake release
# NOTARY_PROFILE=foo`. The required keys:
#   PROJECT         e.g. Plunger.xcodeproj
#   SCHEME          e.g. Plunger
#   CONFIGURATION   e.g. Release
#   NOTARY_PROFILE  keychain profile saved via `xcrun notarytool store-credentials`
#   APPLE_ID        Apple ID email for notarization
#   TEAM_ID         10-char Apple Developer Team ID
#   GH_REPO         owner/name for gh + the appcast URL, e.g. zachahn/Plunger
#   APPCAST_BRANCH  branch that hosts appcast.xml via raw URL, e.g. main

require "shellwords"
require "fileutils"
require "json"

RELEASE_CONFIG =
  begin
    path = File.join(__dir__, "release.json")
    File.exist?(path) ? JSON.parse(File.read(path)) : {}
  end

def setting(key)
  ENV[key] || RELEASE_CONFIG[key] ||
    abort("missing #{key} — set it in release.json or pass #{key}=... on the command line")
end

PROJECT        = setting("PROJECT")
SCHEME         = setting("SCHEME")
CONFIGURATION  = setting("CONFIGURATION")
NOTARY_PROFILE = setting("NOTARY_PROFILE")
APPLE_ID       = setting("APPLE_ID")
TEAM_ID        = setting("TEAM_ID")
GH_REPO        = setting("GH_REPO")
APPCAST_BRANCH = setting("APPCAST_BRANCH")

ROOT       = __dir__
BUILD_DIR  = File.join(ROOT, "build")
ARCHIVE    = File.join(BUILD_DIR, "Plunger.xcarchive")
EXPORT_DIR = File.join(BUILD_DIR, "export")
APP        = File.join(EXPORT_DIR, "Plunger.app")
DIST_DIR   = File.join(BUILD_DIR, "dist") # holds the zip + appcast for generate_appcast
APPCAST    = File.join(ROOT, "appcast.xml")
PBXPROJ    = File.join(ROOT, PROJECT, "project.pbxproj")

# ---- helpers ---------------------------------------------------------------

# ANSI SGR color codes, named so the tasks below read as ok/warn/halt/step
# instead of raw \e[..m sequences.
GREEN  = 32 # success lines
YELLOW = 33 # caution lines
RED    = 31 # failure messages
CYAN   = 36 # step banners and echoed commands

# Wrap the string in an ANSI color and reset. One place for the escape codes.
class String
  def colorize(number) = "\e[#{number}m#{self}\e[0m"
end

def ok(text)   = puts "✓ #{text}".colorize(GREEN)  # green success line
def warn(text) = puts text.colorize(YELLOW)        # yellow caution line
def note(text) = puts "  #{text}"                  # plain, indented secondary hint
def halt(text) = abort text.colorize(RED)          # red message, then abort the run

# Print a cyan banner announcing the step about to run.
def step(text) = puts "\n▶ #{text}".colorize(CYAN)

# Run a command, echoing it first. Raises (aborting the rake run) on failure.
def sh!(*args)
  puts "$ #{args.map { |a| Shellwords.escape(a) }.join(" ")}".colorize(CYAN)
  system(*args) || halt("command failed: #{args.first}")
end

# Capture stdout of a command, aborting on failure.
def capture!(*args)
  out = IO.popen(args, &:read)
  halt("command failed: #{args.first}") unless $?.success?
  out
end

# Read a build-setting value from the exported .app's Info.plist.
def plist(key)
  halt("missing #{APP} — run `rake release:export` first") unless File.exist?(APP)
  capture!("/usr/libexec/PlistBuddy", "-c", "Print :#{key}", File.join(APP, "Contents", "Info.plist")).strip
end

def marketing_version = plist("CFBundleShortVersionString") # e.g. 1.1
def build_version     = plist("CFBundleVersion")            # e.g. 6  (Sparkle's sparkle:version)
def tag               = "v#{marketing_version}"
def zip_name          = "Plunger-#{marketing_version}.zip"
def zip_path          = File.join(DIST_DIR, zip_name)
def download_prefix   = "https://github.com/#{GH_REPO}/releases/download/#{tag}/"

# The newest Sparkle bin/ directory SPM unpacked, or nil if none exists yet.
def sparkle_bin_dir
  Dir.glob(File.expand_path(
    "~/Library/Developer/Xcode/DerivedData/**/artifacts/sparkle/Sparkle/bin"
  )).max_by { |p| File.mtime(p) }
end

def generate_appcast_bin
  dir = sparkle_bin_dir
  path = dir && File.join(dir, "generate_appcast")
  halt("generate_appcast not found — build the app once so SPM resolves Sparkle") unless path && File.exist?(path)
  path
end

def notary_profile_exists?
  # `notarytool history` succeeds only if the named keychain profile resolves.
  system("xcrun", "notarytool", "history", "--keychain-profile", NOTARY_PROFILE,
         out: File::NULL, err: File::NULL)
end

# ---- tasks -----------------------------------------------------------------

desc "One-time: save a notarytool keychain profile (prompts for an app-specific password)"
task :notary_setup do
  if notary_profile_exists?
    ok "notarytool profile \"#{NOTARY_PROFILE}\" already exists — nothing to do"
    next
  end

  puts "Creating notarytool profile \"#{NOTARY_PROFILE}\" for #{APPLE_ID} (team #{TEAM_ID})."
  puts "Generate an app-specific password at https://appleid.apple.com → Sign-In and Security."
  # Omitting --password makes notarytool prompt for it, so the secret is typed
  # straight into store-credentials and never passes through this task or the
  # shell history.
  sh! "xcrun", "notarytool", "store-credentials", NOTARY_PROFILE,
      "--apple-id", APPLE_ID,
      "--team-id", TEAM_ID
  ok "profile \"#{NOTARY_PROFILE}\" saved; `rake release:notarize` can now notarize"
end

desc "Bump the marketing version (VERSION=x.y) and increment the build number"
task :bump do
  version = ENV.fetch("VERSION")
  halt("set VERSION, e.g. `rake bump VERSION=1.1`") if version.to_s.strip.empty?
  halt("VERSION must look like 1.1 or 1.2.3, got #{version.inspect}") unless
    version =~ /\A\d+(\.\d+){1,2}\z/

  # GENERATE_INFOPLIST_FILE = YES means the built Info.plist takes its version
  # from these build settings, not from Plunger/Info.plist — so edit the
  # pbxproj directly, the same values Xcode's UI writes. agvtool doesn't fit:
  # it edits the source Info.plist (regenerated at build time) and trips over
  # the synchronized-folder layout.
  text = File.read(PBXPROJ)

  builds = text.scan(/CURRENT_PROJECT_VERSION = (\d+);/).flatten.map(&:to_i)
  halt("no CURRENT_PROJECT_VERSION found in pbxproj") if builds.empty?
  next_build = builds.max + 1

  # Every target shares one build number (Sparkle's sparkle:version), so set
  # them all to the same next value.
  text = text.gsub(/CURRENT_PROJECT_VERSION = \d+;/, "CURRENT_PROJECT_VERSION = #{next_build};")

  # Bump MARKETING_VERSION only for the app target, identified by its bundle id
  # (each MARKETING_VERSION line is immediately followed by the config's
  # PRODUCT_BUNDLE_IDENTIFIER). The test targets keep their own version. This
  # anchor works whatever the current value is, so re-bumping stays correct.
  app_marketing = /MARKETING_VERSION = [^;]+;(\s*PRODUCT_BUNDLE_IDENTIFIER = com\.zachahn\.Plunger;)/
  halt("no app MARKETING_VERSION line found in pbxproj") unless text.match?(app_marketing)
  text = text.gsub(app_marketing, "MARKETING_VERSION = #{version};\\1")

  File.write(PBXPROJ, text)
  ok "marketing version #{version}, build #{next_build}"
  note "review the pbxproj diff, then commit before releasing."
end

desc "Full release: preflight → archive → export → zip → notarize → appcast → push → GitHub"
task release: %w[
  release:preflight
  release:archive
  release:export
  release:zip
  release:notarize
  release:appcast
  release:push
  release:github
] do
  ok "release #{tag} complete"
end

namespace :release do
  desc "check that the tools, keys, and repo state a release needs are in place"
  task :preflight do
    step "preflight — checking the release environment"

    # Collect every problem, then report them together, so one `rake release`
    # surfaces all the fixes at once instead of failing on the first missing key.
    problems = []
    ask = ->(label, ok_cond) { ok_cond ? ok(label) : (problems << label) }

    # xcodebuild for archive/export.
    ask.("xcodebuild present",
         system("xcodebuild", "-version", out: File::NULL, err: File::NULL))

    # Sparkle tools (generate_appcast for the appcast, generate_keys to read the
    # EdDSA key) land in DerivedData once the app has built and SPM resolved.
    bin = sparkle_bin_dir
    ask.("Sparkle tools resolved (build the app once so SPM fetches Sparkle)",
         bin && File.exist?(File.join(bin, "generate_appcast")))

    # The appcast is signed with the EdDSA private key in the Keychain.
    # generate_keys -p prints the public key and exits 0 only if the key exists.
    keys = bin && File.join(bin, "generate_keys")
    ask.("Sparkle EdDSA signing key in Keychain (run `#{keys || "generate_keys"}` once)",
         keys && File.exist?(keys) &&
           system(keys, "-p", out: File::NULL, err: File::NULL))

    # notarytool keychain profile for the notarize step.
    ask.("notarytool profile \"#{NOTARY_PROFILE}\" saved (run `rake notary_setup`)",
         notary_profile_exists?)

    # gh authenticated for creating the GitHub release.
    ask.("gh authenticated (run `gh auth login`)",
         system("gh", "auth", "status", out: File::NULL, err: File::NULL))

    # The push step commits to APPCAST_BRANCH; make sure we're on it with a remote.
    branch = capture!("git", "rev-parse", "--abbrev-ref", "HEAD").strip
    ask.("on branch #{APPCAST_BRANCH} (currently #{branch})", branch == APPCAST_BRANCH)
    ask.("git remote origin configured",
         !capture!("git", "remote").split.empty?)

    # Managed Developer ID signing usually can't be listed on the CLI, so a
    # missing cert here is a heads-up, not a failure — the export may still work.
    unless system("sh", "-c",
                  "security find-identity -v -p codesigning | grep -q 'Developer ID Application'",
                  out: File::NULL, err: File::NULL)
      warn "  ⚠ no 'Developer ID Application' cert listed on the CLI — fine if Xcode manages signing, but export will fail if it truly can't sign"
    end

    halt("preflight found problems:\n  - #{problems.join("\n  - ")}") unless problems.empty?
    ok "preflight passed — the release environment looks ready"
  end

  desc "archive the app (xcodebuild archive)"
  task :archive do
    step "archiving the app"
    FileUtils.mkdir_p(BUILD_DIR)
    FileUtils.rm_rf(ARCHIVE)
    sh! "xcodebuild", "archive",
        "-project", PROJECT,
        "-scheme", SCHEME,
        "-configuration", CONFIGURATION,
        "-destination", "generic/platform=macOS",
        "-archivePath", ARCHIVE
    ok "archived → #{ARCHIVE}"
  end

  desc "export a Developer ID-signed .app from the archive"
  task :export do
    step "exporting a Developer ID-signed .app"
    halt("missing archive — run `rake release:archive` first") unless File.exist?(ARCHIVE)
    FileUtils.rm_rf(EXPORT_DIR)

    # method=developer-id reuses Xcode's managed Developer ID signing, so this
    # works even when `security find-identity` can't list the cert on the CLI.
    options = File.join(BUILD_DIR, "ExportOptions.plist")
    File.write(options, <<~PLIST)
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
          <key>method</key><string>developer-id</string>
          <key>signingStyle</key><string>automatic</string>
      </dict>
      </plist>
    PLIST

    sh! "xcodebuild", "-exportArchive",
        "-archivePath", ARCHIVE,
        "-exportPath", EXPORT_DIR,
        "-exportOptionsPlist", options
    halt("export did not produce #{APP}") unless File.exist?(APP)
    ok "exported → #{APP} (#{marketing_version}, build #{build_version})"
  end

  desc "zip the exported .app for distribution"
  task :zip do
    step "zipping the .app"
    halt("missing #{APP} — run `rake release:export` first") unless File.exist?(APP)
    FileUtils.mkdir_p(DIST_DIR)
    FileUtils.rm_f(zip_path)
    # ditto preserves the bundle's symlinks/metadata; Sparkle expects a clean zip.
    sh! "ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", APP, zip_path
    ok "zipped → #{zip_path}"
  end

  desc "notarize the zip with notarytool and staple the .app"
  task :notarize do
    step "notarizing and stapling"
    halt("missing #{zip_path} — run `rake release:zip` first") unless File.exist?(zip_path)

    unless notary_profile_exists?
      abort(<<~MSG)
        #{%(No notarytool keychain profile named "#{NOTARY_PROFILE}".).colorize(RED)}
        Create one once (interactive), then re-run:

          xcrun notarytool store-credentials "#{NOTARY_PROFILE}" \\
            --apple-id "<your Apple ID email>" \\
            --team-id "<your 10-char Team ID>" \\
            --password "<an app-specific password from appleid.apple.com>"

        Or override the name with NOTARY_PROFILE=<name>.
      MSG
    end

    sh! "xcrun", "notarytool", "submit", zip_path,
        "--keychain-profile", NOTARY_PROFILE, "--wait"
    # Staple the ticket onto the .app, then re-zip so the distributed zip carries it.
    sh! "xcrun", "stapler", "staple", APP
    sh! "xcrun", "stapler", "validate", APP
    FileUtils.rm_f(zip_path)
    sh! "ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", APP, zip_path
    ok "notarized + stapled; re-zipped → #{zip_path}"
  end

  desc "generate/update the EdDSA-signed appcast.xml for this version"
  task :appcast do
    step "generating the signed appcast.xml"
    halt("missing #{zip_path} — run earlier steps first") unless File.exist?(zip_path)

    # generate_appcast reads/writes an appcast in the archives directory, so seed
    # DIST_DIR with the current committed appcast, let it append this version's
    # item (signed with the private key from the Keychain), then copy it back.
    FileUtils.cp(APPCAST, File.join(DIST_DIR, "appcast.xml")) if File.exist?(APPCAST)

    sh! generate_appcast_bin,
        "--download-url-prefix", download_prefix,
        "-o", File.join(DIST_DIR, "appcast.xml"),
        DIST_DIR

    FileUtils.cp(File.join(DIST_DIR, "appcast.xml"), APPCAST)
    ok "appcast.xml updated for #{marketing_version} (build #{build_version})"
    note "enclosure URL prefix: #{download_prefix}"
  end

  desc "commit and push the version bump + updated appcast.xml"
  task :push do
    step "committing and pushing"
    # Commit the appcast (from release:appcast) together with any pending version
    # bump (from `rake bump`), so the tag release:github creates points at a
    # commit that carries both. Stage pbxproj too rather than leaving an
    # uncommitted bump out of the tagged commit.
    paths = [APPCAST, PBXPROJ].select do |p|
      !capture!("git", "status", "--porcelain", "--", p).strip.empty?
    end
    halt("no appcast.xml or version-bump changes to commit") if paths.empty?

    sh! "git", "add", *paths
    sh! "git", "commit", "-m", "Release #{tag}"
    sh! "git", "push", "origin", APPCAST_BRANCH
    ok "committed and pushed to #{APPCAST_BRANCH}"
    note "Sparkle feed: https://raw.githubusercontent.com/#{GH_REPO}/#{APPCAST_BRANCH}/appcast.xml"
  end

  desc "create the GitHub Release and upload the zip"
  task :github do
    step "publishing the GitHub release"
    halt("missing #{zip_path} — run earlier steps first") unless File.exist?(zip_path)

    # Reuse an existing release for this tag if present; otherwise create it.
    # release:push has already pushed, so a freshly created tag points at the
    # commit carrying this version's appcast and bump.
    exists = system("gh", "release", "view", tag, "--repo", GH_REPO,
                    out: File::NULL, err: File::NULL)
    if exists
      sh! "gh", "release", "upload", tag, zip_path, "--repo", GH_REPO, "--clobber"
    else
      sh! "gh", "release", "create", tag, zip_path,
          "--repo", GH_REPO,
          "--title", "Plunger #{marketing_version}",
          "--generate-notes"
    end
    ok "GitHub release #{tag} published with #{zip_name}"
  end
end
