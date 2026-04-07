#!/bin/bash
echo "=== Exporting PDB Sequence Cross-Alignment Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
RESULTS_DIR="/home/ga/UGENE_Data/pdb_cross_alignment"
EXPORT_DIR="/tmp/ugene_exports"

mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR"/*

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper to check file and record metadata
check_file() {
    local filename="$1"
    local filepath="${RESULTS_DIR}/${filename}"
    local exportpath="${EXPORT_DIR}/${filename}"
    local exists="false"
    local mtime="0"
    local size="0"

    if [ -f "$filepath" ]; then
        exists="true"
        mtime=$(stat -c %Y "$filepath" 2>/dev/null || echo "0")
        size=$(stat -c %s "$filepath" 2>/dev/null || echo "0")
        # Copy to export directory with relaxed permissions so verifier can easily read it
        cp "$filepath" "$exportpath" 2>/dev/null || sudo cp "$filepath" "$exportpath"
        chmod 666 "$exportpath" 2>/dev/null || sudo chmod 666 "$exportpath" 2>/dev/null || true
    fi

    echo "{\"exists\": $exists, \"mtime\": $mtime, \"size\": $size}"
}

# Check all expected files
PDB_FASTA=$(check_file "pdb_beta_chain.fasta")
COMBINED_FASTA=$(check_file "combined_sequences.fasta")
ALN_FILE=$(check_file "cross_species_alignment.aln")
ALN_FASTA=$(check_file "cross_species_alignment.fasta")
REPORT_FILE=$(check_file "verification_report.txt")

# Check if UGENE was running
APP_RUNNING="false"
if pgrep -f "ugene" > /dev/null; then
    APP_RUNNING="true"
fi

# Generate JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "files": {
        "pdb_beta_chain.fasta": $PDB_FASTA,
        "combined_sequences.fasta": $COMBINED_FASTA,
        "cross_species_alignment.aln": $ALN_FILE,
        "cross_species_alignment.fasta": $ALN_FASTA,
        "verification_report.txt": $REPORT_FILE
    }
}
EOF

# Move JSON to accessible location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json and /tmp/ugene_exports/"
echo "=== Export complete ==="