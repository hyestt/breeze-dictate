#!/bin/zsh
# 移除開機啟動。資料夾本身請自行刪除。
LABEL="com.breeze-dictate"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
echo "已移除。也可到系統設定把 BreezeDictate 從三個授權清單刪掉，並刪除本資料夾。"
