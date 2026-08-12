cask "loopbar" do
  version "1.0.0"
  sha256 "5f2f86ff55a4e18dc6a486956833bcccd01b299a9f7fa6d85a115234905cb999"

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
