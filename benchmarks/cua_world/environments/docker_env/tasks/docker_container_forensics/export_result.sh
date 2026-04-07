#!/bin/bash
echo "=== Exporting Docker Container Forensics Result ==="
source /workspace/scripts/task_utils.sh

take_screenshot "forensics_task_end"

# ── Read baseline ──────────────────────────────────────────────────────────────
TASK_START=0
if [ -f /tmp/task_start_timestamp ]; then
    TASK_START=$(cat /tmp/task_start_timestamp)
fi

# ── Helper: check if a container exists and is running ────────────────────────
container_running_flag() {
    local name="$1"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
        echo 1
    else
        echo 0
    fi
}

# Helper: check if a container exists and is stopped/exited
container_stopped_flag() {
    local name="$1"
    local status
    status=$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null)
    if [ "$status" = "exited" ] || [ "$status" = "created" ]; then
        echo 1
    else
        echo 0
    fi
}

# ── Inspect acme-webapp-fixed: capabilities ────────────────────────────────────
WEBAPP_FIXED_RUNNING=$(container_running_flag acme-webapp-fixed)
WEBAPP_CAPS="[]"
WEBAPP_NO_DANGEROUS_CAPS=0
if [ "$WEBAPP_FIXED_RUNNING" = "1" ]; then
    WEBAPP_CAPS=$(docker inspect acme-webapp-fixed --format '{{json .HostConfig.CapAdd}}' 2>/dev/null || echo "null")
    # Check for absence of dangerous caps: SYS_ADMIN, NET_ADMIN, SYS_PTRACE
    if echo "$WEBAPP_CAPS" | grep -qiE 'SYS_ADMIN|NET_ADMIN|SYS_PTRACE'; then
        WEBAPP_NO_DANGEROUS_CAPS=0
    else
        WEBAPP_NO_DANGEROUS_CAPS=1
    fi
fi

# ── Inspect acme-gateway-fixed: hardcoded secrets ─────────────────────────────
GATEWAY_FIXED_RUNNING=$(container_running_flag acme-gateway-fixed)
GATEWAY_ENV="[]"
GATEWAY_NO_HARDCODED_SECRETS=0
if [ "$GATEWAY_FIXED_RUNNING" = "1" ]; then
    GATEWAY_ENV=$(docker inspect acme-gateway-fixed --format '{{json .Config.Env}}' 2>/dev/null || echo "[]")
    # Check for absence of the specific hardcoded secret VALUES (not just the key names)
    HAS_DB_PASS=0
    HAS_AWS_KEY=0
    HAS_STRIPE=0
    HAS_TOKEN=0
    if echo "$GATEWAY_ENV" | grep -q 'Sup3rS3cr3t_ProdDB_2024'; then HAS_DB_PASS=1; fi
    if echo "$GATEWAY_ENV" | grep -q 'AKIAIOSFODNN7EXAMPLE'; then HAS_AWS_KEY=1; fi
    if echo "$GATEWAY_ENV" | grep -q 'wJalrXUtnFEMI'; then HAS_STRIPE=1; fi
    if echo "$GATEWAY_ENV" | grep -q 'sk_live_51EXAMPLE'; then HAS_STRIPE=1; fi
    if echo "$GATEWAY_ENV" | grep -q 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.EXAMPLE'; then HAS_TOKEN=1; fi
    SECRETS_PRESENT=$((HAS_DB_PASS + HAS_AWS_KEY + HAS_STRIPE + HAS_TOKEN))
    if [ "$SECRETS_PRESENT" = "0" ]; then
        GATEWAY_NO_HARDCODED_SECRETS=1
    fi
fi

# ── Inspect acme-monitor-fixed: dangerous bind mounts ─────────────────────────
MONITOR_FIXED_RUNNING=$(container_running_flag acme-monitor-fixed)
MONITOR_BINDS="[]"
MONITOR_NO_ETC_MOUNT=0
if [ "$MONITOR_FIXED_RUNNING" = "1" ]; then
    MONITOR_BINDS=$(docker inspect acme-monitor-fixed --format '{{json .HostConfig.Binds}}' 2>/dev/null || echo "null")
    if echo "$MONITOR_BINDS" | grep -q '^/etc:'; then
        MONITOR_NO_ETC_MOUNT=0
    elif echo "$MONITOR_BINDS" | grep -q '"/etc:'; then
        MONITOR_NO_ETC_MOUNT=0
    else
        MONITOR_NO_ETC_MOUNT=1
    fi
fi

# ── Check originals are stopped ────────────────────────────────────────────────
WEBAPP_ORIG_STOPPED=$(container_stopped_flag acme-webapp)
GATEWAY_ORIG_STOPPED=$(container_stopped_flag acme-gateway)
MONITOR_ORIG_STOPPED=$(container_stopped_flag acme-monitor)
ALL_ORIGINALS_STOPPED=0
if [ "$WEBAPP_ORIG_STOPPED" = "1" ] && [ "$GATEWAY_ORIG_STOPPED" = "1" ] && [ "$MONITOR_ORIG_STOPPED" = "1" ]; then
    ALL_ORIGINALS_STOPPED=1
fi

# ── Check incident report ──────────────────────────────────────────────────────
REPORT_PATH="/home/ga/Desktop/incident_report.txt"
REPORT_EXISTS=0
REPORT_MTIME=0
REPORT_MENTIONS_WEBAPP=0
REPORT_MENTIONS_GATEWAY=0
REPORT_MENTIONS_MONITOR=0
REPORT_WORD_COUNT=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS=1
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo 0)
    REPORT_WORD_COUNT=$(wc -w < "$REPORT_PATH" 2>/dev/null || echo 0)
    if grep -qi 'acme-webapp\|acme_webapp\|webapp' "$REPORT_PATH"; then REPORT_MENTIONS_WEBAPP=1; fi
    if grep -qi 'acme-gateway\|acme_gateway\|gateway' "$REPORT_PATH"; then REPORT_MENTIONS_GATEWAY=1; fi
    if grep -qi 'acme-monitor\|acme_monitor\|monitor' "$REPORT_PATH"; then REPORT_MENTIONS_MONITOR=1; fi
fi

REPORT_COVERS_ALL=0
if [ "$REPORT_MENTIONS_WEBAPP" = "1" ] && [ "$REPORT_MENTIONS_GATEWAY" = "1" ] && [ "$REPORT_MENTIONS_MONITOR" = "1" ]; then
    REPORT_COVERS_ALL=1
fi
REPORT_AFTER_START=0
if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
    REPORT_AFTER_START=1
fi

# ── Write result JSON ──────────────────────────────────────────────────────────
cat > /tmp/docker_forensics_result.json <<EOF
{
  "task_start": ${TASK_START},
  "webapp_fixed_running": ${WEBAPP_FIXED_RUNNING},
  "webapp_no_dangerous_caps": ${WEBAPP_NO_DANGEROUS_CAPS},
  "gateway_fixed_running": ${GATEWAY_FIXED_RUNNING},
  "gateway_no_hardcoded_secrets": ${GATEWAY_NO_HARDCODED_SECRETS},
  "monitor_fixed_running": ${MONITOR_FIXED_RUNNING},
  "monitor_no_etc_mount": ${MONITOR_NO_ETC_MOUNT},
  "all_originals_stopped": ${ALL_ORIGINALS_STOPPED},
  "webapp_orig_stopped": ${WEBAPP_ORIG_STOPPED},
  "gateway_orig_stopped": ${GATEWAY_ORIG_STOPPED},
  "monitor_orig_stopped": ${MONITOR_ORIG_STOPPED},
  "report_exists": ${REPORT_EXISTS},
  "report_after_start": ${REPORT_AFTER_START},
  "report_covers_all": ${REPORT_COVERS_ALL},
  "report_mentions_webapp": ${REPORT_MENTIONS_WEBAPP},
  "report_mentions_gateway": ${REPORT_MENTIONS_GATEWAY},
  "report_mentions_monitor": ${REPORT_MENTIONS_MONITOR},
  "report_word_count": ${REPORT_WORD_COUNT},
  "webapp_caps_raw": $(echo "$WEBAPP_CAPS" | python3 -c "import sys,json; s=sys.stdin.read().strip(); print(json.dumps(s))" 2>/dev/null || echo '""'),
  "gateway_env_count": $(echo "$GATEWAY_ENV" | python3 -c "import sys,json; data=sys.stdin.read().strip(); arr=json.loads(data) if data not in ('null','') else []; print(len(arr))" 2>/dev/null || echo 0),
  "monitor_binds_raw": $(echo "$MONITOR_BINDS" | python3 -c "import sys,json; s=sys.stdin.read().strip(); print(json.dumps(s))" 2>/dev/null || echo '""')
}
EOF

echo "=== Export Complete ==="
echo "Result saved to /tmp/docker_forensics_result.json"
cat /tmp/docker_forensics_result.json
