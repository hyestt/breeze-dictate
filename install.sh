#!/bin/zsh
# 安裝 Breeze 語音輸入：環境、模型、App 外殼、開機啟動。可重複執行。
set -euo pipefail
DIR="${0:A:h}"
LABEL="com.breeze-dictate"
APP="$DIR/BreezeDictate.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
cd "$DIR"

[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo "需要 Apple Silicon 的 Mac"; exit 1; }
command -v uv >/dev/null || { echo "缺少 uv，請先執行：brew install uv"; exit 1; }
command -v clang >/dev/null || { echo "缺少編譯器，請先執行：xcode-select --install"; exit 1; }

echo "1/5 建立 Python 環境"
uv venv --python 3.12 .venv -q
uv pip install -q --python .venv/bin/python -r requirements.txt

echo "2/5 下載模型（約 1 GB）"
if [[ -z "${SKIP_MODEL:-}" ]]; then
  .venv/bin/python -c "from huggingface_hub import snapshot_download as d; d('MarkChen1214/Breeze-ASR-25-MLX-5bit', local_dir='model')"
fi

echo "3/5 建立 BreezeDictate.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
clang -O1 -DAPP_DIR="\"$DIR\"" -o "$APP/Contents/MacOS/BreezeDictate" launcher.c
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$LABEL</string>
<key>CFBundleName</key><string>BreezeDictate</string>
<key>CFBundleExecutable</key><string>BreezeDictate</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSMicrophoneUsageDescription</key><string>語音輸入需要使用麥克風</string>
</dict></plist>
PL
codesign --force --deep -s - "$APP"

echo "4/5 設定開機自動啟動"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL</string>
<key>ProgramArguments</key><array><string>$APP/Contents/MacOS/BreezeDictate</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>30</integer>
<key>StandardOutPath</key><string>$DIR/dictate.log</string>
<key>StandardErrorPath</key><string>$DIR/dictate.log</string>
</dict></plist>
PL

if [[ -z "${SKIP_LAUNCH:-}" ]]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
fi

echo "5/5 授權（需手動，約 2 分鐘）"
cat <<MSG

請到「系統設定 → 隱私權與安全性」，替 BreezeDictate.app 開啟：
  1. 輔助使用（Accessibility；新版叫 Device Control and Data Access）
  2. 輸入監控（Input Monitoring）
按左下 + 加入：$APP
（Finder 已幫你反白這個 App，直接拖進去即可。）
第一次錄音時，允許「麥克風」。
完成後執行：launchctl kickstart -k gui/$(id -u)/$LABEL

使用：按住右 Option（Windows 鍵盤的右 Alt）說話，放開後貼上。
MSG
if [[ -z "${SKIP_LAUNCH:-}" ]]; then
  open -R "$APP"
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
fi
