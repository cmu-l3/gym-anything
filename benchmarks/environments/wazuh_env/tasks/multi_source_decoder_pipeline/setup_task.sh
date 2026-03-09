#!/bin/bash
# Setup script for multi_source_decoder_pipeline
# Creates real nginx and PostgreSQL log files for the agent to build pipelines for.

echo "=== Setting up multi_source_decoder_pipeline ==="

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

# Baseline: web-servers group agent.conf line count
INITIAL_AGENT_CONF_LINES=0
AC_COUNT_OUT=$(wazuh_exec "wc -l < /var/ossec/etc/shared/web-servers/agent.conf 2>/dev/null || echo '0'")
if echo "$AC_COUNT_OUT" | grep -qE '^[0-9]+$'; then
    INITIAL_AGENT_CONF_LINES=$AC_COUNT_OUT
fi
echo "$INITIAL_AGENT_CONF_LINES" > /tmp/initial_agent_conf_lines
echo "Baseline web-servers agent.conf lines: $INITIAL_AGENT_CONF_LINES"

# Baseline: ossec.conf localfile count
INITIAL_LOCALFILE_COUNT=0
LF_COUNT_OUT=$(wazuh_exec "grep -c '<localfile>' /var/ossec/etc/ossec.conf 2>/dev/null")
if echo "$LF_COUNT_OUT" | grep -qE '^[0-9]+$'; then
    INITIAL_LOCALFILE_COUNT=$LF_COUNT_OUT
fi
echo "$INITIAL_LOCALFILE_COUNT" > /tmp/initial_localfile_count
echo "Baseline localfile count: $INITIAL_LOCALFILE_COUNT"

# --- Create real-format nginx and PostgreSQL log files ---
# These are real log format lines from nginx combined log format and PostgreSQL log format

echo "Creating nginx access log with real format entries..."
wazuh_exec "mkdir -p /var/log/nginx"
wazuh_exec "cat > /var/log/nginx/access.log << 'NGINXEOF'
192.168.1.100 - jsmith [28/Jan/2024:10:15:22 +0000] \"GET /index.html HTTP/1.1\" 200 4520 \"-\" \"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36\"
10.0.0.15 - - [28/Jan/2024:10:15:45 +0000] \"GET /api/users?id=1%20UNION%20SELECT%201,username,password%20FROM%20users-- HTTP/1.1\" 200 1234 \"-\" \"sqlmap/1.7.6\"
203.0.113.45 - - [28/Jan/2024:10:16:01 +0000] \"GET /../../../../etc/passwd HTTP/1.1\" 404 162 \"-\" \"curl/7.68.0\"
10.0.0.22 - alice [28/Jan/2024:10:16:15 +0000] \"POST /login HTTP/1.1\" 200 523 \"https://app.company.com\" \"Mozilla/5.0\"
198.51.100.5 - - [28/Jan/2024:10:16:30 +0000] \"GET /admin HTTP/1.1\" 403 162 \"-\" \"Nikto/2.1.6\"
192.168.1.101 - bob [28/Jan/2024:10:17:00 +0000] \"GET /api/products HTTP/1.1\" 200 8903 \"-\" \"Mozilla/5.0\"
198.51.100.5 - - [28/Jan/2024:10:17:15 +0000] \"GET /phpinfo.php HTTP/1.1\" 404 162 \"-\" \"Nikto/2.1.6\"
198.51.100.5 - - [28/Jan/2024:10:17:16 +0000] \"GET /.git/config HTTP/1.1\" 404 162 \"-\" \"Nikto/2.1.6\"
198.51.100.5 - - [28/Jan/2024:10:17:17 +0000] \"GET /wp-admin HTTP/1.1\" 404 162 \"-\" \"Nikto/2.1.6\"
10.0.0.50 - - [28/Jan/2024:10:18:00 +0000] \"GET /api/v2/health HTTP/1.1\" 200 45 \"-\" \"HealthCheck/1.0\"
NGINXEOF"

echo "Creating PostgreSQL log with real format entries..."
wazuh_exec "mkdir -p /var/log/postgresql"
wazuh_exec "cat > /var/log/postgresql/postgresql-14-main.log << 'PGEOF'
2024-01-28 10:15:00.123 UTC [12345] appuser@appdb LOG:  connection received: host=192.168.1.100 port=54321
2024-01-28 10:15:00.456 UTC [12345] appuser@appdb LOG:  connection authorized: user=appuser database=appdb
2024-01-28 10:15:30.789 UTC [12346] unknown@appdb FATAL:  password authentication failed for user \"admin\"
2024-01-28 10:15:31.012 UTC [12347] unknown@appdb FATAL:  password authentication failed for user \"admin\"
2024-01-28 10:15:31.234 UTC [12348] unknown@appdb FATAL:  password authentication failed for user \"admin\"
2024-01-28 10:15:31.456 UTC [12349] unknown@appdb FATAL:  password authentication failed for user \"admin\"
2024-01-28 10:15:31.678 UTC [12350] unknown@appdb FATAL:  password authentication failed for user \"admin\"
2024-01-28 10:16:00.001 UTC [12351] unknown@postgres FATAL:  role \"root\" does not exist
2024-01-28 10:16:15.333 UTC [12352] appuser@appdb ERROR:  permission denied for table users
2024-01-28 10:16:30.555 UTC [12353] appuser@appdb LOG:  statement: SELECT * FROM pg_shadow;
2024-01-28 10:17:00.777 UTC [12354] postgres@postgres LOG:  connection received: host=10.0.0.99 port=60001
2024-01-28 10:17:00.999 UTC [12355] postgres@postgres LOG:  connection authorized: user=postgres database=postgres
PGEOF"

echo "Log files created:"
wazuh_exec "ls -la /var/log/nginx/ /var/log/postgresql/ 2>/dev/null"

# Verify web-servers group exists
if wazuh_exec "test -d /var/ossec/etc/shared/web-servers" 2>/dev/null; then
    echo "web-servers group directory exists"
else
    echo "Creating web-servers group directory..."
    wazuh_exec "mkdir -p /var/ossec/etc/shared/web-servers"
    # Create minimal agent.conf if it doesn't exist
    wazuh_exec "test -f /var/ossec/etc/shared/web-servers/agent.conf || cat > /var/ossec/etc/shared/web-servers/agent.conf << 'EOF'
<agent_config>
</agent_config>
EOF"
fi

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
