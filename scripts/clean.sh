#!/usr/bin/env bash
set -euo pipefail

echo "🧹 FastSwitch cleanup starting..."

# Kill running app
if pgrep -f "FastSwitch" >/dev/null 2>&1; then
  echo "🔪 Killing running FastSwitch..."
  pkill -f FastSwitch || true
fi

# Bundle identifiers to clear (legacy + current)
BUNDLE_IDS=(
  "com.bandonea.FastSwitch"
  "Bandonea.FastSwitch"
)

for BID in "${BUNDLE_IDS[@]}"; do
  echo "🧼 Clearing UserDefaults for $BID (best-effort)"
  defaults delete "$BID" 2>/dev/null || true
  defaults delete "$BID" FastSwitchUsageHistory 2>/dev/null || true
  defaults delete "$BID" MateReductionPlan 2>/dev/null || true

  echo "🔐 Resetting TCC permissions for $BID"
  tccutil reset Accessibility "$BID" 2>/dev/null || true
  tccutil reset AppleEvents   "$BID" 2>/dev/null || true
done

# Remove local temp/log files (repo workspace)
echo "🗑 Removing temp files in repo"
rm -f "$(git rev-parse --show-toplevel 2>/dev/null || pwd)/phrases.json.backup" 2>/dev/null || true
rm -f "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"/*.log 2>/dev/null || true

echo "✅ Cleanup complete. You may need to re-grant Accessibility, Automation, and Notifications on next run."
