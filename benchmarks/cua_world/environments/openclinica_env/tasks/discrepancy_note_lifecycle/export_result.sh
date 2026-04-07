#!/bin/bash
echo "=== Exporting discrepancy_note_lifecycle result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")

DM101_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-101' AND study_id = $DM_STUDY_ID LIMIT 1")
DM102_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-102' AND study_id = $DM_STUDY_ID LIMIT 1")
DM103_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-103' AND study_id = $DM_STUDY_ID LIMIT 1")

# 1. Check Query on DM-101
DM101_NOTE_EXISTS="false"
DM101_NOTE_TYPE=""
DM101_NOTE_DESC=""

if [ -n "$DM101_SS_ID" ]; then
    # Look for a note linked to DM-101 that has "enrollment date" in description
    DM101_DATA=$(oc_query "SELECT dn.discrepancy_note_id, dn.discrepancy_note_type_id, dn.description 
                           FROM discrepancy_note dn 
                           JOIN dn_study_subject_map map ON dn.discrepancy_note_id = map.discrepancy_note_id 
                           WHERE map.study_subject_id = $DM101_SS_ID 
                           AND LOWER(dn.description) LIKE '%enrollment date%' 
                           ORDER BY dn.discrepancy_note_id DESC LIMIT 1")
    if [ -n "$DM101_DATA" ]; then
        DM101_NOTE_EXISTS="true"
        DM101_NOTE_TYPE=$(echo "$DM101_DATA" | cut -d'|' -f2)
        DM101_NOTE_DESC=$(echo "$DM101_DATA" | cut -d'|' -f3)
    else
        # Fallback check any note on DM-101
        DM101_DATA=$(oc_query "SELECT dn.discrepancy_note_id, dn.discrepancy_note_type_id, dn.description 
                               FROM discrepancy_note dn 
                               JOIN dn_study_subject_map map ON dn.discrepancy_note_id = map.discrepancy_note_id 
                               WHERE map.study_subject_id = $DM101_SS_ID 
                               ORDER BY dn.discrepancy_note_id DESC LIMIT 1")
        if [ -n "$DM101_DATA" ]; then
            DM101_NOTE_EXISTS="true"
            DM101_NOTE_TYPE=$(echo "$DM101_DATA" | cut -d'|' -f2)
            DM101_NOTE_DESC=$(echo "$DM101_DATA" | cut -d'|' -f3)
        fi
    fi
fi

# 2. Check Annotation on DM-102
DM102_NOTE_EXISTS="false"
DM102_NOTE_TYPE=""
DM102_NOTE_DESC=""

if [ -n "$DM102_SS_ID" ]; then
    DM102_DATA=$(oc_query "SELECT dn.discrepancy_note_id, dn.discrepancy_note_type_id, dn.description 
                           FROM discrepancy_note dn 
                           JOIN dn_study_subject_map map ON dn.discrepancy_note_id = map.discrepancy_note_id 
                           WHERE map.study_subject_id = $DM102_SS_ID 
                           AND LOWER(dn.description) LIKE '%informed consent%' 
                           ORDER BY dn.discrepancy_note_id DESC LIMIT 1")
    if [ -n "$DM102_DATA" ]; then
        DM102_NOTE_EXISTS="true"
        DM102_NOTE_TYPE=$(echo "$DM102_DATA" | cut -d'|' -f2)
        DM102_NOTE_DESC=$(echo "$DM102_DATA" | cut -d'|' -f3)
    else
        DM102_DATA=$(oc_query "SELECT dn.discrepancy_note_id, dn.discrepancy_note_type_id, dn.description 
                               FROM discrepancy_note dn 
                               JOIN dn_study_subject_map map ON dn.discrepancy_note_id = map.discrepancy_note_id 
                               WHERE map.study_subject_id = $DM102_SS_ID 
                               ORDER BY dn.discrepancy_note_id DESC LIMIT 1")
        if [ -n "$DM102_DATA" ]; then
            DM102_NOTE_EXISTS="true"
            DM102_NOTE_TYPE=$(echo "$DM102_DATA" | cut -d'|' -f2)
            DM102_NOTE_DESC=$(echo "$DM102_DATA" | cut -d'|' -f3)
        fi
    fi
fi

# 3. Check closed query on DM-103
DM103_QUERY_CLOSED="false"
DM103_RESOLUTION_STATUS=""
DM103_HAS_COMMENT="false"
DM103_COMMENT_TEXT=""

if [ -n "$DM103_SS_ID" ]; then
    # Find the pre-existing note (or its latest child)
    PARENT_DN_ID=$(oc_query "SELECT dn.discrepancy_note_id 
                             FROM discrepancy_note dn 
                             JOIN dn_study_subject_map map ON dn.discrepancy_note_id = map.discrepancy_note_id 
                             WHERE map.study_subject_id = $DM103_SS_ID 
                             AND dn.description LIKE 'Blood pressure value appears unusually high%' 
                             ORDER BY dn.discrepancy_note_id ASC LIMIT 1")
    
    if [ -n "$PARENT_DN_ID" ]; then
        DM103_RESOLUTION_STATUS=$(oc_query "SELECT resolution_status_id FROM discrepancy_note WHERE discrepancy_note_id = $PARENT_DN_ID")
        if [ "$DM103_RESOLUTION_STATUS" = "4" ]; then
            DM103_QUERY_CLOSED="true"
        fi
        
        # Look for a child note (which contains the comment)
        CHILD_DATA=$(oc_query "SELECT resolution_status_id, description, detailed_notes FROM discrepancy_note WHERE parent_dn_id = $PARENT_DN_ID ORDER BY discrepancy_note_id DESC LIMIT 1")
        if [ -n "$CHILD_DATA" ]; then
            CHILD_STATUS=$(echo "$CHILD_DATA" | cut -d'|' -f1)
            CHILD_DESC=$(echo "$CHILD_DATA" | cut -d'|' -f2)
            CHILD_DETAILED=$(echo "$CHILD_DATA" | cut -d'|' -f3)
            
            if [ "$CHILD_STATUS" = "4" ]; then
                DM103_QUERY_CLOSED="true"
                DM103_RESOLUTION_STATUS="4"
            fi
            
            if echo "$CHILD_DESC" | grep -qi "verified\|confirmed"; then
                DM103_HAS_COMMENT="true"
                DM103_COMMENT_TEXT="$CHILD_DESC"
            elif echo "$CHILD_DETAILED" | grep -qi "verified\|confirmed"; then
                DM103_HAS_COMMENT="true"
                DM103_COMMENT_TEXT="$CHILD_DETAILED"
            fi
        fi
        
        if [ "$DM103_HAS_COMMENT" = "false" ]; then
            PARENT_DESC=$(oc_query "SELECT description FROM discrepancy_note WHERE discrepancy_note_id = $PARENT_DN_ID")
            PARENT_DETAILED=$(oc_query "SELECT detailed_notes FROM discrepancy_note WHERE discrepancy_note_id = $PARENT_DN_ID")
            if echo "$PARENT_DESC" | grep -qi "verified\|confirmed"; then
                DM103_HAS_COMMENT="true"
                DM103_COMMENT_TEXT="$PARENT_DESC"
            elif echo "$PARENT_DETAILED" | grep -qi "verified\|confirmed"; then
                DM103_HAS_COMMENT="true"
                DM103_COMMENT_TEXT="$PARENT_DETAILED"
            fi
        fi
    fi
fi

# Audit log count
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count.txt 2>/dev/null || echo "0")
NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

TEMP_JSON=$(mktemp /tmp/discrepancy_note_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dm101_note_exists": $DM101_NOTE_EXISTS,
    "dm101_note_type": "$(json_escape "${DM101_NOTE_TYPE:-}")",
    "dm101_note_desc": "$(json_escape "${DM101_NOTE_DESC:-}")",
    "dm102_note_exists": $DM102_NOTE_EXISTS,
    "dm102_note_type": "$(json_escape "${DM102_NOTE_TYPE:-}")",
    "dm102_note_desc": "$(json_escape "${DM102_NOTE_DESC:-}")",
    "dm103_query_closed": $DM103_QUERY_CLOSED,
    "dm103_resolution_status": "$(json_escape "${DM103_RESOLUTION_STATUS:-}")",
    "dm103_has_comment": $DM103_HAS_COMMENT,
    "dm103_comment_text": "$(json_escape "${DM103_COMMENT_TEXT:-}")",
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$NONCE"
}
EOF

rm -f /tmp/discrepancy_note_result.json 2>/dev/null || sudo rm -f /tmp/discrepancy_note_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/discrepancy_note_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/discrepancy_note_result.json
chmod 666 /tmp/discrepancy_note_result.json 2>/dev/null || sudo chmod 666 /tmp/discrepancy_note_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="