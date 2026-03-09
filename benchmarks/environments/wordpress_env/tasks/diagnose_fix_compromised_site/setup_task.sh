#!/bin/bash
# Setup script for diagnose_fix_compromised_site task (pre_task hook)
# Injects 7 security/configuration issues into the WordPress site
# that the agent must discover and fix.

echo "=== Setting up diagnose_fix_compromised_site task ==="

source /workspace/scripts/task_utils.sh

# ============================================================
# Record baseline (original values before injection)
# ============================================================
ORIG_BLOGNAME=$(wp_cli option get blogname)
ORIG_BLOGDESC=$(wp_cli option get blogdescription)
ORIG_PERMALINK=$(wp_cli option get permalink_structure)
ORIG_COMMENT_MOD=$(wp_cli option get comment_moderation)
ORIG_USERS_CAN_REG=$(wp_cli option get users_can_register)
ORIG_DEFAULT_ROLE=$(wp_cli option get default_role)
ORIG_TIMEZONE=$(wp_cli option get timezone_string)

echo "Baseline recorded:"
echo "  blogname: $ORIG_BLOGNAME"
echo "  blogdescription: $ORIG_BLOGDESC"
echo "  permalink_structure: $ORIG_PERMALINK"
echo "  comment_moderation: $ORIG_COMMENT_MOD"
echo "  users_can_register: $ORIG_USERS_CAN_REG"
echo "  default_role: $ORIG_DEFAULT_ROLE"
echo "  timezone_string: $ORIG_TIMEZONE"

# Save baseline for verification
cat > /tmp/compromised_site_baseline.json << BASEEOF
{
    "original_blogname": "$(json_escape "$ORIG_BLOGNAME")",
    "original_blogdescription": "$(json_escape "$ORIG_BLOGDESC")",
    "original_permalink": "$(json_escape "$ORIG_PERMALINK")",
    "original_comment_moderation": "$ORIG_COMMENT_MOD",
    "original_users_can_register": "$ORIG_USERS_CAN_REG",
    "original_default_role": "$ORIG_DEFAULT_ROLE",
    "original_timezone": "$ORIG_TIMEZONE"
}
BASEEOF
chmod 666 /tmp/compromised_site_baseline.json

# Record task start timestamp (AFTER baseline, BEFORE injections)
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# ============================================================
# INJECT ISSUE 1: Change site title to spam
# ============================================================
echo "Injecting issue 1: Spam site title..."
wp_cli option update blogname "H4CK3D SITE - Buy Ch3ap M3ds Online"

# ============================================================
# INJECT ISSUE 2: Change tagline to spam
# ============================================================
echo "Injecting issue 2: Spam tagline..."
wp_cli option update blogdescription "Best pr1ces on pharmaceut1cals - V1sit our store now"

# ============================================================
# INJECT ISSUE 3: Create rogue admin user
# ============================================================
echo "Injecting issue 3: Rogue admin user..."
cd /var/www/html/wordpress
# Delete if exists (from previous run)
wp user delete service_worker --yes --allow-root 2>/dev/null || true
wp user create service_worker svc_worker@malicious-domain.xyz \
    --role=administrator \
    --first_name="System" \
    --last_name="Service" \
    --user_pass="backdoor_p@ss123" \
    --allow-root 2>&1
echo "Rogue user 'service_worker' created with admin role"

# ============================================================
# INJECT ISSUE 4: Change permalink structure to plain
# ============================================================
echo "Injecting issue 4: Plain permalink structure..."
wp_cli option update permalink_structure ""
wp_cli rewrite flush

# ============================================================
# INJECT ISSUE 5: Disable comment moderation
# ============================================================
echo "Injecting issue 5: Disabling comment moderation..."
wp_cli option update comment_moderation 0

# ============================================================
# INJECT ISSUE 6: Enable open registration with admin role
# ============================================================
echo "Injecting issue 6: Open registration as administrator..."
wp_cli option update users_can_register 1
wp_cli option update default_role "administrator"

# ============================================================
# INJECT ISSUE 7: Change timezone
# ============================================================
echo "Injecting issue 7: Changing timezone to UTC..."
wp_cli option update timezone_string "UTC"

# ============================================================
# Verify injections
# ============================================================
echo ""
echo "Verifying injected issues:"
echo "  blogname: $(wp_cli option get blogname)"
echo "  blogdescription: $(wp_cli option get blogdescription)"
echo "  permalink_structure: '$(wp_cli option get permalink_structure)'"
echo "  comment_moderation: $(wp_cli option get comment_moderation)"
echo "  users_can_register: $(wp_cli option get users_can_register)"
echo "  default_role: $(wp_cli option get default_role)"
echo "  timezone_string: $(wp_cli option get timezone_string)"
echo "  service_worker exists: $(wp_cli user get service_worker --field=ID 2>/dev/null && echo YES || echo NO)"

# Ensure Firefox is running and focused
echo ""
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/?autologin=admin' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete (7 issues injected) ==="
