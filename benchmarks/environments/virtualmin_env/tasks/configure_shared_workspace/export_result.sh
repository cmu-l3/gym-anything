#!/bin/bash
echo "=== Exporting configure_shared_workspace result ==="

# ---------------------------------------------------------
# GATHER SYSTEM STATE
# ---------------------------------------------------------

GROUP_NAME="creative_team"
DIR_PATH="/home/acmecorp/campaign_2026"
USERS=("jordan" "alex")

# 1. Check Group Existence
if getent group "$GROUP_NAME" >/dev/null; then
    GROUP_EXISTS="true"
else
    GROUP_EXISTS="false"
fi

# 2. Check Group Membership
MEMBERSHIP_CORRECT="true"
MISSING_MEMBERS=()
for user in "${USERS[@]}"; do
    # use id -nG to get list of group names for user
    if ! id -nG "$user" | grep -qw "$GROUP_NAME"; then
        MEMBERSHIP_CORRECT="false"
        MISSING_MEMBERS+=("$user")
    fi
done

# 3. Check Directory
if [ -d "$DIR_PATH" ]; then
    DIR_EXISTS="true"
    
    # Get ownership
    DIR_USER=$(stat -c "%U" "$DIR_PATH")
    DIR_GROUP=$(stat -c "%G" "$DIR_PATH")
    
    # Get Permissions
    # %a returns octal (e.g., 2770)
    DIR_PERM_OCTAL=$(stat -c "%a" "$DIR_PATH")
    # %A returns human readable (e.g., drwxrws---)
    DIR_PERM_HUMAN=$(stat -c "%A" "$DIR_PATH")
    
    # Check SetGID specifically
    # If the octal is 4 digits and starts with 2, or the human string has 's' in group execute
    if [[ "$DIR_PERM_OCTAL" =~ ^2...$ ]] || [[ "$DIR_PERM_HUMAN" == *"rws"* ]]; then
        SETGID_BIT_SET="true"
    else
        SETGID_BIT_SET="false"
    fi
    
else
    DIR_EXISTS="false"
    DIR_USER=""
    DIR_GROUP=""
    DIR_PERM_OCTAL=""
    SETGID_BIT_SET="false"
fi

# 4. Functional Test: Inheritance
# Create a file as 'jordan' inside the directory and see who owns it
INHERITANCE_WORKS="false"
TEST_FILE_CREATED="false"
TEST_FILE_GROUP=""

if [ "$DIR_EXISTS" = "true" ] && [ "$GROUP_EXISTS" = "true" ] && [ "$MEMBERSHIP_CORRECT" = "true" ]; then
    TEST_FILE="$DIR_PATH/verification_test_$(date +%s).txt"
    
    # Switch to jordan and try to touch a file
    # We use 'su' or 'sudo'. Since script runs as root, easy.
    if sudo -u jordan touch "$TEST_FILE" 2>/dev/null; then
        TEST_FILE_CREATED="true"
        TEST_FILE_GROUP=$(stat -c "%G" "$TEST_FILE")
        
        # Check if the file belongs to 'creative_team' (Success) or 'jordan' (Fail/Default)
        if [ "$TEST_FILE_GROUP" == "$GROUP_NAME" ]; then
            INHERITANCE_WORKS="true"
        fi
        
        # Cleanup
        rm -f "$TEST_FILE"
    fi
fi

# 5. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 6. Create JSON Report
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "group_exists": $GROUP_EXISTS,
    "group_name": "$GROUP_NAME",
    "membership_correct": $MEMBERSHIP_CORRECT,
    "missing_members": $(printf '%s\n' "${MISSING_MEMBERS[@]}" | jq -R . | jq -s .),
    "directory_exists": $DIR_EXISTS,
    "directory_path": "$DIR_PATH",
    "directory_owner_user": "$DIR_USER",
    "directory_owner_group": "$DIR_GROUP",
    "directory_perm_octal": "$DIR_PERM_OCTAL",
    "setgid_bit_set": $SETGID_BIT_SET,
    "inheritance_functional_test": $INHERITANCE_WORKS,
    "test_file_created": $TEST_FILE_CREATED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json