#!/bin/bash
echo "=== Exporting deactivate_dormant_users result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM verification
take_screenshot /tmp/task_end.png

# Query final status of all relevant users
# Status 1 = Active, 2 = Disabled (FreeScout default)
STATUS_DORMANT_OLD=$(fs_query "SELECT status FROM users WHERE email='dormant.old@helpdesk.local'" 2>/dev/null || echo "0")
STATUS_DORMANT_NEVER=$(fs_query "SELECT status FROM users WHERE email='dormant.never@helpdesk.local'" 2>/dev/null || echo "0")
STATUS_ACTIVE_RECENT=$(fs_query "SELECT status FROM users WHERE email='active.recent@helpdesk.local'" 2>/dev/null || echo "0")
STATUS_ACTIVE_BORDER=$(fs_query "SELECT status FROM users WHERE email='active.borderline@helpdesk.local'" 2>/dev/null || echo "0")
STATUS_ADMIN=$(fs_query "SELECT status FROM users WHERE email='admin@helpdesk.local'" 2>/dev/null || echo "0")

# Get counts
INITIAL_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_user_count)

# Check if users still exist (to detect deletion)
EXISTS_DORMANT_OLD=$(fs_query "SELECT COUNT(*) FROM users WHERE email='dormant.old@helpdesk.local'" 2>/dev/null || echo "0")
EXISTS_DORMANT_NEVER=$(fs_query "SELECT COUNT(*) FROM users WHERE email='dormant.never@helpdesk.local'" 2>/dev/null || echo "0")

# Construct JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_user_count": ${INITIAL_COUNT},
    "current_user_count": ${CURRENT_COUNT},
    "users": {
        "dormant_old": {
            "status": ${STATUS_DORMANT_OLD},
            "exists": ${EXISTS_DORMANT_OLD}
        },
        "dormant_never": {
            "status": ${STATUS_DORMANT_NEVER},
            "exists": ${EXISTS_DORMANT_NEVER}
        },
        "active_recent": {
            "status": ${STATUS_ACTIVE_RECENT}
        },
        "active_borderline": {
            "status": ${STATUS_ACTIVE_BORDER}
        },
        "admin": {
            "status": ${STATUS_ADMIN}
        }
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe copy to output location
safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="