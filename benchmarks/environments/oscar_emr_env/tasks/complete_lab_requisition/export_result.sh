#!/bin/bash
# Export script for Complete Lab Requisition task

echo "=== Exporting Lab Requisition Result ==="

source /workspace/scripts/task_utils.sh

# 1. Gather Context
PATIENT_ID=$(cat /tmp/task_patient_id 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_form_count 2>/dev/null || echo "0")

if [ -z "$PATIENT_ID" ]; then
    # Fallback lookup
    PATIENT_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Maria' AND last_name='Santos' LIMIT 1")
fi

# 2. Query for new forms
# We look for the most recent form for this patient
# The table 'formLabReq' is standard for the Ontario Lab Requisition in many OSCAR versions.
# We fetch specific columns that correspond to the task requirements.
# Note: Column names are based on standard OSCAR schema. If strict schema varies, we grab the whole row.

echo "Querying formLabReq for patient $PATIENT_ID..."

# Try to get the latest form ID
LATEST_FORM=$(oscar_query "SELECT ID FROM formLabReq WHERE demographic_no='$PATIENT_ID' ORDER BY ID DESC LIMIT 1" 2>/dev/null)

FORM_FOUND="false"
FORM_DATA="{}"

if [ -n "$LATEST_FORM" ]; then
    # Check if it's new (ID should be higher than what we might have seen, but simpler to check timestamp if available)
    # Often formLabReq has 'form_date' or similar. We'll rely on the count difference primarily.
    
    CURRENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM formLabReq WHERE demographic_no='$PATIENT_ID'" 2>/dev/null || echo "0")
    
    if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
        FORM_FOUND="true"
        echo "New form found (ID: $LATEST_FORM)"
        
        # Extract specific fields (1 = checked, 0 = unchecked usually)
        # Q_Glucose_Fasting, Q_HBA1C, Q_Lipid_Profile, Q_Creatinine
        # clin_info for notes
        
        RAW_DATA=$(oscar_query "SELECT Q_Glucose_Fasting, Q_HBA1C, Q_Lipid_Profile, Q_Creatinine, clin_info FROM formLabReq WHERE ID='$LATEST_FORM'" 2>/dev/null)
        
        # Parse result (tab separated)
        # Handle potential NULLs or empty strings
        if [ -n "$RAW_DATA" ]; then
             GLUCOSE=$(echo "$RAW_DATA" | cut -f1)
             HBA1C=$(echo "$RAW_DATA" | cut -f2)
             LIPID=$(echo "$RAW_DATA" | cut -f3)
             CREATININE=$(echo "$RAW_DATA" | cut -f4)
             NOTES=$(echo "$RAW_DATA" | cut -f5)
             
             # JSON encode the notes (basic escaping)
             NOTES_ESCAPED=$(echo "$NOTES" | sed 's/"/\\"/g' | sed 's/\t/ /g')
             
             FORM_DATA="{\"glucose\": \"$GLUCOSE\", \"hba1c\": \"$HBA1C\", \"lipid\": \"$LIPID\", \"creatinine\": \"$CREATININE\", \"notes\": \"$NOTES_ESCAPED\", \"form_id\": \"$LATEST_FORM\"}"
        fi
    else
        echo "No new form count increment detected in formLabReq."
    fi
else
    # Fallback check in generic 'form' table if formLabReq is empty/unused
    echo "Checking generic form table..."
    GENERIC_FORM=$(oscar_query "SELECT id, formName FROM form WHERE demographic_no='$PATIENT_ID' AND id > 0 ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$GENERIC_FORM" ]; then
        # Check if created recently (this is weaker verification but better than nothing)
        # We assume if the agent created a form, it's likely the right one if the name matches
        GENERIC_ID=$(echo "$GENERIC_FORM" | cut -f1)
        GENERIC_NAME=$(echo "$GENERIC_FORM" | cut -f2)
        
        CURRENT_GENERIC_COUNT=$(oscar_query "SELECT COUNT(*) FROM form WHERE demographic_no='$PATIENT_ID' AND formName LIKE '%Lab%'" 2>/dev/null || echo "0")
        
        if [ "$CURRENT_GENERIC_COUNT" -gt "$INITIAL_COUNT" ]; then
             FORM_FOUND="true_generic"
             FORM_DATA="{\"generic_id\": \"$GENERIC_ID\", \"form_name\": \"$GENERIC_NAME\", \"notes\": \"Generic form verification only\"}"
        fi
    fi
fi

# 3. Capture screenshots
take_screenshot /tmp/task_final.png

# 4. Save result
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START,
    "patient_id": "$PATIENT_ID",
    "form_found": "$FORM_FOUND",
    "form_data": $FORM_DATA,
    "initial_count": $INITIAL_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json