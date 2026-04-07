#!/bin/bash
echo "=== Exporting create_kb_article results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read setup metrics
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_KB_COUNT=$(cat /tmp/initial_kb_count.txt 2>/dev/null || echo "0")

# Get current counts
CURRENT_KB_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM aok_knowledgebase WHERE deleted=0" 2>/dev/null | tr -d '[:space:]')
if [ -z "$CURRENT_KB_COUNT" ]; then
    CURRENT_KB_COUNT="0"
fi

TARGET_NAME="Resolving Payment Gateway Timeout Errors (Code PG-408)"

# Extract article data (status, revision, creation time)
ARTICLE_DATA=$(suitecrm_db_query "SELECT id, status, revision, UNIX_TIMESTAMP(date_entered) FROM aok_knowledgebase WHERE name='${TARGET_NAME}' AND deleted=0 ORDER BY date_entered DESC LIMIT 1" 2>/dev/null)

ARTICLE_FOUND="false"
HAS_MERIDIAN="false"
HAS_PG408="false"
HAS_API_TIMEOUT="false"

if [ -n "$ARTICLE_DATA" ]; then
    ARTICLE_FOUND="true"
    A_ID=$(echo "$ARTICLE_DATA" | awk -F'\t' '{print $1}')
    A_STATUS=$(echo "$ARTICLE_DATA" | awk -F'\t' '{print $2}')
    A_REVISION=$(echo "$ARTICLE_DATA" | awk -F'\t' '{print $3}')
    A_DATE=$(echo "$ARTICLE_DATA" | awk -F'\t' '{print $4}')

    # Validate rich text content natively in DB to prevent parsing errors
    PHRASE_1=$(suitecrm_db_query "SELECT COUNT(*) FROM aok_knowledgebase WHERE id='${A_ID}' AND description LIKE '%Meridian payment gateway%'" | tr -d '[:space:]')
    PHRASE_2=$(suitecrm_db_query "SELECT COUNT(*) FROM aok_knowledgebase WHERE id='${A_ID}' AND description LIKE '%PG-408%'" | tr -d '[:space:]')
    PHRASE_3=$(suitecrm_db_query "SELECT COUNT(*) FROM aok_knowledgebase WHERE id='${A_ID}' AND LOWER(description) LIKE '%api timeout%'" | tr -d '[:space:]')

    if [ "$PHRASE_1" = "1" ]; then HAS_MERIDIAN="true"; fi
    if [ "$PHRASE_2" = "1" ]; then HAS_PG408="true"; fi
    if [ "$PHRASE_3" = "1" ]; then HAS_API_TIMEOUT="true"; fi
fi

# Construct Result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "article_found": ${ARTICLE_FOUND},
  "article_id": "$(json_escape "${A_ID:-}")",
  "status": "$(json_escape "${A_STATUS:-}")",
  "revision": "$(json_escape "${A_REVISION:-}")",
  "date_entered_ts": ${A_DATE:-0},
  "has_meridian": ${HAS_MERIDIAN},
  "has_pg408": ${HAS_PG408},
  "has_api_timeout": ${HAS_API_TIMEOUT},
  "initial_count": ${INITIAL_KB_COUNT:-0},
  "current_count": ${CURRENT_KB_COUNT:-0},
  "task_start_ts": ${TASK_START:-0}
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== create_kb_article export complete ==="