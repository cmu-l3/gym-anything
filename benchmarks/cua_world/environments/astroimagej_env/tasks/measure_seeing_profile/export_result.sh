#!/bin/bash
set -euo pipefail

echo "=== Exporting measure_seeing_profile results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
MEASUREMENTS_DIR="/home/ga/AstroImages/measurements"

# Check Application State
APP_RUNNING="false"
if pgrep -f "AstroImageJ\|aij" > /dev/null; then
    APP_RUNNING="true"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Analyze the FITS file to get Ground Truth background stats using Python & Astropy
# This runs safely isolated within the container
echo "Calculating ground truth statistics..."
cat > /tmp/calc_ground_truth.py << 'EOF'
import json
import numpy as np
import sys
import warnings
from astropy.io import fits
from astropy.stats import sigma_clipped_stats

warnings.filterwarnings('ignore')

try:
    with fits.open('/home/ga/AstroImages/raw/Vcomb.fits') as hdul:
        data = hdul[0].data
        # Use sigma clipping to calculate true background without stars
        mean, median, std = sigma_clipped_stats(data, sigma=3.0, maxiters=5)
        result = {
            "success": True,
            "true_bkg_mean": float(mean),
            "true_bkg_median": float(median),
            "true_bkg_std": float(std)
        }
except Exception as e:
    result = {"success": False, "error": str(e)}

with open('/tmp/ground_truth.json', 'w') as f:
    json.dump(result, f)
EOF

python3 /tmp/calc_ground_truth.py 2>/dev/null || echo '{"success": false}' > /tmp/ground_truth.json

# Gather file existence and timestamp info
check_file() {
    local filepath="$1"
    if [ -f "$filepath" ]; then
        local mtime=$(stat -c %Y "$filepath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$filepath" 2>/dev/null || echo "0")
        local created_during="false"
        if [ "$mtime" -ge "$TASK_START" ]; then
            created_during="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

CSV_INFO=$(check_file "$MEASUREMENTS_DIR/background_stats.csv")
PNG_INFO=$(check_file "$MEASUREMENTS_DIR/seeing_profile.png")
TXT_INFO=$(check_file "$MEASUREMENTS_DIR/seeing_report.txt")

# Prepare export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "ground_truth": $(cat /tmp/ground_truth.json),
    "files": {
        "csv": $CSV_INFO,
        "png": $PNG_INFO,
        "txt": $TXT_INFO
    }
}
EOF

# Move to standard location and fix permissions
rm -f /tmp/task_result.json
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Copy measurement files to /tmp so verifier can easily retrieve them
cp "$MEASUREMENTS_DIR/background_stats.csv" /tmp/ 2>/dev/null || true
cp "$MEASUREMENTS_DIR/seeing_profile.png" /tmp/ 2>/dev/null || true
cp "$MEASUREMENTS_DIR/seeing_report.txt" /tmp/ 2>/dev/null || true
chmod 666 /tmp/background_stats.csv /tmp/seeing_profile.png /tmp/seeing_report.txt 2>/dev/null || true

echo "=== Export complete ==="