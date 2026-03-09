#!/bin/bash
# post_task: Export results for sca_custom_policy_report
echo "=== Exporting sca_custom_policy_report Results ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Desktop/compliance_report.txt"

take_screenshot /tmp/task_end_screenshot.png

# === Check 1: Custom SCA policy YAML file exists with valid structure ===
CUSTOM_POLICY_EXISTS=0
CUSTOM_POLICY_NAME=""
CUSTOM_POLICY_CHECK_COUNT=0

SCA_CHECK=$(docker exec "${CONTAINER}" python3 -c "
import os

DEFAULT_PATTERNS = ['cis_ubuntu', 'cis_debian', 'cis_centos', 'cis_rhel', 'cis_sles',
                    'cis_apple', 'cis_win', 'cis_macos']

def check_policy_file(fpath):
    try:
        with open(fpath) as f:
            content = f.read()
        # Must look like a Wazuh SCA policy YAML
        if 'policy:' not in content and 'checks:' not in content:
            return None
        if 'checks:' not in content:
            return None
        # Count check entries (lines with '- id:' pattern)
        check_count = content.count('- id:') + content.count('  id:')
        # Also count lines that look like check items
        if check_count < 1:
            # Try alternate check count methods
            check_count = sum(1 for line in content.splitlines()
                             if line.strip().startswith('- id:') or
                             (line.strip().startswith('id:') and 'policy' not in line))
        return max(check_count, 0)
    except Exception:
        return None

# Search all shared directories for custom YAML policy files
search_dirs = [
    '/var/ossec/etc/shared',
    '/var/ossec/etc/shared/default',
]
for d in search_dirs:
    if not os.path.isdir(d):
        continue
    for root, dirs, files in os.walk(d):
        for fname in files:
            if not (fname.endswith('.yml') or fname.endswith('.yaml')):
                continue
            # Skip default CIS policies
            if any(dp in fname.lower() for dp in DEFAULT_PATTERNS):
                continue
            fpath = os.path.join(root, fname)
            count = check_policy_file(fpath)
            if count is not None and count >= 1:
                print(f'found:{fname}:{count}')
                exit(0)

print('not_found')
" 2>/dev/null || echo "not_found")

if echo "$SCA_CHECK" | grep -q "^found:"; then
    CUSTOM_POLICY_EXISTS=1
    POLICY_INFO=$(echo "$SCA_CHECK" | grep "^found:" | head -1 | cut -d':' -f2-)
    CUSTOM_POLICY_NAME=$(echo "$POLICY_INFO" | cut -d':' -f1)
    CUSTOM_POLICY_CHECK_COUNT=$(echo "$POLICY_INFO" | cut -d':' -f2)
    [ -z "$CUSTOM_POLICY_CHECK_COUNT" ] && CUSTOM_POLICY_CHECK_COUNT=0
fi

# === Check 2: ossec.conf references a custom (non-CIS-default) policy ===
OSSEC_HAS_CUSTOM_POLICY=0

DEFAULT_SCA_PATTERNS="cis_ubuntu cis_debian cis_centos cis_rhel cis_sles cis_apple cis_win"

POLICY_CHECK=$(docker exec "${CONTAINER}" python3 -c "
import xml.etree.ElementTree as ET
default_patterns = ['cis_ubuntu', 'cis_debian', 'cis_centos', 'cis_rhel', 'cis_sles',
                    'cis_apple', 'cis_win', 'cis_macos']
try:
    tree = ET.parse('/var/ossec/etc/ossec.conf')
    root = tree.getroot()
    for sca in root.iter('sca'):
        for policy in sca.iter('policy'):
            if policy.text:
                ptext = policy.text.strip().lower()
                if not any(dp in ptext for dp in default_patterns):
                    print('found:' + policy.text.strip())
                    exit(0)
    print('not_found')
except Exception as e:
    print('error:' + str(e))
" 2>/dev/null || echo "not_found")

if echo "$POLICY_CHECK" | grep -q "^found:"; then
    OSSEC_HAS_CUSTOM_POLICY=1
fi

# Also check host-mounted config as fallback
HOST_POLICY_CHECK=$(python3 -c "
import xml.etree.ElementTree as ET
default_patterns = ['cis_ubuntu', 'cis_debian', 'cis_centos', 'cis_rhel', 'cis_sles',
                    'cis_apple', 'cis_win', 'cis_macos']
try:
    tree = ET.parse('/home/ga/wazuh/config/wazuh_cluster/wazuh_manager.conf')
    root = tree.getroot()
    for sca in root.iter('sca'):
        for policy in sca.iter('policy'):
            if policy.text:
                ptext = policy.text.strip().lower()
                if not any(dp in ptext for dp in default_patterns):
                    print('found')
                    exit(0)
    print('not_found')
except Exception:
    print('not_found')
" 2>/dev/null || echo "not_found")

if echo "$HOST_POLICY_CHECK" | grep -q "^found"; then
    OSSEC_HAS_CUSTOM_POLICY=1
fi

# === Check 3: Compliance report on desktop ===
REPORT_EXISTS=0
REPORT_SIZE=0
REPORT_MTIME=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS=1
    REPORT_SIZE=$(wc -c < "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
fi

# Create result JSON
cat > /tmp/sca_custom_policy_report_result.json << EOF
{
    "task_start": ${TASK_START},
    "custom_policy_exists": ${CUSTOM_POLICY_EXISTS},
    "custom_policy_name": "${CUSTOM_POLICY_NAME}",
    "custom_policy_check_count": ${CUSTOM_POLICY_CHECK_COUNT},
    "ossec_has_custom_policy": ${OSSEC_HAS_CUSTOM_POLICY},
    "report_exists": ${REPORT_EXISTS},
    "report_size_chars": ${REPORT_SIZE},
    "report_mtime": ${REPORT_MTIME},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat /tmp/sca_custom_policy_report_result.json
echo "=== Export Complete ==="
