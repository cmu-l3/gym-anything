#!/bin/bash
# Export script for multi_source_decoder_pipeline
# Checks nginx decoder, postgres decoder, detection rules, ossec.conf, and group agent.conf.

echo "=== Exporting multi_source_decoder_pipeline Result ==="

source /workspace/scripts/task_utils.sh

if ! type wazuh_exec &>/dev/null; then
    wazuh_exec() { docker exec wazuh.manager bash -c "$1" 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_DECODER_COUNT=$(cat /tmp/initial_decoder_count 2>/dev/null || echo "0")
INITIAL_RULE_COUNT=$(cat /tmp/initial_rule_count 2>/dev/null || echo "0")
INITIAL_LOCALFILE_COUNT=$(cat /tmp/initial_localfile_count 2>/dev/null || echo "0")
INITIAL_AGENT_CONF_LINES=$(cat /tmp/initial_agent_conf_lines 2>/dev/null || echo "0")

echo "Task start: $TASK_START"

DECODER_XML=$(wazuh_exec "cat /var/ossec/etc/decoders/local_decoder.xml 2>/dev/null || echo ''")
RULES_XML=$(wazuh_exec "cat /var/ossec/etc/rules/local_rules.xml 2>/dev/null || echo ''")
OSSEC_CONF=$(wazuh_exec "cat /var/ossec/etc/ossec.conf 2>/dev/null || echo ''")
AGENT_CONF=$(wazuh_exec "cat /var/ossec/etc/shared/web-servers/agent.conf 2>/dev/null || echo ''")

# --- Check 1: Nginx decoder (parent + child) ---
echo "Checking nginx decoder..."

NGINX_PARENT=0
NGINX_CHILD=0
NGINX_DECODER_COUNT=0
NGINX_FIELDS_OK=0

if echo "$DECODER_XML" | grep -qiE 'name="[^"]*nginx|program_name>[^<]*nginx'; then
    NGINX_PARENT=1
    # Check for child decoder
    if echo "$DECODER_XML" | grep -qiE '<parent>[^<]*nginx'; then
        NGINX_CHILD=1
    fi
    # Count nginx decoder entries
    COUNT_OUT=$(echo "$DECODER_XML" | grep -c -iE 'name="[^"]*nginx')
    if echo "$COUNT_OUT" | grep -qE '^[0-9]+$'; then
        NGINX_DECODER_COUNT=$COUNT_OUT
    fi
    # Check for field extraction (src_ip, url, status code, method)
    if echo "$DECODER_XML" | grep -qiE 'srcip|src_ip|url|status|method|http_method'; then
        NGINX_FIELDS_OK=1
    fi
fi
echo "Nginx decoder: parent=$NGINX_PARENT, child=$NGINX_CHILD, count=$NGINX_DECODER_COUNT, fields=$NGINX_FIELDS_OK"

# --- Check 2: PostgreSQL decoder (parent + child) ---
echo "Checking PostgreSQL decoder..."

PG_PARENT=0
PG_CHILD=0
PG_DECODER_COUNT=0
PG_FIELDS_OK=0

if echo "$DECODER_XML" | grep -qiE 'name="[^"]*postgres|name="[^"]*pgsql|program_name>[^<]*postgres'; then
    PG_PARENT=1
    if echo "$DECODER_XML" | grep -qiE '<parent>[^<]*postgres|<parent>[^<]*pgsql'; then
        PG_CHILD=1
    fi
    COUNT_OUT=$(echo "$DECODER_XML" | grep -c -iE 'name="[^"]*postgres|name="[^"]*pgsql')
    if echo "$COUNT_OUT" | grep -qE '^[0-9]+$'; then
        PG_DECODER_COUNT=$COUNT_OUT
    fi
    # Check for field extraction (database, user, log level/severity)
    if echo "$DECODER_XML" | grep -qiE 'database|dbname|db_user|pg_user|user|dstuser'; then
        PG_FIELDS_OK=1
    fi
fi
echo "PostgreSQL decoder: parent=$PG_PARENT, child=$PG_CHILD, count=$PG_DECODER_COUNT, fields=$PG_FIELDS_OK"

# --- Check 3: Detection rules (>=3, covering nginx and postgres) ---
echo "Checking detection rules..."

CURRENT_RULE_COUNT=0
RULE_COUNT_OUT=$(echo "$RULES_XML" | grep -c '<rule id=')
if echo "$RULE_COUNT_OUT" | grep -qE '^[0-9]+$'; then
    CURRENT_RULE_COUNT=$RULE_COUNT_OUT
fi
NEW_RULES=$((CURRENT_RULE_COUNT - INITIAL_RULE_COUNT))
[ "$NEW_RULES" -lt 0 ] && NEW_RULES=0

NGINX_ATTACK_RULE=0
PG_ACCESS_RULE=0
WEB_ERROR_RULE=0

# Nginx attack detection rules
if echo "$RULES_XML" | grep -qiE 'sql.*inject|union.*select|path.*travers|directory.*travers|\.\.\/|scanner|nikto|sqlmap|XSS|script.*alert|http.*403|http.*attack'; then
    NGINX_ATTACK_RULE=1
fi

# PostgreSQL access/auth rules
if echo "$RULES_XML" | grep -qiE 'postgres|pgsql|pg_|authentication.*fail.*postgres|password.*fail.*postgres|permission.*denied.*postgres|pg_shadow|brute.*force.*postgres'; then
    PG_ACCESS_RULE=1
fi

# General web error/anomaly rules
if echo "$RULES_XML" | grep -qiE 'web.*attack|http.*500|http.*error|web.*scan|multiple.*404'; then
    WEB_ERROR_RULE=1
fi

TOTAL_NEW_CATEGORIES=$((NGINX_ATTACK_RULE + PG_ACCESS_RULE + WEB_ERROR_RULE))
echo "Rules: new=$NEW_RULES, nginx_attack=$NGINX_ATTACK_RULE, pg_access=$PG_ACCESS_RULE, web_error=$WEB_ERROR_RULE"

# --- Check 4: ossec.conf localfile entries for nginx and postgres ---
echo "Checking ossec.conf localfile entries..."

OSSEC_HAS_NGINX=0
OSSEC_HAS_POSTGRES=0
NEW_LOCALFILE_COUNT=0

if echo "$OSSEC_CONF" | grep -qiE '/var/log/nginx|nginx.*access\.log|nginx.*error\.log'; then
    OSSEC_HAS_NGINX=1
fi
if echo "$OSSEC_CONF" | grep -qiE '/var/log/postgresql|postgres.*\.log|postgresql.*\.log'; then
    OSSEC_HAS_POSTGRES=1
fi

CURRENT_LF_COUNT=0
LF_COUNT_OUT=$(echo "$OSSEC_CONF" | grep -c '<localfile>')
if echo "$LF_COUNT_OUT" | grep -qE '^[0-9]+$'; then
    CURRENT_LF_COUNT=$LF_COUNT_OUT
fi
NEW_LOCALFILE_COUNT=$((CURRENT_LF_COUNT - INITIAL_LOCALFILE_COUNT))
[ "$NEW_LOCALFILE_COUNT" -lt 0 ] && NEW_LOCALFILE_COUNT=0

echo "ossec.conf: nginx=$OSSEC_HAS_NGINX, postgres=$OSSEC_HAS_POSTGRES, new_localfiles=$NEW_LOCALFILE_COUNT"

# --- Check 5: web-servers group agent.conf updated ---
echo "Checking web-servers agent.conf..."

AGENT_CONF_UPDATED=0
AGENT_CONF_HAS_NGINX=0
AGENT_CONF_HAS_POSTGRES=0
CURRENT_AC_LINES=0

LINES_OUT=$(wazuh_exec "wc -l < /var/ossec/etc/shared/web-servers/agent.conf 2>/dev/null || echo '0'")
if echo "$LINES_OUT" | grep -qE '^[0-9]+$'; then
    CURRENT_AC_LINES=$LINES_OUT
fi

if [ "$CURRENT_AC_LINES" -gt "$INITIAL_AGENT_CONF_LINES" ] 2>/dev/null; then
    AGENT_CONF_UPDATED=1
fi

if echo "$AGENT_CONF" | grep -qiE 'nginx|/var/log/nginx'; then
    AGENT_CONF_HAS_NGINX=1
    AGENT_CONF_UPDATED=1
fi
if echo "$AGENT_CONF" | grep -qiE 'postgres|postgresql|/var/log/postgresql'; then
    AGENT_CONF_HAS_POSTGRES=1
    AGENT_CONF_UPDATED=1
fi
# Also check if new localfile/syscheck entries were added
if echo "$AGENT_CONF" | grep -qE '<localfile>|<syscheck>'; then
    AGENT_CONF_UPDATED=1
fi

echo "agent.conf: updated=$AGENT_CONF_UPDATED, nginx=$AGENT_CONF_HAS_NGINX, postgres=$AGENT_CONF_HAS_POSTGRES, lines=$CURRENT_AC_LINES"

# Write result JSON
cat > /tmp/multi_source_decoder_pipeline_result.json << JSONEOF
{
    "task_start": ${TASK_START},
    "nginx_parent_decoder": ${NGINX_PARENT},
    "nginx_child_decoder": ${NGINX_CHILD},
    "nginx_decoder_count": ${NGINX_DECODER_COUNT},
    "nginx_fields_extracted": ${NGINX_FIELDS_OK},
    "postgres_parent_decoder": ${PG_PARENT},
    "postgres_child_decoder": ${PG_CHILD},
    "postgres_decoder_count": ${PG_DECODER_COUNT},
    "postgres_fields_extracted": ${PG_FIELDS_OK},
    "new_rule_count": ${NEW_RULES},
    "total_rule_count": ${CURRENT_RULE_COUNT},
    "nginx_attack_rule": ${NGINX_ATTACK_RULE},
    "postgres_access_rule": ${PG_ACCESS_RULE},
    "web_error_rule": ${WEB_ERROR_RULE},
    "total_new_categories": ${TOTAL_NEW_CATEGORIES},
    "ossec_has_nginx_localfile": ${OSSEC_HAS_NGINX},
    "ossec_has_postgres_localfile": ${OSSEC_HAS_POSTGRES},
    "new_localfile_count": ${NEW_LOCALFILE_COUNT},
    "agent_conf_updated": ${AGENT_CONF_UPDATED},
    "agent_conf_has_nginx": ${AGENT_CONF_HAS_NGINX},
    "agent_conf_has_postgres": ${AGENT_CONF_HAS_POSTGRES},
    "initial_decoder_count": ${INITIAL_DECODER_COUNT},
    "initial_rule_count": ${INITIAL_RULE_COUNT}
}
JSONEOF

echo "Result JSON written to /tmp/multi_source_decoder_pipeline_result.json"
python3 -m json.tool /tmp/multi_source_decoder_pipeline_result.json > /dev/null 2>&1 && echo "JSON valid" || echo "WARNING: JSON may be malformed"

echo "=== Export Complete ==="
