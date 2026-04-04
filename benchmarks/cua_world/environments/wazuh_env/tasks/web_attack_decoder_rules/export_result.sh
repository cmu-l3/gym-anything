#!/bin/bash
# post_task: Export results for web_attack_decoder_rules
echo "=== Exporting web_attack_decoder_rules Results ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

take_screenshot /tmp/task_end_screenshot.png

# === Check 1: Custom web/nginx decoder in local_decoder.xml ===
DECODER_EXISTS=0
DECODER_NAME=""
DECODER_XML_VALID=0

DECODER_CHECK=$(docker exec "${CONTAINER}" python3 -c "
import sys

# Read file content
try:
    with open('/var/ossec/etc/decoders/local_decoder.xml') as f:
        content = f.read()
except Exception as e:
    print('error:' + str(e))
    exit()

# Validate XML by wrapping in root element
import xml.etree.ElementTree as ET
try:
    root = ET.fromstring('<root>' + content + '</root>')
    xml_valid = True
except Exception:
    xml_valid = False

print('xml_valid:' + str(xml_valid))

# Find web/nginx-related decoders
web_keywords = ['nginx', 'apache', 'http', 'web', 'access', 'httpd']
for decoder in root.findall('decoder'):
    name = decoder.get('name', '').lower()
    # Check decoder name for web keywords
    if any(kw in name for kw in web_keywords):
        print('found:' + decoder.get('name', ''))
        exit()
    # Check program_name element
    prog = decoder.find('program_name')
    if prog is not None and prog.text and any(kw in prog.text.lower() for kw in web_keywords):
        print('found:' + decoder.get('name', ''))
        exit()
    # Check if regex/prematch has HTTP-specific patterns
    for tag in ['prematch', 'regex']:
        el = decoder.find(tag)
        if el is not None and el.text:
            text = el.text.lower()
            if any(kw in text for kw in ['http/', 'get ', 'post ', '\"get', '\"post', 'status_code', 'url']):
                print('found:' + decoder.get('name', ''))
                exit()
print('not_found')
" 2>/dev/null || echo "not_found")

if echo "$DECODER_CHECK" | grep -q "^xml_valid:True"; then
    DECODER_XML_VALID=1
fi
if echo "$DECODER_CHECK" | grep -q "^found:"; then
    DECODER_EXISTS=1
    DECODER_NAME=$(echo "$DECODER_CHECK" | grep "^found:" | head -1 | cut -d':' -f2-)
fi

# === Check 2: Web attack detection rules in local_rules.xml ===
INITIAL_RULE_COUNT=$(cat /tmp/initial_rule_count 2>/dev/null || echo "3")

RULES_CHECK=$(docker exec "${CONTAINER}" python3 -c "
import xml.etree.ElementTree as ET
import re

INITIAL_RULE_COUNT = int('${INITIAL_RULE_COUNT}')

try:
    tree = ET.parse('/var/ossec/etc/rules/local_rules.xml')
    root = tree.getroot()
except Exception as e:
    print('0,0,0,0,0,0')
    exit()

web_attack_rules = 0
max_level = 0
has_mitre = False
sql_level = 0
traversal_level = 0
cmd_level = 0

# Collect all rules, skip the first INITIAL_RULE_COUNT (baseline rules)
all_rules = list(root.iter('rule'))
new_rules = all_rules[INITIAL_RULE_COUNT:]

# Patterns for detecting web attack rules (use specific strings to avoid false positives)
sql_patterns = ['select', 'union', 'insert', 'drop', 'sql inject', '1=1', 'or 1', 'having', 'sleep(', 'benchmark(']
traversal_patterns = ['../', 'directory traversal', 'path traversal', 'directory.traversal', 'path.traversal']
# 'exec' and 'rce' use word-boundary matching via regex to avoid substring false positives
cmd_patterns_plain = ['system(', 'passthru', 'shell_exec', '; ls', '| cat', 'cmd inject', 'command inject', '|bash', '|sh']
cmd_patterns_regex = [r'\bexec\b', r'\brce\b']
xss_patterns = ['<script', 'javascript:', 'onerror=', 'onload=', 'xss', 'cross site', 'cross.site']
mitre_patterns = ['mitre', 't1190', 't1059', 't1134', 't1210', 'att&amp;ck', 'att&ck']

for rule in new_rules:
    level = int(rule.get('level', 0))
    is_web_attack = False
    is_sql = False
    is_traversal = False
    is_cmd = False

    rule_text = ET.tostring(rule, encoding='unicode').lower()

    if any(p in rule_text for p in sql_patterns):
        is_sql = True
        is_web_attack = True
    if any(p in rule_text for p in traversal_patterns):
        is_traversal = True
        is_web_attack = True
    cmd_match = (any(p in rule_text for p in cmd_patterns_plain) or
                 any(re.search(pat, rule_text) for pat in cmd_patterns_regex))
    if cmd_match and level >= 7:
        is_cmd = True
        is_web_attack = True
    if any(p in rule_text for p in xss_patterns):
        is_web_attack = True
    if any(p in rule_text for p in mitre_patterns):
        has_mitre = True

    if is_web_attack:
        web_attack_rules += 1
        if level > max_level:
            max_level = level
        if is_sql and level > sql_level:
            sql_level = level
        if is_traversal and level > traversal_level:
            traversal_level = level
        if is_cmd and level > cmd_level:
            cmd_level = level

print(f'{web_attack_rules},{max_level},{1 if has_mitre else 0},{sql_level},{traversal_level},{cmd_level}')
" 2>/dev/null || echo "0,0,0,0,0,0")

WEB_ATTACK_RULE_COUNT=$(echo "$RULES_CHECK" | cut -d',' -f1)
MAX_RULE_LEVEL=$(echo "$RULES_CHECK" | cut -d',' -f2)
HAS_MITRE_MAPPING=$(echo "$RULES_CHECK" | cut -d',' -f3)
SQL_INJECTION_RULE_LEVEL=$(echo "$RULES_CHECK" | cut -d',' -f4)
TRAVERSAL_RULE_LEVEL=$(echo "$RULES_CHECK" | cut -d',' -f5)
CMD_INJECTION_RULE_LEVEL=$(echo "$RULES_CHECK" | cut -d',' -f6)

[ -z "$WEB_ATTACK_RULE_COUNT" ] && WEB_ATTACK_RULE_COUNT=0
[ -z "$MAX_RULE_LEVEL" ] && MAX_RULE_LEVEL=0
[ -z "$HAS_MITRE_MAPPING" ] && HAS_MITRE_MAPPING=0
[ -z "$SQL_INJECTION_RULE_LEVEL" ] && SQL_INJECTION_RULE_LEVEL=0
[ -z "$TRAVERSAL_RULE_LEVEL" ] && TRAVERSAL_RULE_LEVEL=0
[ -z "$CMD_INJECTION_RULE_LEVEL" ] && CMD_INJECTION_RULE_LEVEL=0

# Create result JSON
cat > /tmp/web_attack_decoder_rules_result.json << EOF
{
    "task_start": ${TASK_START},
    "decoder_exists": ${DECODER_EXISTS},
    "decoder_name": "${DECODER_NAME}",
    "decoder_xml_valid": ${DECODER_XML_VALID},
    "web_attack_rule_count": ${WEB_ATTACK_RULE_COUNT},
    "max_rule_level": ${MAX_RULE_LEVEL},
    "has_mitre_mapping": ${HAS_MITRE_MAPPING},
    "sql_injection_rule_level": ${SQL_INJECTION_RULE_LEVEL},
    "traversal_rule_level": ${TRAVERSAL_RULE_LEVEL},
    "cmd_injection_rule_level": ${CMD_INJECTION_RULE_LEVEL},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat /tmp/web_attack_decoder_rules_result.json
echo "=== Export Complete ==="
