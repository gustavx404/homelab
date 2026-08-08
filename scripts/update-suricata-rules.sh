#!/usr/bin/env bash
set -euo pipefail

# Download Emerging Threats Open rules for Suricata
# Run this once to seed rules, then periodically (cron) to update.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
RULES_DIR="$ROOT_DIR/suricata/rules"

mkdir -p "$RULES_DIR"

echo "Downloading ET Open ruleset..."
docker run --rm \
  -v "$RULES_DIR":/rules:rw \
  jasonish/suricata:latest \
  suricata-update -o /rules --no-reload --no-test 2>&1

if [ -s "$RULES_DIR/suricata.rules" ]; then
  count=$(grep -c '^alert' "$RULES_DIR/suricata.rules" 2>/dev/null || echo 0)
  echo "Done. $count rules downloaded to $RULES_DIR/"
else
  echo "ERROR: Failed to download rules"
  exit 1
fi
