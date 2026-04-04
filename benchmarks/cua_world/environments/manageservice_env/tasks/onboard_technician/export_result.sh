#!/bin/bash
# Export script for "onboard_technician" task

echo "=== Exporting Onboard Technician results ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize variables
SKILL_FOUND="false"
TECH_FOUND="false"
LOGIN_FOUND="false"
COST_CORRECT="false"
LINK_FOUND="false"
ROLE_ASSIGNED="false"

# 1. Verify Skill Creation
SKILL_ID=$(sdp_db_exec "SELECT skillid FROM skill WHERE skillname = 'AWS Certified Solutions Architect'" | head -n 1)
if [ -n "$SKILL_ID" ] && [ "$SKILL_ID" != "0" ]; then
    SKILL_FOUND="true"
    echo "Found Skill ID: $SKILL_ID"
else
    echo "Skill not found in database."
fi

# 2. Verify Technician (User) Existence
# First check AaaUser for basic profile
USER_ID=$(sdp_db_exec "SELECT user_id FROM aaauser WHERE first_name = 'Elena' AND last_name = 'Rodriguez'" | head -n 1)

if [ -n "$USER_ID" ] && [ "$USER_ID" != "0" ]; then
    TECH_FOUND="true"
    echo "Found User ID: $USER_ID"

    # 3. Verify Login
    # Check AaaLogin linked to this user
    LOGIN_NAME=$(sdp_db_exec "SELECT name FROM aaalogin WHERE user_id = '$USER_ID'" | head -n 1)
    if [ "$LOGIN_NAME" == "elena.r" ]; then
        LOGIN_FOUND="true"
        echo "Login confirmed: $LOGIN_NAME"
    else
        echo "Login mismatch or missing. Found: '$LOGIN_NAME'"
    fi

    # 4. Verify Cost Per Hour (HelpDeskCrew table)
    # helpdeskcrew.technicianid is a FK to aaauser.user_id (or sduser.userid)
    COST_VAL=$(sdp_db_exec "SELECT costperhour FROM helpdeskcrew WHERE technicianid = '$USER_ID'" | head -n 1)
    # Remove trailing zeros/decimals for comparison or handle in python
    echo "Found Cost: $COST_VAL"
    # Basic bash check, robust check in python
    if [[ "$COST_VAL" == "85"* ]]; then
        COST_CORRECT="true"
    fi

    # 5. Verify Skill Association (TechnicianSkills table)
    if [ "$SKILL_FOUND" == "true" ]; then
        # Table might be technicianskills or technician_skills depending on version
        # We try standard name 'technicianskills' first
        LINK_COUNT=$(sdp_db_exec "SELECT count(*) FROM technicianskills WHERE technicianid = '$USER_ID' AND skillid = '$SKILL_ID'")
        if [ "$LINK_COUNT" -gt 0 ]; then
            LINK_FOUND="true"
            echo "Skill link found."
        else
            echo "Skill link not found in technicianskills."
        fi
    fi
    
    # 6. Verify Role
    # Check aaaauthorizedrole -> aaarole
    # We look for 'SDSiteAdmin' or 'SDAdmin'
    ROLE_COUNT=$(sdp_db_exec "SELECT count(*) FROM aaaauthorizedrole ar JOIN aaarole r ON ar.role_id = r.role_id WHERE ar.account_id IN (SELECT account_id FROM aaaaccount WHERE login_id IN (SELECT login_id FROM aaalogin WHERE user_id = '$USER_ID')) AND (r.name = 'SDSiteAdmin' OR r.name = 'SDAdmin')")
    if [ "$ROLE_COUNT" -gt 0 ]; then
        ROLE_ASSIGNED="true"
        echo "Admin role found."
    fi

else
    echo "Technician 'Elena Rodriguez' not found."
fi

# Prepare JSON Output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "skill_found": $SKILL_FOUND,
    "technician_found": $TECH_FOUND,
    "login_found": $LOGIN_FOUND,
    "login_name": "$LOGIN_NAME",
    "cost_value": "$COST_VAL",
    "skill_link_found": $LINK_FOUND,
    "role_assigned": $ROLE_ASSIGNED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json