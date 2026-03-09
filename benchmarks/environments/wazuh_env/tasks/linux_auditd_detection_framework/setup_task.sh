#!/bin/bash
# Setup script for linux_auditd_detection_framework
# Creates realistic audit.log events and records baseline state.

echo "=== Setting up linux_auditd_detection_framework ==="

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

# --- Record baseline state ---

INITIAL_DECODER_COUNT=0
DEC_COUNT_OUT=$(wazuh_exec "grep -c '<decoder name=' /var/ossec/etc/decoders/local_decoder.xml 2>/dev/null")
if echo "$DEC_COUNT_OUT" | grep -qE '^[0-9]+$'; then
    INITIAL_DECODER_COUNT=$DEC_COUNT_OUT
fi
echo "$INITIAL_DECODER_COUNT" > /tmp/initial_decoder_count
echo "Baseline decoder count: $INITIAL_DECODER_COUNT"

INITIAL_RULE_COUNT=0
RULE_COUNT_OUT=$(wazuh_exec "grep -c '<rule id=' /var/ossec/etc/rules/local_rules.xml 2>/dev/null")
if echo "$RULE_COUNT_OUT" | grep -qE '^[0-9]+$'; then
    INITIAL_RULE_COUNT=$RULE_COUNT_OUT
fi
echo "$INITIAL_RULE_COUNT" > /tmp/initial_rule_count
echo "Baseline rule count: $INITIAL_RULE_COUNT"

INITIAL_CDB_COUNT=0
CDB_COUNT_OUT=$(wazuh_exec "ls /var/ossec/etc/lists/ 2>/dev/null | wc -l")
if echo "$CDB_COUNT_OUT" | grep -qE '^[0-9]+$'; then
    INITIAL_CDB_COUNT=$CDB_COUNT_OUT
fi
echo "$INITIAL_CDB_COUNT" > /tmp/initial_cdb_count
echo "Baseline CDB list count: $INITIAL_CDB_COUNT"

# --- Create realistic audit.log with real auditd format events ---
# These are real Linux kernel audit log format entries (man 8 auditd, man 7 audit.rules)
# Representing actual TTPs: T1548.003 (sudo abuse), T1003.008 (/etc/shadow access)

echo "Creating audit.log with real-format security events..."

wazuh_exec "mkdir -p /var/log/audit"
wazuh_exec "cat > /var/log/audit/audit.log << 'AUDITEOF'
type=SYSCALL msg=audit(1706823600.123:1001): arch=c000003e syscall=59 success=yes exit=0 a0=55a1234 a1=7fff5678 a2=7fff9abc a3=0 items=2 ppid=2341 pid=2342 auid=1000 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=pts0 ses=3 comm=\"sudo\" exe=\"/usr/bin/sudo\" key=\"privilege_escalation\"
type=EXECVE msg=audit(1706823600.123:1001): argc=3 a0=\"sudo\" a1=\"-s\" a2=\"/bin/bash\"
type=PATH msg=audit(1706823600.123:1001): item=0 name=\"/usr/bin/sudo\" inode=786564 dev=fd:00 mode=0104111 ouid=0 ogid=0 rdev=00:00 nametype=NORMAL
type=SYSCALL msg=audit(1706823600.456:1002): arch=c000003e syscall=2 success=yes exit=3 a0=55b5678 a1=0 a2=1b6 a3=0 items=1 ppid=2342 pid=2343 auid=1000 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=pts0 ses=3 comm=\"cat\" exe=\"/bin/cat\" key=\"credential_access\"
type=PATH msg=audit(1706823600.456:1002): item=0 name=\"/etc/shadow\" inode=655361 dev=fd:00 mode=0100640 ouid=0 ogid=42 rdev=00:00 nametype=NORMAL
type=SYSCALL msg=audit(1706823600.789:1003): arch=c000003e syscall=105 success=yes exit=0 a0=0 a1=0 a2=0 a3=0 items=0 ppid=1 pid=2344 auid=1001 uid=1001 gid=1001 euid=0 suid=0 fsuid=0 egid=1001 sgid=0 fsgid=0 tty=(none) ses=4 comm=\"pkexec\" exe=\"/usr/bin/pkexec\" key=\"setuid_escalation\"
type=SYSCALL msg=audit(1706823601.001:1004): arch=c000003e syscall=59 success=yes exit=0 a0=7f1234 a1=7fff2345 a2=7fff6789 a3=0 items=1 ppid=2344 pid=2345 auid=1001 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4 comm=\"bash\" exe=\"/bin/bash\" key=\"suspicious_exec\"
type=EXECVE msg=audit(1706823601.001:1004): argc=2 a0=\"bash\" a1=\"-i\"
type=SYSCALL msg=audit(1706823601.234:1005): arch=c000003e syscall=2 success=yes exit=4 a0=7ffa1234 a1=0 a2=1b6 a3=0 items=1 ppid=2345 pid=2346 auid=1001 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4 comm=\"cat\" exe=\"/bin/cat\" key=\"credential_access\"
type=PATH msg=audit(1706823601.234:1005): item=0 name=\"/etc/passwd\" inode=655362 dev=fd:00 mode=0100644 ouid=0 ogid=0 rdev=00:00 nametype=NORMAL
AUDITEOF"

echo "Audit log created with $(wazuh_exec "wc -l < /var/log/audit/audit.log 2>/dev/null || echo 0") lines"

# Also check that Wazuh is configured to monitor this file (pre-task note)
echo "NOTE: The agent must add /var/log/audit/audit.log to ossec.conf localfile section"

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

echo "=== Setup Complete ==="
