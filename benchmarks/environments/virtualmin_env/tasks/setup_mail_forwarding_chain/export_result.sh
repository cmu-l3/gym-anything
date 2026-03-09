#!/bin/bash
echo "=== Exporting setup_mail_forwarding_chain result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

TARGET_DOMAIN="acmecorp.test"

# Query current users (--name-only outputs user@domain format)
USERS_OUTPUT=$(virtualmin list-users --domain "$TARGET_DOMAIN" --name-only 2>/dev/null)
USERS_FULL=$(virtualmin list-users --domain "$TARGET_DOMAIN" --multiline 2>/dev/null)

# Check for specific new users (format: hr@acmecorp.test)
HR_EXISTS="false"
BILLING_EXISTS="false"

if echo "$USERS_OUTPUT" | grep -q "^hr@"; then
    HR_EXISTS="true"
fi
if echo "$USERS_OUTPUT" | grep -q "^billing@"; then
    BILLING_EXISTS="true"
fi

# Check real names from multiline output
# Format: "hr@acmecorp.test\n    User: hr\n    Domain: ...\n    ...    Real name: HR Department"
HR_REALNAME=$(echo "$USERS_FULL" | awk '/^hr@/{found=1} found && /Real name:/{print; exit}' | sed 's/.*Real name: *//')
BILLING_REALNAME=$(echo "$USERS_FULL" | awk '/^billing@/{found=1} found && /Real name:/{print; exit}' | sed 's/.*Real name: *//')

# Query current aliases (tabular format: "Alias    Destination")
ALIASES_OUTPUT=$(virtualmin list-aliases --domain "$TARGET_DOMAIN" 2>/dev/null)

# Check for specific aliases
JOBS_ALIAS="false"
JOBS_DEST=""
INVOICES_ALIAS="false"
INVOICES_DEST=""
CONTACT_ALIAS="false"
CONTACT_DEST=""
CONTACT_HAS_INFO="false"
CONTACT_HAS_ADMIN="false"

# Parse tabular alias output - aliases are listed without @domain
if echo "$ALIASES_OUTPUT" | grep -q "^jobs "; then
    JOBS_ALIAS="true"
    JOBS_DEST=$(echo "$ALIASES_OUTPUT" | grep "^jobs " | sed 's/^jobs[[:space:]]*//')
fi

if echo "$ALIASES_OUTPUT" | grep -q "^invoices "; then
    INVOICES_ALIAS="true"
    INVOICES_DEST=$(echo "$ALIASES_OUTPUT" | grep "^invoices " | sed 's/^invoices[[:space:]]*//')
fi

if echo "$ALIASES_OUTPUT" | grep -q "^contact "; then
    CONTACT_ALIAS="true"
    CONTACT_DEST=$(echo "$ALIASES_OUTPUT" | grep "^contact " | sed 's/^contact[[:space:]]*//')
    if echo "$CONTACT_DEST" | grep -qi "info"; then
        CONTACT_HAS_INFO="true"
    fi
    if echo "$CONTACT_DEST" | grep -qi "admin"; then
        CONTACT_HAS_ADMIN="true"
    fi
fi

# Get baseline
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count 2>/dev/null || echo "0")
INITIAL_ALIAS_COUNT=$(cat /tmp/initial_alias_count 2>/dev/null || echo "0")

# Use Python for reliable JSON output
python3 << PYEOF
import json

data = {
    "domain": "${TARGET_DOMAIN}",
    "hr_user_exists": '${HR_EXISTS}' == 'true',
    "hr_realname": """${HR_REALNAME}""".strip(),
    "billing_user_exists": '${BILLING_EXISTS}' == 'true',
    "billing_realname": """${BILLING_REALNAME}""".strip(),
    "jobs_alias_exists": '${JOBS_ALIAS}' == 'true',
    "jobs_alias_dest": """${JOBS_DEST}""".strip(),
    "invoices_alias_exists": '${INVOICES_ALIAS}' == 'true',
    "invoices_alias_dest": """${INVOICES_DEST}""".strip(),
    "contact_alias_exists": '${CONTACT_ALIAS}' == 'true',
    "contact_alias_dest": """${CONTACT_DEST}""".strip(),
    "contact_has_info_dest": '${CONTACT_HAS_INFO}' == 'true',
    "contact_has_admin_dest": '${CONTACT_HAS_ADMIN}' == 'true',
    "initial_user_count": int('${INITIAL_USER_COUNT}' or '0'),
    "initial_alias_count": int('${INITIAL_ALIAS_COUNT}' or '0'),
    "export_timestamp": "$(date -Iseconds)"
}

with open("/tmp/setup_mail_forwarding_chain_result.json", "w") as f:
    json.dump(data, f, indent=2)

print(json.dumps(data, indent=2))
PYEOF

echo "=== Export Complete ==="
