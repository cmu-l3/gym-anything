#!/bin/bash
echo "=== Exporting lookup_ncic_name result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

INITIAL_CITATION_COUNT=$(cat /tmp/initial_citation_count 2>/dev/null || echo "0")
INITIAL_TOTAL_CITATION_COUNT=$(cat /tmp/initial_total_citation_count 2>/dev/null || echo "0")

# Read baseline max ID to filter out pre-existing seed data
BASELINE_MAX_CITATION=$(cat /tmp/baseline_max_citation_id 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_MAX_CITATION=${BASELINE_MAX_CITATION:-0}

# Current citation counts
CURRENT_TREVOR_CITATIONS=$(opencad_db_query "SELECT COUNT(*) FROM ncic_citations WHERE name_id=3")
CURRENT_TOTAL_CITATIONS=$(opencad_db_query "SELECT COUNT(*) FROM ncic_citations")

# Search for the new citation - only consider records NEWER than baseline
CITATION_FOUND="false"
CITATION_ID=""
CITATION_NAME=""
CITATION_FINE=""
CITATION_DATE=""

# Search for reckless driving citation for Trevor (only new records)
CITATION_ID=$(opencad_db_query "SELECT id FROM ncic_citations WHERE name_id=3 AND LOWER(citation_name) LIKE '%reckless%' AND id > ${BASELINE_MAX_CITATION} ORDER BY id DESC LIMIT 1")

if [ -z "$CITATION_ID" ]; then
    # Broader search - any new citation for Trevor after baseline
    CITATION_ID=$(opencad_db_query "SELECT id FROM ncic_citations WHERE name_id=3 AND id > ${BASELINE_MAX_CITATION} ORDER BY id DESC LIMIT 1")
fi

if [ -z "$CITATION_ID" ]; then
    # Search any new citation with reckless driving after baseline
    CITATION_ID=$(opencad_db_query "SELECT id FROM ncic_citations WHERE LOWER(citation_name) LIKE '%reckless%' AND id > ${BASELINE_MAX_CITATION} ORDER BY id DESC LIMIT 1")
fi

if [ -n "$CITATION_ID" ]; then
    CITATION_FOUND="true"
    CITATION_NAME=$(opencad_db_query "SELECT citation_name FROM ncic_citations WHERE id=${CITATION_ID}")
    CITATION_FINE=$(opencad_db_query "SELECT citation_fine FROM ncic_citations WHERE id=${CITATION_ID}")
    CITATION_DATE=$(opencad_db_query "SELECT issued_date FROM ncic_citations WHERE id=${CITATION_ID}")
    CITATION_NAME_ID=$(opencad_db_query "SELECT name_id FROM ncic_citations WHERE id=${CITATION_ID}")
fi

# Check if NCIC lookup was performed (look for Trevor in ncic_names)
TREVOR_NCIC=$(opencad_db_query "SELECT COUNT(*) FROM ncic_names WHERE LOWER(name) LIKE '%trevor%philips%'")

RESULT_JSON=$(cat << EOF
{
    "initial_trevor_citation_count": ${INITIAL_CITATION_COUNT:-0},
    "current_trevor_citation_count": ${CURRENT_TREVOR_CITATIONS:-0},
    "initial_total_citation_count": ${INITIAL_TOTAL_CITATION_COUNT:-0},
    "current_total_citation_count": ${CURRENT_TOTAL_CITATIONS:-0},
    "trevor_ncic_records": ${TREVOR_NCIC:-0},
    "citation_found": ${CITATION_FOUND},
    "citation": {
        "id": "$(json_escape "${CITATION_ID}")",
        "name_id": "$(json_escape "${CITATION_NAME_ID}")",
        "citation_name": "$(json_escape "${CITATION_NAME}")",
        "fine": "$(json_escape "${CITATION_FINE}")",
        "date": "$(json_escape "${CITATION_DATE}")"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/lookup_ncic_name_result.json

echo "Result saved to /tmp/lookup_ncic_name_result.json"
cat /tmp/lookup_ncic_name_result.json
echo "=== Export complete ==="
