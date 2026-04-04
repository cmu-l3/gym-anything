#!/bin/bash
# Setup script for cisa_kev_threat_intelligence
# Downloads real CISA KEV catalog and records baseline state.
# Per task creation rules: NO synthetic data fallback — fail cleanly if download fails.

echo "=== Setting up cisa_kev_threat_intelligence ==="

source /workspace/scripts/task_utils.sh

if ! type wazuh_exec &>/dev/null; then
    echo "Warning: task_utils.sh not fully loaded, using inline definitions"
    wazuh_exec() { docker exec wazuh.manager bash -c "$1" 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

MAX_WAIT=60
WAITED=0
until docker ps | grep -q "wazuh.manager"; do
    sleep 5
    WAITED=$((WAITED + 5))
    if [ "$WAITED" -ge "$MAX_WAIT" ]; then
        echo "ERROR: wazuh.manager not running after ${MAX_WAIT}s"
        exit 1
    fi
done

# --- Remove any pre-existing KEV integration artifacts ---
echo "Cleaning pre-existing KEV integration artifacts..."
wazuh_exec "find /var/ossec/etc/lists/ -name '*kev*' -o -name '*cisa*' -o -name '*cve*' 2>/dev/null | xargs rm -f 2>/dev/null || true"
rm -f /home/ga/Desktop/kev_integration_report.txt 2>/dev/null || true

# --- Download real CISA KEV catalog ---
# Source: CISA Known Exploited Vulnerabilities Catalog (public, machine-readable JSON)
# https://www.cisa.gov/known-exploited-vulnerabilities-catalog
KEV_URL="https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json"
KEV_PATH="/tmp/cisa_kev.json"

echo "Downloading CISA KEV catalog from ${KEV_URL}..."
wget -q --timeout=30 --tries=3 "${KEV_URL}" -O "${KEV_PATH}"

if [ ! -s "${KEV_PATH}" ]; then
    echo "ERROR: Failed to download CISA KEV catalog from ${KEV_URL}"
    echo "ERROR: This task requires real CISA KEV data. Please check network connectivity."
    echo "ERROR: No synthetic data fallback — real data is required for this benchmark task."
    exit 1
fi

# Validate it's real JSON with CVE data
CVE_COUNT=$(python3 -c "
import json, sys
try:
    with open('${KEV_PATH}') as f:
        data = json.load(f)
    vulns = data.get('vulnerabilities', [])
    print(len(vulns))
except Exception as e:
    print('0')
    print(str(e), file=sys.stderr)
" 2>/dev/null)

if [ "$CVE_COUNT" -lt 10 ] 2>/dev/null; then
    echo "ERROR: CISA KEV catalog appears invalid or incomplete (found ${CVE_COUNT:-0} entries)"
    echo "ERROR: Real data required — no synthetic fallback allowed."
    exit 1
fi

echo "CISA KEV catalog downloaded successfully: ${CVE_COUNT} known exploited vulnerabilities"

# Display a sample of CVEs for verification
echo "Sample CVEs from catalog:"
python3 -c "
import json
with open('${KEV_PATH}') as f:
    data = json.load(f)
for v in data['vulnerabilities'][:5]:
    print(f\"  {v['cveID']}: {v['vulnerabilityName']} ({v['vendorProject']})\")
" 2>/dev/null || true

# Also copy KEV catalog inside the Wazuh manager container for agent use
echo "Copying KEV catalog into Wazuh manager container..."
docker cp "${KEV_PATH}" wazuh.manager:/tmp/cisa_kev.json 2>/dev/null || \
    echo "Warning: Could not copy KEV to container (agent can still use /tmp/cisa_kev.json on host)"

# --- Record baseline state ---

INITIAL_CDB_COUNT=0
CDB_COUNT_OUT=$(wazuh_exec "ls /var/ossec/etc/lists/ 2>/dev/null | wc -l")
if echo "$CDB_COUNT_OUT" | grep -qE '^[0-9]+$'; then
    INITIAL_CDB_COUNT=$CDB_COUNT_OUT
fi
echo "$INITIAL_CDB_COUNT" > /tmp/initial_cdb_count
echo "Baseline CDB list count: $INITIAL_CDB_COUNT"

INITIAL_RULE_COUNT=0
RULE_COUNT_OUT=$(wazuh_exec "grep -c '<rule id=' /var/ossec/etc/rules/local_rules.xml 2>/dev/null")
if echo "$RULE_COUNT_OUT" | grep -qE '^[0-9]+$'; then
    INITIAL_RULE_COUNT=$RULE_COUNT_OUT
fi
echo "$INITIAL_RULE_COUNT" > /tmp/initial_rule_count
echo "Baseline rule count: $INITIAL_RULE_COUNT"

# Baseline: vulnerability-detector wodle enabled?
INITIAL_VULN_DETECTOR=0
if wazuh_exec "grep -qE 'wodle.*vulnerability|vulnerability.*detector|syscollector' /var/ossec/etc/ossec.conf 2>/dev/null"; then
    INITIAL_VULN_DETECTOR=1
fi
echo "$INITIAL_VULN_DETECTOR" > /tmp/initial_vuln_detector
echo "Baseline vulnerability detector enabled: $INITIAL_VULN_DETECTOR"

# Record total KEV count for reference
echo "$CVE_COUNT" > /tmp/kev_total_count

# --- Record task start timestamp ---
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Launch Firefox on Wazuh dashboard
if type ensure_firefox_wazuh &>/dev/null; then
    ensure_firefox_wazuh 2>/dev/null || true
else
    su - ga -c "DISPLAY=:1 firefox --new-window 'https://localhost' &" 2>/dev/null || true
fi
sleep 3

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== CISA KEV Data Available ==="
echo "  File: ${KEV_PATH}"
echo "  Total CVEs: ${CVE_COUNT}"
echo "  Format: JSON with 'vulnerabilities' array"
echo "  Each entry has: cveID, vulnerabilityName, vendorProject, product, dateAdded"
echo "=== Setup Complete ==="
