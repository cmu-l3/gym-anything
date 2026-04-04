#!/bin/bash
echo "=== Exporting connect_experiment_tasks result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

INITIAL_CONN_COUNT=$(cat /tmp/initial_connection_count 2>/dev/null || echo "0")
EXPERIMENT_ID=$(cat /tmp/experiment_id 2>/dev/null || echo "")

# If experiment_id isn't cached, look it up
if [ -z "$EXPERIMENT_ID" ]; then
    EXPERIMENT_ID=$(scinote_db_query "SELECT e.id FROM experiments e JOIN projects p ON e.project_id = p.id WHERE e.name='DNA Sequencing Pipeline' AND p.name='Genomics Study' LIMIT 1;" | tr -d '[:space:]')
fi

# Guard: if we still don't have an experiment ID, write a minimal valid JSON and exit
if [ -z "$EXPERIMENT_ID" ]; then
    RESULT_JSON='{"experiment_id":"","task_ids":{"sample_collection":"","dna_extraction":"","pcr_amplification":""},"initial_connection_count":0,"current_connection_count":0,"connection_1_to_2":false,"connection_2_to_3":false,"all_connections":[],"export_timestamp":"'"$(date -Iseconds)"'"}'
    safe_write_json "/tmp/connect_tasks_result.json" "$RESULT_JSON"
    echo "No experiment found. Result saved."
    exit 0
fi

# Get task IDs
TASK1_ID=$(scinote_db_query "SELECT id FROM my_modules WHERE name='Sample Collection' AND experiment_id=${EXPERIMENT_ID} LIMIT 1;" | tr -d '[:space:]')
TASK2_ID=$(scinote_db_query "SELECT id FROM my_modules WHERE name='DNA Extraction' AND experiment_id=${EXPERIMENT_ID} LIMIT 1;" | tr -d '[:space:]')
TASK3_ID=$(scinote_db_query "SELECT id FROM my_modules WHERE name='PCR Amplification' AND experiment_id=${EXPERIMENT_ID} LIMIT 1;" | tr -d '[:space:]')

# Count connections for this experiment using a dedicated COUNT query (not grep)
CURRENT_CONN_COUNT=$(scinote_db_query "SELECT COUNT(DISTINCT c.id) FROM connections c JOIN my_modules mm ON (c.output_id = mm.id OR c.input_id = mm.id) WHERE mm.experiment_id=${EXPERIMENT_ID};" | tr -d '[:space:]')
CURRENT_CONN_COUNT=${CURRENT_CONN_COUNT:-0}

# Check specific expected connections using dedicated boolean queries
CONN_1_2="false"
CONN_2_3="false"

if [ -n "$TASK1_ID" ] && [ -n "$TASK2_ID" ]; then
    HAS_CONN_1_2=$(scinote_db_query "SELECT COUNT(*) FROM connections WHERE output_id=${TASK1_ID} AND input_id=${TASK2_ID};" | tr -d '[:space:]')
    if [ "${HAS_CONN_1_2:-0}" -gt 0 ] 2>/dev/null; then
        CONN_1_2="true"
    fi
fi

if [ -n "$TASK2_ID" ] && [ -n "$TASK3_ID" ]; then
    HAS_CONN_2_3=$(scinote_db_query "SELECT COUNT(*) FROM connections WHERE output_id=${TASK2_ID} AND input_id=${TASK3_ID};" | tr -d '[:space:]')
    if [ "${HAS_CONN_2_3:-0}" -gt 0 ] 2>/dev/null; then
        CONN_2_3="true"
    fi
fi

# Build connections JSON array using individual queries per connection
# This avoids multi-column pipe-delimited parsing that can produce malformed JSON
CONN_JSON="[]"
CONN_IDS=$(scinote_db_query "SELECT c.id FROM connections c JOIN my_modules mm ON (c.output_id = mm.id OR c.input_id = mm.id) WHERE mm.experiment_id=${EXPERIMENT_ID} GROUP BY c.id ORDER BY c.id;")

if [ -n "$CONN_IDS" ]; then
    CONN_JSON="["
    CONN_FIRST=true
    while IFS= read -r conn_id; do
        conn_id_clean=$(echo "$conn_id" | tr -d '[:space:]')
        [ -z "$conn_id_clean" ] && continue

        FROM_NAME=$(scinote_db_query "SELECT mm.name FROM connections c JOIN my_modules mm ON c.output_id = mm.id WHERE c.id=${conn_id_clean};" | tr -d '\n' | sed 's/"/\\"/g; s/[[:space:]]*$//')
        TO_NAME=$(scinote_db_query "SELECT mm.name FROM connections c JOIN my_modules mm ON c.input_id = mm.id WHERE c.id=${conn_id_clean};" | tr -d '\n' | sed 's/"/\\"/g; s/[[:space:]]*$//')

        [ -z "$FROM_NAME" ] && continue
        [ -z "$TO_NAME" ] && continue

        if [ "$CONN_FIRST" = true ]; then
            CONN_FIRST=false
        else
            CONN_JSON="${CONN_JSON},"
        fi
        CONN_JSON="${CONN_JSON}{\"from\":\"${FROM_NAME}\",\"to\":\"${TO_NAME}\"}"
    done <<< "$CONN_IDS"
    CONN_JSON="${CONN_JSON}]"
fi

# Write result JSON using printf to avoid heredoc interpolation issues
printf '{\n' > /tmp/connect_tasks_result_tmp.json
printf '    "experiment_id": "%s",\n' "$EXPERIMENT_ID" >> /tmp/connect_tasks_result_tmp.json
printf '    "task_ids": {\n' >> /tmp/connect_tasks_result_tmp.json
printf '        "sample_collection": "%s",\n' "$TASK1_ID" >> /tmp/connect_tasks_result_tmp.json
printf '        "dna_extraction": "%s",\n' "$TASK2_ID" >> /tmp/connect_tasks_result_tmp.json
printf '        "pcr_amplification": "%s"\n' "$TASK3_ID" >> /tmp/connect_tasks_result_tmp.json
printf '    },\n' >> /tmp/connect_tasks_result_tmp.json
printf '    "initial_connection_count": %s,\n' "${INITIAL_CONN_COUNT:-0}" >> /tmp/connect_tasks_result_tmp.json
printf '    "current_connection_count": %s,\n' "${CURRENT_CONN_COUNT}" >> /tmp/connect_tasks_result_tmp.json
printf '    "connection_1_to_2": %s,\n' "${CONN_1_2}" >> /tmp/connect_tasks_result_tmp.json
printf '    "connection_2_to_3": %s,\n' "${CONN_2_3}" >> /tmp/connect_tasks_result_tmp.json
printf '    "all_connections": %s,\n' "${CONN_JSON}" >> /tmp/connect_tasks_result_tmp.json
printf '    "export_timestamp": "%s"\n' "$(date -Iseconds)" >> /tmp/connect_tasks_result_tmp.json
printf '}\n' >> /tmp/connect_tasks_result_tmp.json

# Validate JSON before saving (python fallback if jq not available)
if command -v python3 > /dev/null 2>&1; then
    if python3 -c "import json; json.load(open('/tmp/connect_tasks_result_tmp.json'))" 2>/dev/null; then
        safe_write_json "/tmp/connect_tasks_result.json" "$(cat /tmp/connect_tasks_result_tmp.json)"
    else
        echo "WARNING: Generated JSON is invalid, writing fallback"
        FALLBACK='{"experiment_id":"'"${EXPERIMENT_ID}"'","task_ids":{"sample_collection":"'"${TASK1_ID}"'","dna_extraction":"'"${TASK2_ID}"'","pcr_amplification":"'"${TASK3_ID}"'"},"initial_connection_count":'"${INITIAL_CONN_COUNT:-0}"',"current_connection_count":'"${CURRENT_CONN_COUNT}"',"connection_1_to_2":'"${CONN_1_2}"',"connection_2_to_3":'"${CONN_2_3}"',"all_connections":[],"export_timestamp":"'"$(date -Iseconds)"'"}'
        safe_write_json "/tmp/connect_tasks_result.json" "$FALLBACK"
    fi
else
    safe_write_json "/tmp/connect_tasks_result.json" "$(cat /tmp/connect_tasks_result_tmp.json)"
fi

rm -f /tmp/connect_tasks_result_tmp.json

echo "Result saved to /tmp/connect_tasks_result.json"
cat /tmp/connect_tasks_result.json
echo "=== Export complete ==="
