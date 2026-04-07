#!/usr/bin/env bash
# setup_task.sh — pre_task hook for threat_intel_enrichment_pipeline
# Cleans up any pre-existing artifacts, records baselines, ensures Splunk + Firefox ready.

set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "[setup] Starting threat_intel_enrichment_pipeline setup..."

# ── 1. Ensure Splunk is running ──────────────────────────────────────────────
if ! splunk_is_running; then
    echo "[setup] Splunk not running, starting..."
    /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt
    sleep 10
fi

# ── 2. Anti-gaming: delete any pre-existing artifacts ────────────────────────
# Delete lookup file
rm -f /opt/splunk/etc/apps/search/lookups/threat_intel.csv
rm -f /opt/splunk/etc/apps/launcher/lookups/threat_intel.csv

# Delete lookup definition (transforms.conf entries)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    -X DELETE "${SPLUNK_API}/servicesNS/admin/search/data/transforms/lookups/threat_intel_lookup" \
    2>/dev/null || true

# Delete automatic lookup (props.conf entries)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    -X DELETE "${SPLUNK_API}/servicesNS/admin/search/data/props/lookups/linux_secure%20%3A%20LOOKUP-threat_auto_enrich" \
    2>/dev/null || true
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    -X DELETE "${SPLUNK_API}/servicesNS/admin/search/data/props/lookups/threat_auto_enrich" \
    2>/dev/null || true

# Delete target dashboard
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    -X DELETE "${SPLUNK_API}/servicesNS/admin/search/data/ui/views/threat_intelligence_monitor" \
    2>/dev/null || true
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    -X DELETE "${SPLUNK_API}/servicesNS/admin/search/data/ui/views/Threat_Intelligence_Monitor" \
    2>/dev/null || true

# Delete target alert
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    -X DELETE "${SPLUNK_API}/servicesNS/admin/search/saved/searches/Critical_Threat_Activity" \
    2>/dev/null || true
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    -X DELETE "${SPLUNK_API}/servicesNS/admin/search/saved/searches/critical_threat_activity" \
    2>/dev/null || true

# ── 2b. Ensure field extractions exist for src_ip and user ────────────────
# In a real SOC environment, the Splunk_TA_nix add-on provides these.
# We create them here so the agent can use src_ip/user fields directly.
echo "[setup] Ensuring src_ip and user field extractions for linux_secure..."

PROPS_DIR="/opt/splunk/etc/apps/search/local"
PROPS_FILE="${PROPS_DIR}/props.conf"
mkdir -p "$PROPS_DIR"

# Write both linux_secure and syslog extractions (SSH data may be ingested as either)
# Only write if not already present
if ! grep -q "EXTRACT-src_ip" "$PROPS_FILE" 2>/dev/null; then
    cat > "$PROPS_FILE" << 'PROPSEOF'
[linux_secure]
EXTRACT-src_ip = from\s(?<src_ip>\d+\.\d+\.\d+\.\d+)\sport
EXTRACT-ssh_user = (?:for|user)\s(?:invalid user\s)?(?<user>\S+)\sfrom

[syslog]
EXTRACT-src_ip = from\s(?<src_ip>\d+\.\d+\.\d+\.\d+)\sport
EXTRACT-ssh_user = (?:for|user)\s(?:invalid user\s)?(?<user>\S+)\sfrom
PROPSEOF
    chown -R splunk:splunk "$PROPS_DIR" 2>/dev/null || true
    echo "[setup] Field extractions added. Reloading Splunk config..."
    /opt/splunk/bin/splunk reload deploy-server 2>/dev/null || true
    sleep 3
else
    echo "[setup] Field extractions already exist."
fi

# ── 3. Record baselines (for diff-based verification) ───────────────────────
echo "[setup] Recording baselines..."

# Baseline saved searches
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/saved/searches?output_mode=json&count=0" \
    -o /tmp/tiep_initial_saved_searches.json 2>/dev/null || echo '{"entry":[]}' > /tmp/tiep_initial_saved_searches.json

# Baseline dashboards
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/data/ui/views?output_mode=json&count=0" \
    -o /tmp/tiep_initial_dashboards.json 2>/dev/null || echo '{"entry":[]}' > /tmp/tiep_initial_dashboards.json

# Baseline lookup definitions
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/data/transforms/lookups?output_mode=json&count=0" \
    -o /tmp/tiep_initial_lookup_defs.json 2>/dev/null || echo '{"entry":[]}' > /tmp/tiep_initial_lookup_defs.json

# ── 4. Record task start timestamp ──────────────────────────────────────────
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start timestamp: $(cat /tmp/task_start_timestamp)"

# ── 5. Ensure Firefox with Splunk is visible ─────────────────────────────────
ensure_firefox_with_splunk 120
if [ $? -ne 0 ]; then
    echo "[setup] ERROR: Could not verify Firefox with Splunk. Exiting."
    exit 1
fi
sleep 3

# ── 6. Take start screenshot ────────────────────────────────────────────────
take_screenshot /tmp/task_start_screenshot.png

echo "[setup] Setup complete. Environment ready for threat_intel_enrichment_pipeline task."
