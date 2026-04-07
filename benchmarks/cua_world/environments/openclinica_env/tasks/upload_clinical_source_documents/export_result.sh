#!/bin/bash
echo "=== Exporting upload_clinical_source_documents result ==="

source /workspace/scripts/task_utils.sh

# Record end state
take_screenshot /tmp/task_final.png

# Query DB for DM-101
DM101_FILE=$(oc_query "SELECT id.value FROM item_data id JOIN item i ON id.item_id=i.item_id JOIN event_crf ec ON id.event_crf_id=ec.event_crf_id JOIN study_subject ss ON ec.study_subject_id=ss.study_subject_id WHERE ss.label='DM-101' AND i.name='FILE_ATTACH' AND ec.crf_version_id=99000 LIMIT 1")
DM101_DOC=$(oc_query "SELECT id.value FROM item_data id JOIN item i ON id.item_id=i.item_id JOIN event_crf ec ON id.event_crf_id=ec.event_crf_id JOIN study_subject ss ON ec.study_subject_id=ss.study_subject_id WHERE ss.label='DM-101' AND i.name='DOC_TYPE' AND ec.crf_version_id=99000 LIMIT 1")
DM101_COM=$(oc_query "SELECT id.value FROM item_data id JOIN item i ON id.item_id=i.item_id JOIN event_crf ec ON id.event_crf_id=ec.event_crf_id JOIN study_subject ss ON ec.study_subject_id=ss.study_subject_id WHERE ss.label='DM-101' AND i.name='COMMENTS' AND ec.crf_version_id=99000 LIMIT 1")
DM101_STATUS=$(oc_query "SELECT ec.status_id FROM event_crf ec JOIN study_subject ss ON ec.study_subject_id=ss.study_subject_id WHERE ss.label='DM-101' AND ec.crf_version_id=99000 LIMIT 1")

# Query DB for DM-102
DM102_FILE=$(oc_query "SELECT id.value FROM item_data id JOIN item i ON id.item_id=i.item_id JOIN event_crf ec ON id.event_crf_id=ec.event_crf_id JOIN study_subject ss ON ec.study_subject_id=ss.study_subject_id WHERE ss.label='DM-102' AND i.name='FILE_ATTACH' AND ec.crf_version_id=99000 LIMIT 1")
DM102_DOC=$(oc_query "SELECT id.value FROM item_data id JOIN item i ON id.item_id=i.item_id JOIN event_crf ec ON id.event_crf_id=ec.event_crf_id JOIN study_subject ss ON ec.study_subject_id=ss.study_subject_id WHERE ss.label='DM-102' AND i.name='DOC_TYPE' AND ec.crf_version_id=99000 LIMIT 1")
DM102_COM=$(oc_query "SELECT id.value FROM item_data id JOIN item i ON id.item_id=i.item_id JOIN event_crf ec ON id.event_crf_id=ec.event_crf_id JOIN study_subject ss ON ec.study_subject_id=ss.study_subject_id WHERE ss.label='DM-102' AND i.name='COMMENTS' AND ec.crf_version_id=99000 LIMIT 1")
DM102_STATUS=$(oc_query "SELECT ec.status_id FROM event_crf ec JOIN study_subject ss ON ec.study_subject_id=ss.study_subject_id WHERE ss.label='DM-102' AND ec.crf_version_id=99000 LIMIT 1")

# Check if physical files exist in Tomcat attached files dir
DM101_PHYSICAL_FOUND="false"
if [ -n "$DM101_FILE" ]; then
    FOUND=$(docker exec oc-app find /usr/local/tomcat/openclinica_data -name "*DM-101_ECG.pdf*" 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then
        DM101_PHYSICAL_FOUND="true"
    fi
fi

DM102_PHYSICAL_FOUND="false"
if [ -n "$DM102_FILE" ]; then
    FOUND=$(docker exec oc-app find /usr/local/tomcat/openclinica_data -name "*DM-102_LabReport.pdf*" 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then
        DM102_PHYSICAL_FOUND="true"
    fi
fi

# Compare Audit logs
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")

# Write to JSON
TEMP_JSON=$(mktemp /tmp/upload_docs_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dm101": {
        "file_value": "$(json_escape "${DM101_FILE:-}")",
        "doc_type": "$(json_escape "${DM101_DOC:-}")",
        "comments": "$(json_escape "${DM101_COM:-}")",
        "crf_status": "${DM101_STATUS:-0}",
        "physical_file_found": $DM101_PHYSICAL_FOUND
    },
    "dm102": {
        "file_value": "$(json_escape "${DM102_FILE:-}")",
        "doc_type": "$(json_escape "${DM102_DOC:-}")",
        "comments": "$(json_escape "${DM102_COM:-}")",
        "crf_status": "${DM102_STATUS:-0}",
        "physical_file_found": $DM102_PHYSICAL_FOUND
    },
    "audit_baseline": $AUDIT_BASELINE_COUNT,
    "audit_final": $AUDIT_LOG_COUNT
}
EOF

# Move securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export completed successfully."