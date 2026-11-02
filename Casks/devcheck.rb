# Homebrew cask template — lives in a separate tap repo: iihao/homebrew-tap
# Usage after publishing:  brew install --cask iihao/tap/devcheck
cask "devcheck" do
  version "0.1.0"
  sha256 "REPLACE_WITH_ZIP_SHA256"

  url "https://github.com/iihao/devcheck/releases/download/v#{version}/DevCheck-#{version}.zip"
  name "DevCheck"
  desc "Menu bar port map: who is holding :3000, and which project it belongs to"
  homepage "https://github.com/iihao/devcheck"

  depends_on macos: :sonoma

  app "DevCheck.app"

  caveats <<~EOS
    DevCheck is ad-hoc signed (no Apple Developer ID yet), so macOS marks the
    download as quarantined and refuses to launch it. Clear the flag once:

      xattr -dr com.apple.quarantine /Applications/DevCheck.app
  EOS

  zap trash: [
    "~/Library/Preferences/local.devcheck.plist",
  ]
end
