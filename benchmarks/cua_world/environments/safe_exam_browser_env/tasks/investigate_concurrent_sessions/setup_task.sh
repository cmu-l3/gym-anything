#!/bin/bash
set -euo pipefail

echo "=== Setting up investigate_concurrent_sessions task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Create the dynamic DB injection script
cat > /tmp/inject_sessions.py << 'PYEOF'
import subprocess
import sys
import time

def run_sql(query):
    try:
        result = subprocess.run(
            ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
             '-psebserver123', 'SEBServer', '-N', '-e', query],
            capture_output=True, text=True, timeout=10
        )
        return result.stdout.strip()
    except Exception as e:
        print(f"SQL Error: {e}")
        return ""

print("Injecting target user 'alex_rogue'...")
# 1. Ensure user exists
run_sql("INSERT INTO user (username, name, surname, email, active) VALUES ('alex_rogue', 'Alex', 'Rogue', 'alex@university.edu', 1) ON DUPLICATE KEY UPDATE active=1;")
user_id = run_sql("SELECT id FROM user WHERE username='alex_rogue' LIMIT 1")

if not user_id:
    print("Failed to create/find user!")
    sys.exit(1)

# 2. Dynamically find session/monitoring table
tables = run_sql("SHOW TABLES").split('\n')
session_table = None
ip_col = None
user_col = None

for t in tables:
    if any(keyword in t.lower() for keyword in ['session', 'connection', 'monitoring', 'client_log']):
        cols = run_sql(f"SHOW COLUMNS FROM {t}").split('\n')
        col_names = [c.split('\t')[0] for c in cols if c]
        
        # Look for an IP column
        for c in col_names:
            if 'ip' in c.lower() or 'address' in c.lower():
                ip_col = c
                break
                
        if ip_col:
            session_table = t
            # Look for a user reference
            for c in col_names:
                if 'user' in c.lower() or 'client' in c.lower():
                    user_col = c
                    break
            break

if session_table and ip_col:
    print(f"Found target table: {session_table} (IP col: {ip_col}, User col: {user_col})")
    
    # 3. Inject the expected IPs
    ip1 = "192.168.100.42"
    ip2 = "10.0.55.201"
    
    if user_col:
        run_sql(f"INSERT INTO {session_table} ({user_col}, {ip_col}) VALUES ('{user_id}', '{ip1}');")
        run_sql(f"INSERT INTO {session_table} ({user_col}, {ip_col}) VALUES ('{user_id}', '{ip2}');")
    else:
        # Fallback if no direct user col, just insert the IPs into the table so they are visible
        run_sql(f"INSERT INTO {session_table} ({ip_col}) VALUES ('{ip1}');")
        run_sql(f"INSERT INTO {session_table} ({ip_col}) VALUES ('{ip2}');")
        
    print("Forensic data injected successfully.")
else:
    print("Could not find suitable session table. Task relies on UI fallback.")
PYEOF

# Run the injection
python3 /tmp/inject_sessions.py

# Launch Firefox and log in
launch_firefox "${SEB_SERVER_URL}"
sleep 5
login_seb_server "super-admin" "admin"
sleep 3

# Make sure Documents directory exists
su - ga -c "mkdir -p /home/ga/Documents"
# Ensure the file doesn't exist from a previous run
rm -f /home/ga/Documents/rogue_ips.txt

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="