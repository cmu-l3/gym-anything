#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Playback History Result ==="

# Check for CSV file at expected location
CSV_FILE="/home/ga/Documents/playback_history.csv"

if [ -f "$CSV_FILE" ]; then
    echo "✅ Playback history CSV found: $CSV_FILE"
    
    # Show file info
    ls -lh "$CSV_FILE"
    
    # Display first few lines
    echo "--- CSV Preview ---"
    head -10 "$CSV_FILE" || true
    echo "-------------------"
    
    # Copy to temp location for verification
    cp "$CSV_FILE" /tmp/vlc_history_export.csv
    echo "✅ CSV copied to /tmp for verification"
else
    echo "⚠️ CSV file not found at expected location: $CSV_FILE"
    
    # Check if file was created elsewhere in Documents
    FOUND_CSV=$(find /home/ga/Documents -name "*.csv" -type f -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$FOUND_CSV" ]; then
        echo "Found CSV file at: $FOUND_CSV"
        cp "$FOUND_CSV" /tmp/vlc_history_export.csv
        echo "✅ Alternative CSV copied to /tmp"
    else
        echo "❌ No CSV file found in Documents directory"
        
        # Create empty placeholder to avoid verification errors
        echo "filename,path,timestamp" > /tmp/vlc_history_export.csv
    fi
fi

# Close any running VLC instances
if is_vlc_running; then
    echo "Closing any running VLC instances..."
    kill_vlc ga
    sleep 1
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_history_export_completed.txt
echo "Playback history export task completed" >> /tmp/vlc_history_export_completed.txt
echo "CSV location: $CSV_FILE" >> /tmp/vlc_history_export_completed.txt

# Also copy VLC history source files for debugging
echo "Copying VLC history source files for debugging..."
if [ -f /home/ga/.local/share/vlc/ml.xspf ]; then
    cp /home/ga/.local/share/vlc/ml.xspf /tmp/vlc_ml_xspf_backup.xml 2>/dev/null || true
fi

if [ -f /home/ga/.config/vlc/vlc-qt-interface.conf ]; then
    cp /home/ga/.config/vlc/vlc-qt-interface.conf /tmp/vlc_qt_config_backup.conf 2>/dev/null || true
fi

echo "=== Export Complete ==="