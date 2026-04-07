#!/bin/bash
echo "=== Exporting candidate_processing_interview_dispatch Result ==="

source /workspace/scripts/task_utils.sh
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png
sleep 1

# 1. Query candidates from DB
SARAH_EXISTS=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e "SELECT COUNT(*) FROM main_candidates WHERE candidate_name LIKE '%Sarah%' OR first_name LIKE '%Sarah%';" 2>/dev/null || echo "0")
ELENA_EXISTS=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e "SELECT COUNT(*) FROM main_candidates WHERE candidate_name LIKE '%Elena%' OR first_name LIKE '%Elena%';" 2>/dev/null || echo "0")
MARCUS_EXISTS=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e "SELECT COUNT(*) FROM main_candidates WHERE candidate_name LIKE '%Marcus%' OR first_name LIKE '%Marcus%';" 2>/dev/null || echo "0")

# 2. Extract Candidate IDs
SARAH_ID=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e "SELECT id FROM main_candidates WHERE candidate_name LIKE '%Sarah%' OR first_name LIKE '%Sarah%' LIMIT 1;" 2>/dev/null || echo "")
ELENA_ID=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e "SELECT id FROM main_candidates WHERE candidate_name LIKE '%Elena%' OR first_name LIKE '%Elena%' LIMIT 1;" 2>/dev/null || echo "")
MARCUS_ID=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e "SELECT id FROM main_candidates WHERE candidate_name LIKE '%Marcus%' OR first_name LIKE '%Marcus%' LIMIT 1;" 2>/dev/null || echo "")

# 3. Query scheduled interviews linked to those IDs
SARAH_INT=0
ELENA_INT=0
MARCUS_INT=0

if [ -n "$SARAH_ID" ]; then
    SARAH_INT=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e "SELECT COUNT(*) FROM main_interviewschedule WHERE candidate_id='$SARAH_ID';" 2>/dev/null || echo "0")
fi
if [ -n "$ELENA_ID" ]; then
    ELENA_INT=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e "SELECT COUNT(*) FROM main_interviewschedule WHERE candidate_id='$ELENA_ID';" 2>/dev/null || echo "0")
fi
if [ -n "$MARCUS_ID" ]; then
    MARCUS_INT=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e "SELECT COUNT(*) FROM main_interviewschedule WHERE candidate_id='$MARCUS_ID';" 2>/dev/null || echo "0")
fi

# 4. Check for uploaded resumes (PDFs created in the Sentrifugo uploads dir since task start)
UPLOADED_PDFS=$(find /var/www/html/sentrifugo/public/uploads -name "*.pdf" -type f -newermt "@$TASK_START" 2>/dev/null | wc -l)
# Fallback broader search if they were placed elsewhere in Sentrifugo
if [ "$UPLOADED_PDFS" -eq 0 ]; then
    UPLOADED_PDFS=$(find /var/www/html/sentrifugo -name "*.pdf" -type f -newermt "@$TASK_START" 2>/dev/null | wc -l)
fi

# Create export JSON securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "candidates_exist": {
        "sarah": $SARAH_EXISTS,
        "elena": $ELENA_EXISTS,
        "marcus": $MARCUS_EXISTS
    },
    "interviews_scheduled": {
        "sarah": $SARAH_INT,
        "elena": $ELENA_INT,
        "marcus": $MARCUS_INT
    },
    "uploaded_pdfs": $UPLOADED_PDFS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Task result exported."
cat /tmp/task_result.json
echo "=== Export Complete ==="