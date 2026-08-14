cask "loopbar" do
  version "1.0.1"
  sha256 "aedb9d8c10f1d7bd122d2195f3e3fefefb12115666abcefcfed21aa20735fa20"

  url "https://github.com/tohel17/LoopBar/releases/download/#{version}/LoopBar-#{version}.dmg",
      verified: "github.com/tohel17/LoopBar/"
  name "LoopBar"
  desc "Status island for monitoring Cursor, Codex, and Claude Code agents"
  homepage "https://github.com/tohel17/LoopBar"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "LoopBar.app"

  zap trash: [
    "~/Library/Caches/com.loopbar.app",
    "~/Library/Preferences/com.loopbar.app.plist",
    "~/Library/Saved Application State/com.loopbar.app.savedState",
  ]
end
