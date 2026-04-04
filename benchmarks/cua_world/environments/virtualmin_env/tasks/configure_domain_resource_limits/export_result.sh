#!/bin/bash
echo "=== Exporting configure_domain_resource_limits result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

TARGET_DOMAIN="greenvalley.test"

# Get domain ID for config file lookup
DOMAIN_ID=$(virtualmin list-domains --domain "$TARGET_DOMAIN" --id-only 2>/dev/null)

# Read quota and bw_limit from domain config file (they are NOT in list-domains --multiline output)
DOMAIN_CONFIG="/etc/webmin/virtual-server/domains/${DOMAIN_ID}"
QUOTA_RAW=""
BW_RAW=""
if [ -f "$DOMAIN_CONFIG" ]; then
    QUOTA_RAW=$(grep "^quota=" "$DOMAIN_CONFIG" 2>/dev/null | cut -d= -f2)
    BW_RAW=$(grep "^bw_limit=" "$DOMAIN_CONFIG" 2>/dev/null | cut -d= -f2)
fi

# Get max mailboxes, aliases, databases from list-domains --multiline
DOMAIN_INFO=$(virtualmin list-domains --domain "$TARGET_DOMAIN" --multiline 2>/dev/null)

MAX_MAIL_VAL=$(echo "$DOMAIN_INFO" | grep -i "Maximum mailboxes" | awk '{print $NF}' | head -1)
MAX_ALIAS_VAL=$(echo "$DOMAIN_INFO" | grep -i "Maximum aliases" | awk '{print $NF}' | head -1)
MAX_DBS_VAL=$(echo "$DOMAIN_INFO" | grep -i "Maximum databases" | awk '{print $NF}' | head -1)

# Use Python to create reliable JSON
python3 << PYEOF
import json

def parse_val(raw, zero_means_unlimited=False):
    """Parse a Virtualmin value - could be a number, UNLIMITED, NONE, etc."""
    raw = str(raw).strip()
    if not raw or raw.upper() in ('UNLIMITED', 'NONE', 'N/A', ''):
        return None
    try:
        val = int(raw.replace(',', ''))
        if zero_means_unlimited and val == 0:
            return None
        return val
    except ValueError:
        try:
            return float(raw.replace(',', ''))
        except ValueError:
            return raw

data = {
    "domain": "${TARGET_DOMAIN}",
    "quota_raw": "${QUOTA_RAW}",
    "bw_raw": "${BW_RAW}",
    "max_mailboxes_raw": "${MAX_MAIL_VAL}",
    "max_aliases_raw": "${MAX_ALIAS_VAL}",
    "max_dbs_raw": "${MAX_DBS_VAL}",
    "export_timestamp": "$(date -Iseconds)"
}

data["quota_parsed"] = parse_val(data["quota_raw"], zero_means_unlimited=True)
data["bw_parsed"] = parse_val(data["bw_raw"])
data["max_mailboxes_parsed"] = parse_val(data["max_mailboxes_raw"])
data["max_aliases_parsed"] = parse_val(data["max_aliases_raw"])
data["max_dbs_parsed"] = parse_val(data["max_dbs_raw"])

with open("/tmp/configure_domain_resource_limits_result.json", "w") as f:
    json.dump(data, f, indent=2)

print(json.dumps(data, indent=2))
PYEOF

echo ""
echo "=== Export Complete ==="
