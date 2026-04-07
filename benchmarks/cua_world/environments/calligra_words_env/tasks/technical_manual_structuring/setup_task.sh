#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Technical Manual Structuring Task ==="

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents

rm -f /home/ga/Documents/netwatch_manual.odt

# ------------------------------------------------------------------
# Create the unformatted NetWatch Pro manual using odfpy
# ALL content is plain P elements — no heading styles, no tables,
# no bold, no monospace — everything is plain paragraphs.
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()


def add(text=""):
    doc.text.addElement(P(text=text))


# ── Title page elements (plain paragraphs, no styles) ──
add("NetWatch Pro v3.2")
add("Administrator Manual")
add("Nexus Systems Corp.")
add("Version 3.2 — Release Date: September 2025")
add("Document Classification: Internal Use Only")
add("")

# ── Introduction ──
add("Introduction")
add(
    "NetWatch Pro is an enterprise-grade network monitoring and management "
    "platform designed for organizations with complex, multi-site network "
    "infrastructure. It provides real-time visibility into network health, "
    "performance metrics, bandwidth utilization, and security events across "
    "heterogeneous environments including on-premises, cloud, and hybrid "
    "deployments."
)
add(
    "NetWatch Pro v3.2 introduces enhanced SNMP v3 support, a redesigned "
    "alerting engine, REST API improvements, and support for monitoring "
    "containerized workloads via Kubernetes integration."
)
add(
    "This manual covers installation, configuration, day-to-day operation, "
    "and troubleshooting of NetWatch Pro. It is intended for network "
    "administrators, system engineers, and IT operations staff responsible "
    "for network infrastructure management."
)
add("")

# ── System Requirements ──
add("System Requirements")

add("Hardware Requirements")
add(
    "The following minimum hardware specifications are required for a "
    "standard deployment supporting up to 500 monitored devices:"
)
add("Component: CPU — Minimum: 4 cores (x86_64) — Recommended: 8 cores")
add("Component: RAM — Minimum: 8 GB — Recommended: 16 GB")
add("Component: Disk — Minimum: 100 GB SSD — Recommended: 500 GB NVMe SSD")
add("Component: Network — Minimum: 1 Gbps — Recommended: 10 Gbps")
add(
    "For large-scale deployments (500-5000 devices), multiply RAM and disk "
    "requirements by the scaling factor: devices/500, rounded up."
)
add("")

add("Software Requirements")
add(
    "Operating System: Red Hat Enterprise Linux 8/9, Ubuntu Server "
    "20.04/22.04, or Windows Server 2019/2022"
)
add("Database: PostgreSQL 14 or later (bundled with installer)")
add("Runtime: Java 17 LTS (bundled with installer)")
add(
    "Browser: Chrome 90+, Firefox 88+, or Edge 90+ for the web console"
)
add("")

# ── Installation ──
add("Installation")

add("Linux Installation")
add(
    "Step 1: Download the installation package from the Nexus Systems "
    "customer portal."
)
add(
    "Step 2: Extract the archive: tar -xzf "
    "netwatch-pro-3.2-linux-x64.tar.gz"
)
add(
    "Step 3: Run the installer with root privileges: "
    "sudo ./install.sh --accept-license"
)
add(
    "Step 4: Initialize the database: "
    "nw-dbinit --create --admin-password=<your_password>"
)
add("Step 5: Start the service: sudo systemctl start netwatch")
add("Step 6: Verify the installation: netwatch --version")
add(
    "The web console will be available at https://localhost:8443 after "
    "startup."
)
add("")

add("Windows Installation")
add("Step 1: Run the MSI installer: netwatch-pro-3.2-win-x64.msi")
add(
    "Step 2: Follow the installation wizard. Accept the default "
    "installation directory (C:\\Program Files\\NetWatch Pro)."
)
add(
    "Step 3: The installer will automatically configure the PostgreSQL "
    "database and Windows service."
)
add(
    "Step 4: Open a browser and navigate to https://localhost:8443 to "
    "access the web console."
)
add("")

# ── Configuration ──
add("Configuration")

add("Global Configuration")
add(
    "NetWatch Pro stores its configuration in /etc/netwatch/nw.conf "
    "(Linux) or C:\\ProgramData\\NetWatch\\nw.conf (Windows). The "
    "following parameters control core behavior:"
)
add(
    "Parameter: nw.scan.interval — Default: 300 — Unit: seconds — "
    "Description: Interval between automatic network discovery scans"
)
add(
    "Parameter: nw.scan.timeout — Default: 30 — Unit: seconds — "
    "Description: Timeout for individual device probe"
)
add(
    "Parameter: nw.data.retention — Default: 90 — Unit: days — "
    "Description: Number of days to retain historical monitoring data"
)
add(
    "Parameter: nw.alert.threshold — Default: 3 — Unit: count — "
    "Description: Number of consecutive failures before triggering an alert"
)
add(
    "Parameter: nw.snmp.version — Default: v2c — Unit: — — "
    "Description: Default SNMP protocol version"
)
add(
    "Parameter: nw.api.port — Default: 8443 — Unit: — — "
    "Description: HTTPS port for web console and REST API"
)
add(
    "Parameter: nw.log.level — Default: INFO — Unit: — — "
    "Description: Logging verbosity (DEBUG, INFO, WARN, ERROR)"
)
add(
    "Configure alert thresholds to match your organization's SLA "
    "requirements. A lower nw.alert.threshold value means faster alerting "
    "but may increase false positives."
)
add("")

add("Alert Configuration")
add(
    "Alerts are configured through the web console under Settings > "
    "Alerts, or via the REST API. Each alert rule consists of a condition "
    "(metric threshold), a scope (device group or individual device), and "
    "one or more notification channels (email, Slack, PagerDuty, webhook)."
)
add(
    "To create a custom alert for bandwidth utilization: Navigate to "
    "Settings > Alerts > New Rule. Set Metric to 'bandwidth_utilization', "
    "Operator to 'greater_than', Threshold to 85 (percent). Select the "
    "target device group and notification channel."
)
add(
    "NetWatch Pro supports alert correlation to reduce noise. When "
    "multiple related alerts fire within a configurable time window "
    "(default: 5 minutes), they are automatically grouped into a single "
    "incident."
)
add("")

# ── Command Reference ──
add("Command Reference")

add("Network Discovery Commands")
add(
    "netwatch --discover --subnet 192.168.1.0/24 — Discover all devices "
    "on the specified subnet"
)
add(
    "netwatch --discover --range 10.0.0.1-10.0.0.254 — Discover devices "
    "in an IP range"
)
add(
    "netwatch --discover --file hosts.txt — Discover devices listed in a "
    "text file (one IP per line)"
)
add(
    "netwatch --discover --snmp-community public — Use a specific SNMP "
    "community string for discovery"
)
add("")

add("Monitoring Commands")
add(
    "netwatch --monitor --device 192.168.1.1 --metrics cpu,memory,"
    "bandwidth — Monitor specific metrics on a device"
)
add(
    "netwatch --monitor --group servers --interval 60 — Monitor all "
    "devices in the 'servers' group every 60 seconds"
)
add(
    "nw-config --set nw.scan.interval=120 — Change a configuration "
    "parameter at runtime"
)
add(
    "nw-config --get nw.alert.threshold — View the current value of a "
    "configuration parameter"
)
add("nw-service restart — Restart all NetWatch Pro services")
add("nw-service status — Display the status of all NetWatch Pro services")
add("")

# ── Troubleshooting ──
add("Troubleshooting")

add("Common Error Codes")
add(
    "Error Code: E001 — Meaning: Device unreachable — Cause: Target "
    "device is not responding to ICMP or SNMP probes — Resolution: Verify "
    "network connectivity, check firewall rules, confirm device is "
    "powered on"
)
add(
    "Error Code: E002 — Meaning: SNMP authentication failure — Cause: "
    "Incorrect SNMP community string or credentials — Resolution: Verify "
    "SNMP configuration on the target device and in NetWatch Pro"
)
add(
    "Error Code: E003 — Meaning: Database connection lost — Cause: "
    "PostgreSQL service is down or unreachable — Resolution: Check "
    "PostgreSQL service status, verify database connection parameters "
    "in nw.conf"
)
add(
    "Error Code: E004 — Meaning: License expired — Cause: The NetWatch "
    "Pro license has expired — Resolution: Contact Nexus Systems sales "
    "to renew your license"
)
add(
    "Error Code: E005 — Meaning: Disk space critical — Cause: Available "
    "disk space has fallen below 10% — Resolution: Reduce data retention "
    "period or add storage capacity"
)
add("")

add("Performance Tuning")
add(
    "The discovery engine uses a combination of ICMP echo requests and "
    "SNMP queries to identify devices. For large networks (>1000 devices), "
    "increase the scan timeout (nw.scan.timeout) to 60 seconds and reduce "
    "concurrent scan threads (nw.scan.threads) to 4 to prevent network "
    "congestion."
)
add(
    "Database performance can be improved by increasing PostgreSQL "
    "shared_buffers to 25% of available RAM and enabling query parallelism "
    "with max_parallel_workers_per_gather=4."
)
add("")

# ── API Reference ──
add("API Reference")
add(
    "NetWatch Pro exposes a REST API at https://<server>:8443/api/v3/. "
    "All API requests require authentication via Bearer token."
)
add(
    "GET /api/v3/devices — List all monitored devices. Returns a JSON "
    "payload with device name, IP address, status, and last-seen timestamp."
)
add(
    "GET /api/v3/devices/{id}/metrics?period=24h — Retrieve metrics for a "
    "specific device over the specified time period."
)
add(
    "POST /api/v3/alerts/rules — Create a new alert rule. Request body "
    "must be a JSON payload containing the rule definition."
)
add("DELETE /api/v3/devices/{id} — Remove a device from monitoring.")
add(
    "PUT /api/v3/config/{key} — Update a configuration parameter via the "
    "API."
)
add(
    "Response codes: 200 OK, 201 Created, 400 Bad Request, "
    "401 Unauthorized, 404 Not Found, 500 Internal Server Error."
)
add("")

# ── Appendix ──
add("Appendix")
add(
    "Supported SNMP MIBs: IF-MIB, HOST-RESOURCES-MIB, UCD-SNMP-MIB, "
    "ENTITY-MIB, CISCO-ENVMON-MIB, HP-ICF-MIB"
)
add(
    "Default ports: 8443 (HTTPS/API), 162 (SNMP Trap receiver), "
    "514 (Syslog receiver), 5432 (PostgreSQL)"
)
add(
    "Log file locations: Linux — /var/log/netwatch/, Windows — "
    "C:\\ProgramData\\NetWatch\\logs\\"
)

doc.save("/home/ga/Documents/netwatch_manual.odt", False)
print("Created netwatch_manual.odt with all plain paragraphs (no formatting)")
PYEOF

# ------------------------------------------------------------------
# Set ownership
# ------------------------------------------------------------------
chown ga:ga /home/ga/Documents/netwatch_manual.odt
chmod 0664 /home/ga/Documents/netwatch_manual.odt

# ------------------------------------------------------------------
# Launch Calligra Words with the manual
# ------------------------------------------------------------------
echo "Launching Calligra Words..."
launch_calligra_document "/home/ga/Documents/netwatch_manual.odt" "/tmp/calligra_words_task.log"

if ! wait_for_process "/usr/bin/calligrawords" 20; then
    wait_for_process "calligrawords" 15 || true
fi

if ! wait_for_window "Calligra Words\\|netwatch_manual" 60; then
    echo "ERROR: Calligra Words window did not appear"
    cat /tmp/calligra_words_task.log || true
fi

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
    safe_xdotool ga :1 key Escape || true
    sleep 0.5
    safe_xdotool ga :1 key ctrl+Home || true
fi

take_screenshot /tmp/calligra_technical_manual_structuring_setup.png

echo "=== Technical Manual Structuring Task Setup Complete ==="
