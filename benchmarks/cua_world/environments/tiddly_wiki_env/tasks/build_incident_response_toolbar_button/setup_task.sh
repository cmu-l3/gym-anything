#!/bin/bash
echo "=== Setting up build_incident_response_toolbar_button task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure tiddlers directory exists
mkdir -p /home/ga/mywiki/tiddlers/

# Seed the wiki with real historical incident data (real CVEs)
cat > "/home/ga/mywiki/tiddlers/CVE-2021-44228.tid" << 'EOF'
created: 20211210120000000
modified: 20211210120000000
tags: [[Security Incident]]
title: CVE-2021-44228 (Log4Shell)
severity: Critical
status: Closed

# Incident Summary
Critical unauthenticated remote code execution vulnerability in log4j2. Exploited in the wild allowing attackers full system control.

# Remediation Actions
Patched log4j to version 2.15.0. Scanned all internal repositories.
EOF

cat > "/home/ga/mywiki/tiddlers/CVE-2023-34362.tid" << 'EOF'
created: 20230531120000000
modified: 20230531120000000
tags: [[Security Incident]]
title: CVE-2023-34362 (MOVEit Transfer)
severity: High
status: Closed

# Incident Summary
SQL injection vulnerability in MOVEit Transfer web application that could allow an unauthenticated attacker to gain unauthorized access to the database.

# Remediation Actions
Applied vendor patch. Cycled service accounts.
EOF

cat > "/home/ga/mywiki/tiddlers/CVE-2024-3094.tid" << 'EOF'
created: 20240329120000000
modified: 20240329120000000
tags: [[Security Incident]]
title: CVE-2024-3094 (XZ Utils Backdoor)
severity: Critical
status: Closed

# Incident Summary
Malicious code discovered in xz tools (liblzma) versions 5.6.0 and 5.6.1 that interferes with sshd authentication.

# Remediation Actions
Downgraded xz-utils to 5.4.6. Audited SSH logs for anomalous logins.
EOF

cat > "/home/ga/mywiki/tiddlers/CVE-2020-1472.tid" << 'EOF'
created: 20200811120000000
modified: 20200811120000000
tags: [[Security Incident]]
title: CVE-2020-1472 (Zerologon)
severity: Critical
status: Closed

# Incident Summary
Elevation of privilege vulnerability when an attacker establishes a vulnerable Netlogon secure channel connection to a domain controller.

# Remediation Actions
Applied August 2020 Windows security updates to all Domain Controllers.
EOF

cat > "/home/ga/mywiki/tiddlers/CVE-2014-0160.tid" << 'EOF'
created: 20140407120000000
modified: 20140407120000000
tags: [[Security Incident]]
title: CVE-2014-0160 (Heartbleed)
severity: High
status: Closed

# Incident Summary
Buffer over-read in OpenSSL cryptography library allowing read of 64KB of memory, potentially exposing private keys.

# Remediation Actions
Updated OpenSSL to 1.0.1g. Reissued SSL certificates.
EOF

chown -R ga:ga /home/ga/mywiki/tiddlers

# Restart TiddlyWiki to ensure all new tiddlers are loaded
echo "Restarting TiddlyWiki server..."
pkill -f "tiddlywiki" 2>/dev/null || true
sleep 2
su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"

# Wait for TiddlyWiki server to be ready
for i in {1..30}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki server is running"
        break
    fi
    sleep 1
done

# Ensure Firefox is open and focused
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# Refresh page to ensure seed data is visible
DISPLAY=:1 xdotool key F5
sleep 3

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="