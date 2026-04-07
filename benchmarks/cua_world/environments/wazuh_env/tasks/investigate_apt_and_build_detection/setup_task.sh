#!/bin/bash
echo "=== Setting up investigate_apt_and_build_detection task ==="

source /workspace/scripts/task_utils.sh

# 1. Delete stale outputs BEFORE recording timestamp
rm -f /home/ga/apt_report.json 2>/dev/null

# 2. Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Fix pre-existing decoder issues in the container
#    The default GymApp decoder uses unsupported OS_Regex syntax (alternation, \S+).
#    Replace it with a harmless placeholder that will never match real logs.
echo "Fixing pre-existing decoder issues..."
docker exec "${WAZUH_MANAGER_CONTAINER}" bash -c '
cat > /var/ossec/etc/decoders/local_decoder.xml << "DEOF"
<decoder name="local-placeholder">
  <prematch>^GYMAPP_PLACEHOLDER_UNUSED</prematch>
</decoder>
DEOF
' 2>/dev/null || true

# 4. Install nano in container for easier editing
#    Container is Amazon Linux (yum-based), not Debian.
echo "Installing nano in container..."
docker exec "${WAZUH_MANAGER_CONTAINER}" bash -c \
  'yum install -y nano 2>/dev/null' 2>/dev/null || true

# 5. Reset local_rules.xml to clean state
#    Must include at least one rule — an empty group causes a parse error.
echo "Resetting local_rules.xml..."
docker exec "${WAZUH_MANAGER_CONTAINER}" bash -c '
cat > /var/ossec/etc/rules/local_rules.xml << "REOF"
<group name="local,syslog,sshd,">
  <rule id="100099" level="0">
    <description>Placeholder rule for clean state.</description>
  </rule>
</group>
REOF
chown root:wazuh /var/ossec/etc/rules/local_rules.xml
chmod 660 /var/ossec/etc/rules/local_rules.xml
'

# 6. Restart manager with clean config
echo "Restarting Wazuh manager..."
restart_wazuh_manager
sleep 10

# 7. Wait for indexer
echo "Waiting for Wazuh Indexer..."
wait_for_service "Wazuh Indexer" "curl -sk -u admin:SecretPassword https://localhost:9200/_cluster/health" 120

# 8. Delete any existing test indices
echo "Cleaning existing test indices..."
for day in 10 11 12 13 14 15; do
  curl -sk -u admin:SecretPassword -X DELETE \
    "https://localhost:9200/wazuh-alerts-4.x-2025.03.${day}" 2>/dev/null || true
done

# 9. Generate alert data with inline Python
echo "Generating APT alert data..."
cat > /tmp/generate_apt_data.py << 'PYEOF'
#!/usr/bin/env python3
"""Generate realistic Wazuh alert data for an APT investigation scenario.

Attack chain:
  Day 3: SSH brute force -> initial compromise of 'deploy' on web-prod-01
  Day 4: Lateral movement to db-prod-01 -> privilege escalation -> backdoor user
  Day 5: Persistence via crontab + malicious process, backdoor login
  Day 6: Continued backdoor access
Days 1-2 and interspersed: Normal operational noise
"""
import json
import random

random.seed(42)  # Deterministic output

INDEX_PREFIX = "wazuh-alerts-4.x-2025.03"

AGENTS = {
    "web-prod-01": {"id": "001", "name": "web-prod-01", "ip": "10.0.1.15"},
    "db-prod-01":  {"id": "002", "name": "db-prod-01",  "ip": "10.0.2.22"},
}

ATTACKER_IP    = "185.220.101.33"
INITIAL_USER   = "deploy"
INITIAL_HOST   = "web-prod-01"
LATERAL_HOST   = "db-prod-01"
BACKDOOR_USER  = "sysadm1n"
JUMPBOX_IP     = "10.0.0.50"

records = []


def add(day, alert):
    records.append((f"{INDEX_PREFIX}.{day}", alert))


def ssh_ok(ts, host, srcip, user, mitre=None):
    a = AGENTS[host]
    alert = {
        "timestamp": ts,
        "rule": {
            "level": 3, "description": "sshd: authentication success.",
            "id": "5715", "firedtimes": 1, "mail": False,
            "groups": ["syslog", "sshd", "authentication_success"],
        },
        "agent": {"id": a["id"], "name": a["name"], "ip": a["ip"]},
        "manager": {"name": "wazuh-manager"},
        "decoder": {"name": "sshd"},
        "data": {"srcip": srcip, "dstuser": user,
                 "srcport": str(random.randint(40000, 60000))},
        "location": "/var/log/auth.log",
        "full_log": (f"sshd[{random.randint(10000,50000)}]: "
                     f"Accepted password for {user} from {srcip} "
                     f"port {random.randint(40000,60000)} ssh2"),
    }
    if mitre:
        alert["rule"]["mitre"] = mitre
    return alert


def ssh_fail(ts, host, srcip, user):
    a = AGENTS[host]
    return {
        "timestamp": ts,
        "rule": {
            "level": 5,
            "description": "Attempt to login using a non-existent user.",
            "id": "5710", "firedtimes": 1, "mail": False,
            "groups": ["syslog", "sshd", "invalid_login",
                       "authentication_failures"],
            "mitre": {"id": ["T1110.001"],
                      "tactic": ["Credential Access"],
                      "technique": ["Brute Force: Password Guessing"]},
        },
        "agent": {"id": a["id"], "name": a["name"], "ip": a["ip"]},
        "manager": {"name": "wazuh-manager"},
        "decoder": {"name": "sshd"},
        "data": {"srcip": srcip, "dstuser": user,
                 "srcport": str(random.randint(40000, 60000))},
        "location": "/var/log/auth.log",
        "full_log": (f"sshd[{random.randint(10000,50000)}]: "
                     f"Failed password for {user} from {srcip} "
                     f"port {random.randint(40000,60000)} ssh2"),
    }


def sudo_cmd(ts, host, user, cmd):
    a = AGENTS[host]
    return {
        "timestamp": ts,
        "rule": {
            "level": 3,
            "description": "Successful sudo to ROOT executed.",
            "id": "5402", "firedtimes": 1, "mail": False,
            "groups": ["syslog", "sudo"],
        },
        "agent": {"id": a["id"], "name": a["name"], "ip": a["ip"]},
        "manager": {"name": "wazuh-manager"},
        "decoder": {"name": "sudo"},
        "data": {"srcuser": user, "dstuser": "root"},
        "location": "/var/log/auth.log",
        "full_log": (f"sudo: {user} : TTY=pts/0 ; "
                     f"PWD=/home/{user} ; USER=root ; COMMAND={cmd}"),
    }


# ==================================================================
# DAY 1  (March 10) - Normal baseline
# ==================================================================
for t in ["08:15:00", "09:30:00", "10:45:00", "14:00:00",
          "15:30:00", "16:45:00"]:
    add("10", ssh_ok(f"2025-03-10T{t}.000+0000",
                     "web-prod-01", JUMPBOX_IP, "ga"))

for t in ["09:00:00", "11:30:00", "14:30:00", "16:00:00"]:
    add("10", sudo_cmd(f"2025-03-10T{t}.000+0000",
                       "web-prod-01", "ga", "/usr/bin/apt update"))

for t in ["07:00:00", "12:00:00", "17:00:00"]:
    add("10", ssh_ok(f"2025-03-10T{t}.000+0000",
                     "db-prod-01", JUMPBOX_IP, "dba_admin"))

# SCA noise
for host in ["web-prod-01", "db-prod-01"]:
    a = AGENTS[host]
    add("10", {
        "timestamp": "2025-03-10T06:00:00.000+0000",
        "rule": {"level": 7, "id": "19108",
                 "description": "SCA check failed: Ensure SSH "
                                "MaxAuthTries is set to 4 or less.",
                 "groups": ["sca"]},
        "agent": {"id": a["id"], "name": a["name"], "ip": a["ip"]},
        "manager": {"name": "wazuh-manager"},
        "data": {"sca": {"check": {"title": "Ensure SSH MaxAuthTries "
                                            "is set to 4 or less",
                                   "result": "failed"},
                          "policy": "CIS Benchmark for Ubuntu 22.04 LTS"}},
        "location": "sca", "decoder": {"name": "sca"},
    })


# ==================================================================
# DAY 2  (March 11) - More normal activity
# ==================================================================
for t in ["08:00:00", "10:00:00", "14:00:00", "16:00:00"]:
    add("11", ssh_ok(f"2025-03-11T{t}.000+0000",
                     "web-prod-01", JUMPBOX_IP, "deploy"))

# Package install noise
add("11", {
    "timestamp": "2025-03-11T11:00:00.000+0000",
    "rule": {"level": 7, "id": "2902",
             "description": "New dpkg (Debian Package) installed.",
             "groups": ["syslog", "dpkg"]},
    "agent": {"id": "001", "name": "web-prod-01", "ip": "10.0.1.15"},
    "manager": {"name": "wazuh-manager"},
    "data": {"package": "nginx"},
    "location": "/var/log/dpkg.log", "decoder": {"name": "dpkg"},
    "full_log": "dpkg[5432]: status installed nginx:amd64 1.24.0-2",
})

for t in ["07:30:00", "13:00:00"]:
    add("11", ssh_ok(f"2025-03-11T{t}.000+0000",
                     "db-prod-01", JUMPBOX_IP, "dba_admin"))


# ==================================================================
# DAY 3  (March 12) - ATTACK: SSH brute force -> initial compromise
# ==================================================================
# 50 brute-force attempts, one per minute starting at 08:16
for i in range(50):
    mins = 8 * 60 + 16 + i
    h, m, s = mins // 60, mins % 60, (i * 7) % 60
    ts = f"2025-03-12T{h:02d}:{m:02d}:{s:02d}.000+0000"
    add("12", ssh_fail(ts, "web-prod-01", ATTACKER_IP, INITIAL_USER))

# Successful login after brute force
add("12", ssh_ok(
    "2025-03-12T09:10:33.000+0000", "web-prod-01",
    ATTACKER_IP, INITIAL_USER,
    mitre={"id": ["T1078"],
           "tactic": ["Defense Evasion", "Initial Access"],
           "technique": ["Valid Accounts"]},
))

# Normal logins interspersed (noise)
for t in ["10:00:00", "11:00:00", "13:00:00", "15:00:00"]:
    add("12", ssh_ok(f"2025-03-12T{t}.000+0000",
                     "web-prod-01", JUMPBOX_IP, "ga"))


# ==================================================================
# DAY 4  (March 13) - LATERAL MOVEMENT + PRIVILEGE ESCALATION
# ==================================================================
# Normal morning noise
for t in ["07:00:00", "08:00:00"]:
    add("13", ssh_ok(f"2025-03-13T{t}.000+0000",
                     "web-prod-01", JUMPBOX_IP, "ga"))

# ATTACK: Lateral movement - deploy logs into db-prod-01 from
#         web-prod-01's internal IP (10.0.1.15)
add("13", ssh_ok(
    "2025-03-13T02:47:12.000+0000", "db-prod-01",
    AGENTS["web-prod-01"]["ip"], INITIAL_USER,
    mitre={"id": ["T1021.004"],
           "tactic": ["Lateral Movement"],
           "technique": ["Remote Services: SSH"]},
))

# ATTACK: Privilege escalation - sudo su to root on db-prod-01
esc = sudo_cmd("2025-03-13T02:48:05.000+0000",
               "db-prod-01", INITIAL_USER, "/bin/su -")
esc["rule"]["mitre"] = {
    "id": ["T1548.003"],
    "tactic": ["Privilege Escalation", "Defense Evasion"],
    "technique": ["Abuse Elevation Control Mechanism: "
                  "Sudo and Sudo Caching"],
}
add("13", esc)

# ATTACK: Create backdoor user sysadm1n with UID 0
add("13", {
    "timestamp": "2025-03-13T02:49:30.000+0000",
    "rule": {
        "level": 8,
        "description": "New user added to the system.",
        "id": "5902", "firedtimes": 1, "mail": False,
        "groups": ["syslog", "pam", "authentication"],
        "mitre": {"id": ["T1136.001"],
                  "tactic": ["Persistence"],
                  "technique": ["Create Account: Local Account"]},
    },
    "agent": {"id": "002", "name": "db-prod-01", "ip": "10.0.2.22"},
    "manager": {"name": "wazuh-manager"},
    "decoder": {"name": "useradd"},
    "data": {"srcuser": "root", "dstuser": BACKDOOR_USER, "uid": "0"},
    "location": "/var/log/auth.log",
    "full_log": (f"useradd[22400]: new user: name={BACKDOOR_USER}, "
                 f"UID=0, GID=0, home=/root, shell=/bin/bash"),
})

# Normal daytime noise
for t in ["09:00:00", "11:00:00", "14:00:00", "16:00:00"]:
    add("13", sudo_cmd(f"2025-03-13T{t}.000+0000",
                       "web-prod-01", "ga",
                       "/usr/bin/systemctl restart nginx"))

# FIM noise
add("13", {
    "timestamp": "2025-03-13T12:00:00.000+0000",
    "rule": {"level": 7, "id": "550",
             "description": "Integrity checksum changed.",
             "groups": ["ossec", "syscheck",
                        "syscheck_entry_modified", "syscheck_file"]},
    "agent": {"id": "001", "name": "web-prod-01", "ip": "10.0.1.15"},
    "manager": {"name": "wazuh-manager"},
    "syscheck": {"path": "/etc/nginx/nginx.conf", "event": "modified"},
    "location": "syscheck",
    "decoder": {"name": "syscheck_integrity_changed"},
})


# ==================================================================
# DAY 5  (March 14) - PERSISTENCE + BACKDOOR ACCESS
# ==================================================================
# ATTACK: sysadm1n logs in from attacker IP (confirms same attacker)
add("14", ssh_ok("2025-03-14T01:15:00.000+0000",
                 "db-prod-01", ATTACKER_IP, BACKDOOR_USER))

# ATTACK: Crontab modification (persistence via FIM)
add("14", {
    "timestamp": "2025-03-14T01:17:22.000+0000",
    "rule": {
        "level": 7,
        "description": "File added to the system.",
        "id": "554", "firedtimes": 1, "mail": False,
        "groups": ["ossec", "syscheck",
                   "syscheck_entry_added", "syscheck_file"],
        "mitre": {"id": ["T1053.003"],
                  "tactic": ["Execution", "Persistence",
                             "Privilege Escalation"],
                  "technique": ["Scheduled Task/Job: Cron"]},
    },
    "agent": {"id": "002", "name": "db-prod-01", "ip": "10.0.2.22"},
    "manager": {"name": "wazuh-manager"},
    "syscheck": {"path": "/var/spool/cron/crontabs/root",
                 "event": "added",
                 "diff": ("* * * * * /tmp/.cache/sshd "
                          "--daemon >/dev/null 2>&1")},
    "location": "syscheck",
    "decoder": {"name": "syscheck_new_entry"},
})

# ATTACK: Suspicious process from /tmp
add("14", {
    "timestamp": "2025-03-14T01:18:00.000+0000",
    "rule": {
        "level": 12,
        "description": "Process execution from /tmp directory detected.",
        "id": "100150", "firedtimes": 1, "mail": True,
        "groups": ["local", "process_monitor"],
        "mitre": {"id": ["T1059"],
                  "tactic": ["Execution"],
                  "technique": ["Command and Scripting Interpreter"]},
    },
    "agent": {"id": "002", "name": "db-prod-01", "ip": "10.0.2.22"},
    "manager": {"name": "wazuh-manager"},
    "decoder": {"name": "auditd"},
    "data": {"process": {"name": "/tmp/.cache/sshd",
                         "pid": "23200", "ppid": "1", "user": "root"}},
    "location": "/var/log/audit/audit.log",
    "full_log": ("type=EXECVE msg=audit(1710378000.000:100): "
                 "argc=2 a0=\"/tmp/.cache/sshd\" a1=\"--daemon\""),
})

# Normal daytime noise
for t in ["08:00:00", "09:00:00", "10:00:00", "14:00:00", "16:00:00"]:
    add("14", ssh_ok(f"2025-03-14T{t}.000+0000",
                     "web-prod-01", JUMPBOX_IP, "ga"))

for t in ["09:30:00", "14:30:00"]:
    add("14", sudo_cmd(f"2025-03-14T{t}.000+0000",
                       "db-prod-01", "dba_admin",
                       "/usr/bin/pg_dump mydb"))


# ==================================================================
# DAY 6  (March 15) - Continued backdoor access
# ==================================================================
# ATTACK: sysadm1n logs in again
add("15", ssh_ok("2025-03-15T03:22:00.000+0000",
                 "db-prod-01", ATTACKER_IP, BACKDOOR_USER))

# Normal activity
for t in ["08:00:00", "10:00:00", "14:00:00"]:
    add("15", ssh_ok(f"2025-03-15T{t}.000+0000",
                     "web-prod-01", JUMPBOX_IP, "ga"))


# ==================================================================
# OUTPUT
# ==================================================================
with open("/tmp/apt_bulk_data.json", "w") as f:
    for idx_name, alert in records:
        f.write(json.dumps({"index": {"_index": idx_name}}) + "\n")
        f.write(json.dumps(alert) + "\n")

# Hidden ground truth for verifier (not accessible to agent)
ground_truth = {
    "attacker_ip": ATTACKER_IP,
    "compromised_account": INITIAL_USER,
    "compromised_host": INITIAL_HOST,
    "lateral_movement_target": LATERAL_HOST,
    "privilege_escalation_method":
        "sudo su to root, created backdoor user sysadm1n with UID 0",
    "persistence_mechanism":
        "crontab entry executing /tmp/.cache/sshd",
    "total_alerts": len(records),
}
with open("/tmp/apt_ground_truth.json", "w") as f:
    json.dump(ground_truth, f, indent=2)

print(f"Generated {len(records)} alert records")
PYEOF

python3 /tmp/generate_apt_data.py

# 10. Inject data into OpenSearch
echo "Injecting APT alert data into Wazuh Indexer..."
curl -sk -u admin:SecretPassword -X POST "https://localhost:9200/_bulk" \
    -H "Content-Type: application/json" \
    --data-binary @/tmp/apt_bulk_data.json > /dev/null 2>&1

# Refresh indices to make data searchable immediately
curl -sk -u admin:SecretPassword -X POST \
    "https://localhost:9200/wazuh-alerts-*/_refresh" > /dev/null 2>&1

echo "Data injection complete."

# 11. Protect ground truth
chmod 600 /tmp/apt_ground_truth.json

# 12. Open Firefox to Wazuh Dashboard
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 2
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 13. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
