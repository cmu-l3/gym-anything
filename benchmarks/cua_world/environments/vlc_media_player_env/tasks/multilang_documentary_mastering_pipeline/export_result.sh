#!/bin/bash
echo "=== Exporting multilang_documentary_mastering_pipeline results ==="

# Collect task result information
RESULT_FILE="/tmp/task_result.json"
MASTERED_DIR="/home/ga/Videos/mastered"
REPORT="/home/ga/Documents/mastering_report.json"

# Check which deliverables exist
MASTER_EXISTS=$(test -f "$MASTERED_DIR/documentary_master.mkv" && echo true || echo false)
DIST_EN_EXISTS=$(test -f "$MASTERED_DIR/dist_english.mp4" && echo true || echo false)
DIST_ES_EXISTS=$(test -f "$MASTERED_DIR/dist_spanish.mp4" && echo true || echo false)
DIST_AUDIO_EXISTS=$(test -f "$MASTERED_DIR/dist_audio.m4a" && echo true || echo false)
PROOF_EXISTS=$(test -f "$MASTERED_DIR/qa_proof_sheet.png" && echo true || echo false)
REPORT_EXISTS=$(test -f "$REPORT" && echo true || echo false)

cat > "$RESULT_FILE" << JSONEOF
{
  "task_id": "multilang_documentary_mastering_pipeline@1",
  "deliverables": {
    "master_mkv": {"path": "$MASTERED_DIR/documentary_master.mkv", "exists": $MASTER_EXISTS},
    "dist_english": {"path": "$MASTERED_DIR/dist_english.mp4", "exists": $DIST_EN_EXISTS},
    "dist_spanish": {"path": "$MASTERED_DIR/dist_spanish.mp4", "exists": $DIST_ES_EXISTS},
    "dist_audio": {"path": "$MASTERED_DIR/dist_audio.m4a", "exists": $DIST_AUDIO_EXISTS},
    "proof_sheet": {"path": "$MASTERED_DIR/qa_proof_sheet.png", "exists": $PROOF_EXISTS},
    "report": {"path": "$REPORT", "exists": $REPORT_EXISTS}
  }
}
JSONEOF

echo "Result exported to $RESULT_FILE"
echo "=== Export complete ==="
