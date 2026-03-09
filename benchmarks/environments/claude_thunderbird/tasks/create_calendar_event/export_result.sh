#!/bin/bash
set -euo pipefail

echo "=== Exporting Calendar Events ==="

# Give Thunderbird time to save
sleep 2

# Export directory
EXPORT_DIR="/home/ga/Documents/results"
sudo -u ga mkdir -p "$EXPORT_DIR"

# Copy calendar data directory
TB_PROFILE="/home/ga/.thunderbird/default"
CALENDAR_DIR="$TB_PROFILE/calendar-data"

if [ -d "$CALENDAR_DIR" ]; then
    # Copy all ICS files
    cp -r "$CALENDAR_DIR" "$EXPORT_DIR/calendar-data" 2>/dev/null || true
    echo "✅ Exported calendar data"

    # Count events
    EVENT_COUNT=$(find "$CALENDAR_DIR" -name "*.ics" 2>/dev/null | wc -l)
    echo "Found $EVENT_COUNT calendar files"
else
    echo "⚠️ Calendar data directory not found"
fi

echo "=== Export Complete ==="
