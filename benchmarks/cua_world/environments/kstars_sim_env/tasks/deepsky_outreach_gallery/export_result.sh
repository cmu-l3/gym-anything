#!/bin/bash
echo "=== Exporting deepsky_outreach_gallery results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Count slew commands in INDI log since task start
SLEW_COUNT=$(awk '/=== TASK_START ===/{flag=1} flag && /EQUATORIAL_EOD_COORD/{count++} END{print count+0}' /tmp/indiserver.log 2>/dev/null)
if [ -z "$SLEW_COUNT" ]; then
    SLEW_COUNT=0
fi

# Collect FITS, PNG, and HTML info via Python
python3 - << PYEOF
import os
import json
import glob
import base64

base_dir = '/home/ga/Outreach'
targets = ['M42', 'M31', 'M1', 'M57', 'M51']
task_start = $TASK_START
slew_count = $SLEW_COUNT

results = {
    "task_start": task_start,
    "timestamp": $(date +%s),
    "slew_count": slew_count,
    "targets": {}
}

for t in targets:
    target_dir = os.path.join(base_dir, t)
    fits_count = 0
    
    # Check FITS files
    for ext in ['*.fits', '*.fit']:
        pattern = os.path.join(target_dir, ext)
        for f in glob.glob(pattern):
            try:
                st = os.stat(f)
                # Verify size and creation time
                if st.st_size > 1024 and st.st_mtime >= task_start:
                    fits_count += 1
            except Exception:
                pass
                
    # Check sky_view.png
    png_path = os.path.join(target_dir, 'sky_view.png')
    has_png = False
    try:
        if os.path.exists(png_path):
            st = os.stat(png_path)
            # Verify size (>50KB) to ensure it's not a dummy file
            if st.st_size > 50000 and st.st_mtime >= task_start:
                has_png = True
    except Exception:
        pass
        
    results["targets"][t] = {
        "fits_count": fits_count,
        "has_png": has_png
    }

# Check HTML Gallery
html_path = os.path.join(base_dir, 'gallery.html')
html_exists = False
html_b64 = ""

try:
    if os.path.exists(html_path):
        st = os.stat(html_path)
        if st.st_mtime >= task_start:
            html_exists = True
            with open(html_path, 'rb') as f:
                # Read up to 100KB to prevent memory issues with massive garbage files
                content = f.read(102400)
                html_b64 = base64.b64encode(content).decode('utf-8')
except Exception:
    pass

results["gallery"] = {
    "exists": html_exists,
    "content_b64": html_b64
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f, indent=2)
PYEOF

echo "Result written to /tmp/task_result.json"
echo "=== Export complete ==="