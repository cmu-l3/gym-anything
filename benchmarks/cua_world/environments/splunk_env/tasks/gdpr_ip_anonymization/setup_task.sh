#!/bin/bash
echo "=== Setting up gdpr_ip_anonymization task ==="

source /workspace/scripts/task_utils.sh

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Ensure a clean state to prevent false positives/gaming
echo "Cleaning up any pre-existing artifacts..."
curl -sk -u admin:SplunkAdmin1! -X DELETE "https://localhost:8089/services/data/indexes/gdpr_logs" 2>/dev/null || true
curl -sk -u admin:SplunkAdmin1! -X DELETE "https://localhost:8089/services/configs/conf-props/apache_gdpr" 2>/dev/null || true
curl -sk -u admin:SplunkAdmin1! -X DELETE "https://localhost:8089/servicesNS/admin/search/saved/searches/Anonymized_Traffic_Report" 2>/dev/null || true

# Remove manual file additions in case of residual data
if [ -f /opt/splunk/etc/system/local/props.conf ]; then
    sed -i '/\[apache_gdpr\]/,/^\[/d' /opt/splunk/etc/system/local/props.conf 2>/dev/null || true
fi

# Reload splunk config to clear memory caches
curl -sk -u admin:SplunkAdmin1! -X POST "https://localhost:8089/services/admin/cacheman/_reload" 2>/dev/null || true

# Record task start time
echo "$(date +%s)" > /tmp/task_start_timestamp

# Ensure Firefox is running with Splunk visible BEFORE task starts
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

sleep 3
take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup complete ==="