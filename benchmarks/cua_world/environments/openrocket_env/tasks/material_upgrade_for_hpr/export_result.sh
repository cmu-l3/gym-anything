#!/bin/bash
echo "=== Exporting material_upgrade_for_hpr result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/material_upgrade_final.png 2>/dev/null || true

UPGRADED_ORK="/home/ga/Documents/rockets/upgraded_rocket.ork"
REPORT_FILE="/home/ga/Documents/exports/material_upgrade_report.txt"

ork_exists="false"
report_exists="false"

# Check exact and alternative case/extensions
if [ -f "$UPGRADED_ORK" ]; then
    ork_exists="true"
else
    # Fallback to case-insensitive check in rockets directory
    ALT_ORK=$(find /home/ga/Documents/rockets -maxdepth 1 -iname "upgraded_rocket.ork" | head -n 1)
    if [ -n "$ALT_ORK" ]; then
        UPGRADED_ORK="$ALT_ORK"
        ork_exists="true"
    fi
fi

if [ -f "$REPORT_FILE" ]; then
    report_exists="true"
else
    # Fallback to case-insensitive or .md format
    ALT_REPORT=$(find /home/ga/Documents/exports -maxdepth 1 \( -iname "material_upgrade_report.txt" -o -iname "material_upgrade_report.md" \) | head -n 1)
    if [ -n "$ALT_REPORT" ]; then
        REPORT_FILE="$ALT_REPORT"
        report_exists="true"
    fi
fi

ork_mtime="0"
report_size=0

if [ "$ork_exists" = "true" ]; then
    ork_mtime=$(stat -c %Y "$UPGRADED_ORK" 2>/dev/null || echo "0")
    # Copy to standardized temp location for verifier
    cp "$UPGRADED_ORK" /tmp/agent_upgraded_rocket.ork 2>/dev/null || true
fi

if [ "$report_exists" = "true" ]; then
    report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    # Copy to standardized temp location for verifier
    cp "$REPORT_FILE" /tmp/agent_material_report.txt 2>/dev/null || true
fi

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_mtime\": $ork_mtime,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/material_upgrade_result.json

echo "=== Export complete ==="