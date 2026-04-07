#!/bin/bash
echo "=== Setting up enrich_with_threat_intel task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# 2. Record baselines to detect newly created artifacts
echo "Recording baseline artifacts..."

# Record baseline lookup table files
curl -sk -u "admin:SplunkAdmin1!" \
    "https://localhost:8089/servicesNS/-/-/data/lookup-table-files?output_mode=json&count=0" 2>/dev/null | \
    python3 -c "import sys, json; print(json.dumps([e.get('name', '') for e in json.load(sys.stdin).get('entry', [])]))" \
    > /tmp/baseline_lookups.json 2>/dev/null || echo "[]" > /tmp/baseline_lookups.json

# Record baseline lookup definitions
curl -sk -u "admin:SplunkAdmin1!" \
    "https://localhost:8089/servicesNS/-/-/data/transforms/lookups?output_mode=json&count=0" 2>/dev/null | \
    python3 -c "import sys, json; print(json.dumps([e.get('name', '') for e in json.load(sys.stdin).get('entry', [])]))" \
    > /tmp/baseline_defs.json 2>/dev/null || echo "[]" > /tmp/baseline_defs.json

# Record baseline saved searches
curl -sk -u "admin:SplunkAdmin1!" \
    "https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0" 2>/dev/null | \
    python3 -c "import sys, json; print(json.dumps([e.get('name', '') for e in json.load(sys.stdin).get('entry', [])]))" \
    > /tmp/baseline_searches.json 2>/dev/null || echo "[]" > /tmp/baseline_searches.json

echo "$(date +%s)" > /tmp/task_start_timestamp

# 3. Generate the Threat Intelligence CSV Feed
# We inject a few realistic IPs and attempt to extract some actual IPs from auth.log so lookups will succeed.
echo "Generating threat intelligence CSV feed..."
mkdir -p /home/ga/Documents

cat > /home/ga/Documents/threat_intel_feed.csv << 'EOF'
ip,threat_category,severity,threat_actor,first_seen,last_seen,description
203.0.113.50,brute_force,critical,APT28,2024-01-15,2025-03-20,SSH brute force attack source
185.220.101.1,tor_exit,high,TOR_Network,2023-01-01,2025-06-01,Known Tor exit node
116.31.116.50,brute_force,high,Unknown,2024-08-15,2025-04-22,Persistent SSH brute force source
192.168.1.100,internal_compromise,critical,Insider,2024-10-01,2025-01-01,Compromised internal host
EOF

# Extract up to 5 real IPs from the auth.log data to make the enrichment work perfectly
if [ -f /opt/splunk_data/security/auth.log ]; then
    grep "Failed password" /opt/splunk_data/security/auth.log | grep -oP 'from \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort | uniq | head -n 5 | while read -r ip; do
        echo "$ip,brute_force,critical,Automated_Bot,2024-11-01,2025-02-01,Extracted active threat from auth logs" >> /home/ga/Documents/threat_intel_feed.csv
    done
fi

chown ga:ga /home/ga/Documents/threat_intel_feed.csv
chmod 644 /home/ga/Documents/threat_intel_feed.csv

# 4. Ensure Firefox is running with Splunk visible
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    exit 1
fi

sleep 3
take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup complete ==="