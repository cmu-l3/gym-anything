#!/bin/bash
set -e
echo "=== Verifying task: setup_store_manager_role ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Debug log
DEBUG_LOG="/tmp/verifier_debug.log"
echo "=== Verification started at $(date) ===" > "$DEBUG_LOG"

SCORE=0
DETAILS=""
DRUPAL_DIR="/var/www/html/drupal"
DRUSH="$DRUPAL_DIR/vendor/bin/drush"

# Load baseline
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Clear Drupal caches to ensure fresh data
cd "$DRUPAL_DIR" && $DRUSH cr 2>/dev/null || true

# ============================================================
# Criterion 1: Role exists with correct name (15 pts)
# ============================================================
echo "--- Criterion 1: Role existence ---" >> "$DEBUG_LOG"

ROLE_EXISTS=false
ROLE_LABEL=""

# Check via Drush
ROLE_INFO=$(cd "$DRUPAL_DIR" && $DRUSH role:list --format=json 2>/dev/null || echo "{}")
echo "Role list output: $ROLE_INFO" >> "$DEBUG_LOG"

if echo "$ROLE_INFO" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'store_manager' in data:
    print('EXISTS')
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
    ROLE_EXISTS=true
fi

# Also check config table directly
ROLE_CONFIG=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'user.role.store_manager'" 2>/dev/null || echo "0")
echo "Role config count: $ROLE_CONFIG" >> "$DEBUG_LOG"

if [ "$ROLE_EXISTS" = true ] || [ "$ROLE_CONFIG" -gt 0 ]; then
    # Check the label
    ROLE_LABEL=$(cd "$DRUPAL_DIR" && $DRUSH php:eval "
        \$role = \Drupal\user\Entity\Role::load('store_manager');
        if (\$role) { echo \$role->label(); }
    " 2>/dev/null || echo "")
    echo "Role label: '$ROLE_LABEL'" >> "$DEBUG_LOG"

    if echo "$ROLE_LABEL" | grep -qi "store.manager\|store manager"; then
        SCORE=$((SCORE + 15))
        DETAILS="${DETAILS}Criterion 1 (Role exists): PASS - store_manager role found with label '$ROLE_LABEL'\n"
    else
        SCORE=$((SCORE + 8))
        DETAILS="${DETAILS}Criterion 1 (Role exists): PARTIAL - store_manager config exists but label is '$ROLE_LABEL'\n"
    fi
    ROLE_EXISTS=true
else
    DETAILS="${DETAILS}Criterion 1 (Role exists): FAIL - store_manager role not found\n"
    ROLE_EXISTS=false
fi

# ============================================================
# Gate check: If no role exists, most subsequent checks are moot
# but we still check user creation
# ============================================================

# ============================================================
# Criterion 2: Commerce product permissions (20 pts)
# ============================================================
echo "--- Criterion 2: Product permissions ---" >> "$DEBUG_LOG"

if [ "$ROLE_EXISTS" = true ]; then
    # Get all permissions for the role
    PERMS=$(cd "$DRUPAL_DIR" && $DRUSH php:eval "
        \$role = \Drupal\user\Entity\Role::load('store_manager');
        if (\$role) {
            foreach (\$role->getPermissions() as \$p) { echo \$p . '\n'; }
        }
    " 2>/dev/null || echo "")
    echo "All permissions for store_manager:" >> "$DEBUG_LOG"
    echo "$PERMS" >> "$DEBUG_LOG"

    PRODUCT_PERM_SCORE=0
    PRODUCT_PERM_TOTAL=4

    if echo "$PERMS" | grep -q "view commerce_product"; then
        PRODUCT_PERM_SCORE=$((PRODUCT_PERM_SCORE + 1))
    fi
    if echo "$PERMS" | grep -q "create default commerce_product"; then
        PRODUCT_PERM_SCORE=$((PRODUCT_PERM_SCORE + 1))
    fi
    if echo "$PERMS" | grep -q "update any default commerce_product"; then
        PRODUCT_PERM_SCORE=$((PRODUCT_PERM_SCORE + 1))
    fi
    if echo "$PERMS" | grep -q "delete any default commerce_product"; then
        PRODUCT_PERM_SCORE=$((PRODUCT_PERM_SCORE + 1))
    fi

    PERM2_POINTS=$(( (PRODUCT_PERM_SCORE * 20) / PRODUCT_PERM_TOTAL ))
    SCORE=$((SCORE + PERM2_POINTS))
    DETAILS="${DETAILS}Criterion 2 (Product perms): ${PRODUCT_PERM_SCORE}/${PRODUCT_PERM_TOTAL} granted = ${PERM2_POINTS}/20 pts\n"
else
    DETAILS="${DETAILS}Criterion 2 (Product perms): SKIP - role doesn't exist\n"
fi

# ============================================================
# Criterion 3: Commerce order permissions (15 pts)
# ============================================================
echo "--- Criterion 3: Order permissions ---" >> "$DEBUG_LOG"

if [ "$ROLE_EXISTS" = true ]; then
    ORDER_PERM_SCORE=0
    ORDER_PERM_TOTAL=2

    if echo "$PERMS" | grep -q "administer commerce_order"; then
        ORDER_PERM_SCORE=$((ORDER_PERM_SCORE + 1))
    fi
    if echo "$PERMS" | grep -q "access commerce_order overview"; then
        ORDER_PERM_SCORE=$((ORDER_PERM_SCORE + 1))
    fi

    PERM3_POINTS=$(( (ORDER_PERM_SCORE * 15) / ORDER_PERM_TOTAL ))
    SCORE=$((SCORE + PERM3_POINTS))
    DETAILS="${DETAILS}Criterion 3 (Order perms): ${ORDER_PERM_SCORE}/${ORDER_PERM_TOTAL} granted = ${PERM3_POINTS}/15 pts\n"
else
    DETAILS="${DETAILS}Criterion 3 (Order perms): SKIP - role doesn't exist\n"
fi

# ============================================================
# Criterion 4: Commerce promotion permission (10 pts)
# ============================================================
echo "--- Criterion 4: Promotion permission ---" >> "$DEBUG_LOG"

if [ "$ROLE_EXISTS" = true ]; then
    if echo "$PERMS" | grep -q "administer commerce_promotion"; then
        SCORE=$((SCORE + 10))
        DETAILS="${DETAILS}Criterion 4 (Promotion perm): PASS\n"
    else
        DETAILS="${DETAILS}Criterion 4 (Promotion perm): FAIL - administer commerce_promotion not found\n"
    fi
else
    DETAILS="${DETAILS}Criterion 4 (Promotion perm): SKIP - role doesn't exist\n"
fi

# ============================================================
# Criterion 5: Admin access permissions (5 pts)
# ============================================================
echo "--- Criterion 5: Admin access permissions ---" >> "$DEBUG_LOG"

if [ "$ROLE_EXISTS" = true ]; then
    ADMIN_PERM_SCORE=0
    ADMIN_PERM_TOTAL=2

    if echo "$PERMS" | grep -q "access administration pages"; then
        ADMIN_PERM_SCORE=$((ADMIN_PERM_SCORE + 1))
    fi
    if echo "$PERMS" | grep -q "access commerce administration pages"; then
        ADMIN_PERM_SCORE=$((ADMIN_PERM_SCORE + 1))
    fi

    PERM5_POINTS=$(( (ADMIN_PERM_SCORE * 5) / ADMIN_PERM_TOTAL ))
    SCORE=$((SCORE + PERM5_POINTS))
    DETAILS="${DETAILS}Criterion 5 (Admin access): ${ADMIN_PERM_SCORE}/${ADMIN_PERM_TOTAL} granted = ${PERM5_POINTS}/5 pts\n"
else
    DETAILS="${DETAILS}Criterion 5 (Admin access): SKIP - role doesn't exist\n"
fi

# ============================================================
# Criterion 6: User account created (15 pts)
# ============================================================
echo "--- Criterion 6: User account ---" >> "$DEBUG_LOG"

USER_EXISTS=false
USER_UID=""

USER_DATA=$(drupal_db_query "SELECT uid, name, mail, status, created FROM users_field_data WHERE name = 'sarahchen' LIMIT 1" 2>/dev/null || echo "")
echo "User query result: '$USER_DATA'" >> "$DEBUG_LOG"

if [ -n "$USER_DATA" ] && [ "$USER_DATA" != "" ]; then
    USER_UID=$(echo "$USER_DATA" | awk '{print $1}')
    USER_NAME=$(echo "$USER_DATA" | awk '{print $2}')
    USER_MAIL=$(echo "$USER_DATA" | awk '{print $3}')
    USER_STATUS=$(echo "$USER_DATA" | awk '{print $4}')
    USER_CREATED=$(echo "$USER_DATA" | awk '{print $5}')

    echo "UID=$USER_UID NAME=$USER_NAME MAIL=$USER_MAIL STATUS=$USER_STATUS CREATED=$USER_CREATED" >> "$DEBUG_LOG"

    USER_SCORE=0

    # Check username exists
    if [ -n "$USER_UID" ] && [ "$USER_UID" -gt 0 ] 2>/dev/null; then
        USER_EXISTS=true
        USER_SCORE=$((USER_SCORE + 5))
    fi

    # Check email
    if echo "$USER_MAIL" | grep -qi "sarah.chen@urbanelectronics.com"; then
        USER_SCORE=$((USER_SCORE + 5))
    else
        echo "Email mismatch: expected sarah.chen@urbanelectronics.com, got $USER_MAIL" >> "$DEBUG_LOG"
    fi

    # Check active status
    if [ "$USER_STATUS" = "1" ]; then
        USER_SCORE=$((USER_SCORE + 3))
    else
        echo "User is not active (status=$USER_STATUS)" >> "$DEBUG_LOG"
    fi

    # Anti-gaming: check creation timestamp
    if [ -n "$USER_CREATED" ] && [ "$USER_CREATED" -ge "$TASK_START_TIME" ] 2>/dev/null; then
        echo "User created after task start (good)" >> "$DEBUG_LOG"
    else
        echo "WARNING: User created timestamp ($USER_CREATED) is before task start ($TASK_START_TIME)" >> "$DEBUG_LOG"
        USER_SCORE=$((USER_SCORE - 2))
        [ $USER_SCORE -lt 0 ] && USER_SCORE=0
    fi

    SCORE=$((SCORE + USER_SCORE))
    DETAILS="${DETAILS}Criterion 6 (User account): ${USER_SCORE}/15 pts (uid=$USER_UID, mail=$USER_MAIL, status=$USER_STATUS)\n"
else
    DETAILS="${DETAILS}Criterion 6 (User account): FAIL - user 'sarahchen' not found\n"
fi

# ============================================================
# Criterion 7: Role assigned to user (15 pts)
# ============================================================
echo "--- Criterion 7: Role assignment ---" >> "$DEBUG_LOG"

if [ "$USER_EXISTS" = true ] && [ "$ROLE_EXISTS" = true ]; then
    ROLE_ASSIGNED=$(drupal_db_query "SELECT COUNT(*) FROM user__roles WHERE entity_id = $USER_UID AND roles_target_id = 'store_manager'" 2>/dev/null || echo "0")
    echo "Role assignment count: $ROLE_ASSIGNED" >> "$DEBUG_LOG"

    if [ "$ROLE_ASSIGNED" -gt 0 ]; then
        SCORE=$((SCORE + 15))
        DETAILS="${DETAILS}Criterion 7 (Role assigned): PASS - store_manager role assigned to sarahchen\n"
    else
        DETAILS="${DETAILS}Criterion 7 (Role assigned): FAIL - store_manager role NOT assigned to sarahchen (uid=$USER_UID)\n"

        # Check if any role was assigned
        ANY_ROLES=$(drupal_db_query "SELECT roles_target_id FROM user__roles WHERE entity_id = $USER_UID" 2>/dev/null || echo "none")
        echo "User's roles: $ANY_ROLES" >> "$DEBUG_LOG"
    fi
elif [ "$USER_EXISTS" = false ]; then
    DETAILS="${DETAILS}Criterion 7 (Role assigned): SKIP - user doesn't exist\n"
elif [ "$ROLE_EXISTS" = false ]; then
    DETAILS="${DETAILS}Criterion 7 (Role assigned): SKIP - role doesn't exist\n"
fi

# ============================================================
# Criterion 8: No dangerous permissions (5 pts - bonus safety)
# ============================================================
echo "--- Criterion 8: No dangerous permissions ---" >> "$DEBUG_LOG"

if [ "$ROLE_EXISTS" = true ]; then
    DANGEROUS=false

    if echo "$PERMS" | grep -q "administer commerce_store"; then
        DANGEROUS=true
        echo "DANGEROUS: has administer commerce_store" >> "$DEBUG_LOG"
    fi
    if echo "$PERMS" | grep -q "administer commerce_payment_gateway"; then
        DANGEROUS=true
        echo "DANGEROUS: has administer commerce_payment_gateway" >> "$DEBUG_LOG"
    fi

    if [ "$DANGEROUS" = false ]; then
        SCORE=$((SCORE + 5))
        DETAILS="${DETAILS}Criterion 8 (No dangerous perms): PASS - no over-permissioning detected\n"
    else
        DETAILS="${DETAILS}Criterion 8 (No dangerous perms): FAIL - dangerous permissions granted\n"
    fi
else
    DETAILS="${DETAILS}Criterion 8 (No dangerous perms): SKIP - role doesn't exist\n"
fi

# ============================================================
# Anti-gaming: "do nothing" detection
# ============================================================
echo "--- Anti-gaming checks ---" >> "$DEBUG_LOG"

CURRENT_USER_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM users_field_data WHERE uid > 0" 2>/dev/null || echo "0")
CURRENT_ROLE_COUNT=$(cd "$DRUPAL_DIR" && $DRUSH role:list --format=list 2>/dev/null | wc -l || echo "0")

echo "User count: initial=$INITIAL_USER_COUNT, current=$CURRENT_USER_COUNT" >> "$DEBUG_LOG"
echo "Role count: initial=$(cat /tmp/initial_role_count.txt 2>/dev/null), current=$CURRENT_ROLE_COUNT" >> "$DEBUG_LOG"

if [ "$CURRENT_USER_COUNT" = "$INITIAL_USER_COUNT" ] && [ "$ROLE_EXISTS" = false ]; then
    echo "DO-NOTHING DETECTED: No new users or roles created" >> "$DEBUG_LOG"
    SCORE=0
    DETAILS="ANTI-GAMING: No changes detected. Score forced to 0.\n${DETAILS}"
fi

# ============================================================
# Gate check: Both role AND user must exist for passing score
# ============================================================
if [ "$ROLE_EXISTS" = false ] && [ "$USER_EXISTS" = false ]; then
    echo "GATE FAIL: Neither role nor user exists" >> "$DEBUG_LOG"
    if [ $SCORE -gt 10 ]; then
        SCORE=10
    fi
    DETAILS="GATE: Neither role nor user created. Score capped.\n${DETAILS}"
fi

# ============================================================
# Output results
# ============================================================
echo ""
echo "=== VERIFICATION RESULTS ==="
echo -e "$DETAILS"
echo "TOTAL SCORE: $SCORE / 100"
echo ""

# Write result JSON
RESULT_FILE="/tmp/task_result.json"
cat > "$RESULT_FILE" << EOF
{
    "score": $SCORE,
    "max_score": 100,
    "pass_threshold": 65,
    "passed": $([ $SCORE -ge 65 ] && echo "true" || echo "false"),
    "details": "$(echo -e "$DETAILS" | tr '\n' '|' | sed 's/|/\\n/g' | sed 's/"/\\"/g')"
}
EOF

echo "Result written to $RESULT_FILE"
cat "$RESULT_FILE"

# Copy debug log
cp "$DEBUG_LOG" /tmp/verifier_debug_final.log 2>/dev/null || true

exit 0