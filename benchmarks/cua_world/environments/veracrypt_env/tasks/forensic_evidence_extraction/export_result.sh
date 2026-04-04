#!/bin/bash
# Note: No set -e to ensure we capture partial failures
echo "=== Exporting forensic_evidence_extraction results ==="

source /workspace/scripts/task_utils.sh

# Load Ground Truth
GT_COUNT=$(cat /var/lib/veracrypt_task/gt_file_count.txt 2>/dev/null || echo "0")
GT_HASHES="/var/lib/veracrypt_task/gt_hashes.txt"

# Initialize Result Variables
EVIDENCE_DIR_EXISTS="false"
EXTRACTED_COUNT=0
FILES_INTEGRITY="false"
MANIFEST_EXISTS="false"
MANIFEST_FORMAT="false"
MANIFEST_HASHES_CORRECT="false"
REPORT_EXISTS="false"
REPORT_CONTENT_SCORE=0
VOLUME_DISMOUNTED="false"
TIMESTAMP_VALID="true"

# 1. Check Evidence Directory
if [ -d "/home/ga/Evidence/extracted" ]; then
    EVIDENCE_DIR_EXISTS="true"
    EXTRACTED_COUNT=$(ls -1 /home/ga/Evidence/extracted/ 2>/dev/null | wc -l)
fi

# 2. Check File Integrity (Compare extracted files against GT hashes)
if [ "$EVIDENCE_DIR_EXISTS" = "true" ] && [ -f "$GT_HASHES" ]; then
    INTEGRITY_FAILURES=0
    # Check that every ground truth hash exists in the extracted directory
    while read -r line; do
        hash=$(echo "$line" | awk '{print $1}')
        filename=$(echo "$line" | awk '{print $2}')
        
        if [ -f "/home/ga/Evidence/extracted/$filename" ]; then
            actual_hash=$(sha256sum "/home/ga/Evidence/extracted/$filename" | awk '{print $1}')
            if [ "$actual_hash" != "$hash" ]; then
                INTEGRITY_FAILURES=$((INTEGRITY_FAILURES + 1))
            fi
        else
            INTEGRITY_FAILURES=$((INTEGRITY_FAILURES + 1))
        fi
    done < "$GT_HASHES"
    
    if [ "$INTEGRITY_FAILURES" -eq 0 ] && [ "$EXTRACTED_COUNT" -eq "$GT_COUNT" ]; then
        FILES_INTEGRITY="true"
    fi
fi

# 3. Check Manifest Existence and Format
MANIFEST="/home/ga/Evidence/manifest.sha256"
if [ -f "$MANIFEST" ]; then
    MANIFEST_EXISTS="true"
    # Check format: 64 hex chars, two spaces, filename
    # grep -E returns 0 if match found. We want to check if ALL lines match or if mostly correct.
    # Simple check: Does it look like sha256sum output?
    if grep -qE "^[a-f0-9]{64}  .+$" "$MANIFEST"; then
        MANIFEST_FORMAT="true"
    fi
    
    # 4. Check Manifest Content Accuracy
    # Verify the manifest against the actual files (if files exist)
    if [ "$EVIDENCE_DIR_EXISTS" = "true" ]; then
        cd /home/ga/Evidence/extracted
        if sha256sum -c "$MANIFEST" --status 2>/dev/null; then
            MANIFEST_HASHES_CORRECT="true"
        fi
        cd /
    fi
fi

# 5. Check Report
REPORT="/home/ga/Evidence/extraction_report.txt"
if [ -f "$REPORT" ]; then
    REPORT_EXISTS="true"
    # Check for required keywords
    grep -qi "Date:" "$REPORT" && REPORT_CONTENT_SCORE=$((REPORT_CONTENT_SCORE + 1))
    grep -qi "Source:" "$REPORT" && REPORT_CONTENT_SCORE=$((REPORT_CONTENT_SCORE + 1))
    grep -qi "Files:" "$REPORT" && REPORT_CONTENT_SCORE=$((REPORT_CONTENT_SCORE + 1))
    grep -qi "Size:" "$REPORT" && REPORT_CONTENT_SCORE=$((REPORT_CONTENT_SCORE + 1))
fi

# 6. Check Dismount State
if ! veracrypt --text --list 2>/dev/null | grep -q "data_volume.hc"; then
    VOLUME_DISMOUNTED="true"
fi

# 7. Anti-Gaming Timestamp Check
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
if [ "$EVIDENCE_DIR_EXISTS" = "true" ]; then
    DIR_MTIME=$(stat -c %Y /home/ga/Evidence/extracted 2>/dev/null || echo "0")
    if [ "$DIR_MTIME" -lt "$TASK_START" ]; then
        TIMESTAMP_VALID="false"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON Result
cat << EOF > /tmp/task_result.json
{
  "evidence_dir_exists": $EVIDENCE_DIR_EXISTS,
  "extracted_count": $EXTRACTED_COUNT,
  "expected_count": $GT_COUNT,
  "files_integrity": $FILES_INTEGRITY,
  "manifest_exists": $MANIFEST_EXISTS,
  "manifest_format_valid": $MANIFEST_FORMAT,
  "manifest_hashes_correct": $MANIFEST_HASHES_CORRECT,
  "report_exists": $REPORT_EXISTS,
  "report_content_score": $REPORT_CONTENT_SCORE,
  "volume_dismounted": $VOLUME_DISMOUNTED,
  "timestamp_valid": $TIMESTAMP_VALID
}
EOF

# Permission fix for copy_from_env
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json