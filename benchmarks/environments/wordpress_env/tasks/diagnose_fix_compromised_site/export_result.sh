#!/bin/bash
# Export script for diagnose_fix_compromised_site task (post_task hook)
# Reads current WordPress settings and user state, compares to injected issues.

echo "=== Exporting diagnose_fix_compromised_site result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# ============================================================
# Read current state of all 7 settings
# ============================================================
CURRENT_BLOGNAME=$(wp_cli option get blogname)
CURRENT_BLOGDESC=$(wp_cli option get blogdescription)
CURRENT_PERMALINK=$(wp_cli option get permalink_structure)
CURRENT_COMMENT_MOD=$(wp_cli option get comment_moderation)
CURRENT_USERS_CAN_REG=$(wp_cli option get users_can_register)
CURRENT_DEFAULT_ROLE=$(wp_cli option get default_role)
CURRENT_TIMEZONE=$(wp_cli option get timezone_string)

# Check if rogue user still exists
ROGUE_USER_EXISTS="false"
cd /var/www/html/wordpress
if wp user get service_worker --field=ID --allow-root 2>/dev/null; then
    ROGUE_USER_EXISTS="true"
    echo "WARNING: Rogue user 'service_worker' still exists!"
else
    echo "Rogue user 'service_worker' has been removed"
fi

echo "Current state:"
echo "  blogname: $CURRENT_BLOGNAME"
echo "  blogdescription: $CURRENT_BLOGDESC"
echo "  permalink_structure: '$CURRENT_PERMALINK'"
echo "  comment_moderation: $CURRENT_COMMENT_MOD"
echo "  users_can_register: $CURRENT_USERS_CAN_REG"
echo "  default_role: $CURRENT_DEFAULT_ROLE"
echo "  timezone_string: $CURRENT_TIMEZONE"
echo "  rogue_user_exists: $ROGUE_USER_EXISTS"

# ============================================================
# Check each issue
# ============================================================

# Issue 1: Site title no longer spam
TITLE_FIXED="false"
TITLE_LOWER=$(echo "$CURRENT_BLOGNAME" | tr '[:upper:]' '[:lower:]')
if ! echo "$TITLE_LOWER" | grep -q "h4ck3d" && \
   ! echo "$TITLE_LOWER" | grep -q "ch3ap" && \
   ! echo "$TITLE_LOWER" | grep -q "m3ds"; then
    TITLE_FIXED="true"
fi

# Issue 2: Tagline no longer spam
TAGLINE_FIXED="false"
DESC_LOWER=$(echo "$CURRENT_BLOGDESC" | tr '[:upper:]' '[:lower:]')
if ! echo "$DESC_LOWER" | grep -q "pharmaceut1cals" && \
   ! echo "$DESC_LOWER" | grep -q "pr1ces" && \
   ! echo "$DESC_LOWER" | grep -q "v1sit"; then
    TAGLINE_FIXED="true"
fi

# Issue 3: Rogue user removed
ROGUE_USER_FIXED="false"
if [ "$ROGUE_USER_EXISTS" = "false" ]; then
    ROGUE_USER_FIXED="true"
fi

# Issue 4: Permalink structure not plain
PERMALINK_FIXED="false"
if [ -n "$CURRENT_PERMALINK" ] && [ "$CURRENT_PERMALINK" != "" ]; then
    PERMALINK_FIXED="true"
fi

# Issue 5: Comment moderation enabled
COMMENT_MOD_FIXED="false"
if [ "$CURRENT_COMMENT_MOD" = "1" ]; then
    COMMENT_MOD_FIXED="true"
fi

# Issue 6: Registration disabled or default role not admin
REGISTRATION_FIXED="false"
if [ "$CURRENT_USERS_CAN_REG" = "0" ]; then
    REGISTRATION_FIXED="true"
elif [ "$CURRENT_DEFAULT_ROLE" != "administrator" ]; then
    REGISTRATION_FIXED="true"
fi

# Issue 7: Timezone not UTC
TIMEZONE_FIXED="false"
if [ "$CURRENT_TIMEZONE" != "UTC" ] && [ -n "$CURRENT_TIMEZONE" ]; then
    TIMEZONE_FIXED="true"
fi

# Count fixed issues
FIXED_COUNT=0
for fixed in "$TITLE_FIXED" "$TAGLINE_FIXED" "$ROGUE_USER_FIXED" "$PERMALINK_FIXED" "$COMMENT_MOD_FIXED" "$REGISTRATION_FIXED" "$TIMEZONE_FIXED"; do
    if [ "$fixed" = "true" ]; then
        FIXED_COUNT=$((FIXED_COUNT + 1))
    fi
done

echo ""
echo "Issue remediation status ($FIXED_COUNT/7 fixed):"
echo "  title_fixed: $TITLE_FIXED"
echo "  tagline_fixed: $TAGLINE_FIXED"
echo "  rogue_user_fixed: $ROGUE_USER_FIXED"
echo "  permalink_fixed: $PERMALINK_FIXED"
echo "  comment_mod_fixed: $COMMENT_MOD_FIXED"
echo "  registration_fixed: $REGISTRATION_FIXED"
echo "  timezone_fixed: $TIMEZONE_FIXED"

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "current_state": {
        "blogname": "$(json_escape "$CURRENT_BLOGNAME")",
        "blogdescription": "$(json_escape "$CURRENT_BLOGDESC")",
        "permalink_structure": "$(json_escape "$CURRENT_PERMALINK")",
        "comment_moderation": "$CURRENT_COMMENT_MOD",
        "users_can_register": "$CURRENT_USERS_CAN_REG",
        "default_role": "$CURRENT_DEFAULT_ROLE",
        "timezone_string": "$CURRENT_TIMEZONE",
        "rogue_user_exists": $ROGUE_USER_EXISTS
    },
    "issues_fixed": {
        "title_fixed": $TITLE_FIXED,
        "tagline_fixed": $TAGLINE_FIXED,
        "rogue_user_fixed": $ROGUE_USER_FIXED,
        "permalink_fixed": $PERMALINK_FIXED,
        "comment_mod_fixed": $COMMENT_MOD_FIXED,
        "registration_fixed": $REGISTRATION_FIXED,
        "timezone_fixed": $TIMEZONE_FIXED,
        "fixed_count": $FIXED_COUNT
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/diagnose_fix_compromised_site_result.json 2>/dev/null || sudo rm -f /tmp/diagnose_fix_compromised_site_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/diagnose_fix_compromised_site_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/diagnose_fix_compromised_site_result.json
chmod 666 /tmp/diagnose_fix_compromised_site_result.json 2>/dev/null || sudo chmod 666 /tmp/diagnose_fix_compromised_site_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/diagnose_fix_compromised_site_result.json"
cat /tmp/diagnose_fix_compromised_site_result.json
echo ""
echo "=== Export complete ==="
