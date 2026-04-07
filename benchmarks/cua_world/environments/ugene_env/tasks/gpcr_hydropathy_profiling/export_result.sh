#!/bin/bash
echo "=== Exporting GPCR Hydropathy Profiling Results ==="

TASK_START=$(cat /tmp/gpcr_hydropathy_profiling_start_ts 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/protein_properties/results"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/gpcr_hydropathy_profiling_end_screenshot.png 2>/dev/null || true

CSV_EXISTS="false"
CSV_SIZE="0"
TXT_EXISTS="false"
TXT_SIZE="0"
PNG_EXISTS="false"

# Check for expected CSV
if [ -f "${RESULTS_DIR}/hydropathy_profile.csv" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "${RESULTS_DIR}/hydropathy_profile.csv" 2>/dev/null || echo "0")
fi

# Check for expected report
if [ -f "${RESULTS_DIR}/tm_domains_report.txt" ]; then
    TXT_EXISTS="true"
    TXT_SIZE=$(stat -c%s "${RESULTS_DIR}/tm_domains_report.txt" 2>/dev/null || echo "0")
fi

# Check for expected screenshot
if [ -f "${RESULTS_DIR}/plot_screenshot.png" ]; then
    PNG_EXISTS="true"
fi

# Build result JSON for quick existence checks
cat > /tmp/gpcr_hydropathy_profiling_result.json << EOF
{
    "task_start_ts": ${TASK_START},
    "csv_exists": ${CSV_EXISTS},
    "csv_size_bytes": ${CSV_SIZE},
    "txt_exists": ${TXT_EXISTS},
    "txt_size_bytes": ${TXT_SIZE},
    "png_exists": ${PNG_EXISTS}
}
EOF

chmod 666 /tmp/gpcr_hydropathy_profiling_result.json 2>/dev/null || true

echo "Export complete. Result JSON:"
cat /tmp/gpcr_hydropathy_profiling_result.json