#!/bin/bash
set -e
echo "=== Setting up IT Security Audit Report Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. create documents directory
sudo -u ga mkdir -p /home/ga/Documents

# 2. Clean up previous run artifacts
rm -f /home/ga/Documents/Apex_Security_Report_Q1_2025.odt 2>/dev/null || true
rm -f /home/ga/Documents/scan_results.json 2>/dev/null || true

# 3. Create the input data file (scan_results.json)
cat > /home/ga/Documents/scan_results.json << 'JSONEOF'
{
  "assessment_info": {
    "client": "Apex Healthcare Systems",
    "date": "2025-03-15",
    "scope": "Internal Network (192.168.10.0/24)",
    "auditor": "Security Operations Team"
  },
  "findings": [
    {
      "id": "VULN-001",
      "name": "Apache Log4j Remote Code Execution",
      "cvss": 9.8,
      "severity": "Critical",
      "description": "The application is using a vulnerable version of Log4j which allows remote code execution via JNDI injection.",
      "remediation": "Upgrade Log4j to version 2.17.1 or higher immediately."
    },
    {
      "id": "VULN-002",
      "name": "TLS 1.0/1.1 Protocol Enabled",
      "cvss": 5.4,
      "severity": "Medium",
      "description": "Obsolete TLS protocols are enabled on the web server, which may allow downgrade attacks.",
      "remediation": "Disable TLS 1.0 and 1.1. Enable TLS 1.2 and 1.3 only."
    },
    {
      "id": "VULN-003",
      "name": "Missing HTTP Security Headers",
      "cvss": 2.8,
      "severity": "Low",
      "description": "The web server response is missing X-Frame-Options and Content-Security-Policy headers.",
      "remediation": "Configure the web server to send appropriate security headers."
    },
    {
      "id": "VULN-004",
      "name": "OpenSSL Heartbleed Vulnerability",
      "cvss": 7.5,
      "severity": "High",
      "description": "The remote service is affected by an information disclosure vulnerability in the OpenSSL library.",
      "remediation": "Upgrade OpenSSL to the latest patched version and regenerate SSL keys."
    },
    {
      "id": "VULN-005",
      "name": "Default Administrator Credentials",
      "cvss": 9.1,
      "severity": "Critical",
      "description": "The management interface is accessible using default 'admin/admin' credentials.",
      "remediation": "Change the default password immediately and enforce a strong password policy."
    }
  ]
}
JSONEOF

chown ga:ga /home/ga/Documents/scan_results.json
chmod 644 /home/ga/Documents/scan_results.json

# 4. Record initial state
date +%s > /tmp/task_start_time.txt
ls -l /home/ga/Documents/ > /tmp/initial_file_list.txt

# 5. Launch OpenOffice Writer (Blank Document)
echo "Starting OpenOffice Writer..."
if ! pgrep -f "soffice" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice Writer"; then
            echo "OpenOffice Writer window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize window
DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenOffice Writer" 2>/dev/null || true

# Dismiss any startup dialogs (like recovery or registration)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="