#!/bin/bash
set -e
echo "=== Exporting configure_mail_server result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# GET SYSTEM CONFIGURATION
# ==============================================================================
# We fetch the full system configuration XML
CONFIG_XML=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" "${ARTIFACTORY_URL}/artifactory/api/system/configuration")

# Calculate final hash
FINAL_HASH=$(echo "$CONFIG_XML" | md5sum | awk '{print $1}')
INITIAL_HASH=$(cat /tmp/initial_config_hash.txt 2>/dev/null || echo "none")

# ==============================================================================
# PARSE CONFIGURATION TO JSON
# ==============================================================================
# We use Python to parse the XML and extract the mailServer block into a JSON object
# This avoids XML parsing issues in the verifier and keeps the logic self-contained.

python3 -c "
import sys
import json
import xml.etree.ElementTree as ET

try:
    xml_data = sys.stdin.read()
    root = ET.fromstring(xml_data)
    
    # Find mailServer block
    # Namespace handling might be needed depending on Artifactory version, 
    # but usually standard tags work if we ignore namespace or use wildcard.
    # We'll try direct tag first.
    
    ns = {'ns': 'http://artifactory.jfrog.org/xsd/3.1.2'} # Example namespace, might vary
    # Helper to find text safely
    def get_text(parent, tag):
        # Try finding tag directly
        el = parent.find(tag)
        if el is None:
            # Try searching all descendants (catch-all)
            for child in parent.iter():
                if child.tag.endswith(tag):
                    return child.text
            return None
        return el.text

    mail_server = None
    # Look for mailServer tag
    for child in root.iter():
        if child.tag.endswith('mailServer'):
            mail_server = child
            break
            
    result = {
        'found': False,
        'enabled': False,
        'host': None,
        'port': None,
        'username': None,
        'from': None,
        'subjectPrefix': None,
        'ssl': False,
        'tls': False,
        'has_password': False
    }

    if mail_server is not None:
        result['found'] = True
        
        enabled_txt = get_text(mail_server, 'enabled')
        result['enabled'] = (enabled_txt and enabled_txt.lower() == 'true')
        
        result['host'] = get_text(mail_server, 'host')
        
        port_txt = get_text(mail_server, 'port')
        result['port'] = int(port_txt) if port_txt and port_txt.isdigit() else None
        
        result['username'] = get_text(mail_server, 'username')
        result['from'] = get_text(mail_server, 'from')
        result['subjectPrefix'] = get_text(mail_server, 'subjectPrefix')
        
        ssl_txt = get_text(mail_server, 'ssl')
        result['ssl'] = (ssl_txt and ssl_txt.lower() == 'true')
        
        tls_txt = get_text(mail_server, 'tls')
        result['tls'] = (tls_txt and tls_txt.lower() == 'true')
        
        pass_txt = get_text(mail_server, 'password')
        result['has_password'] = (pass_txt is not None and len(pass_txt) > 0)

    # Output JSON
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({'error': str(e), 'found': False}))
" <<< "$CONFIG_XML" > /tmp/parsed_config.json

# Combine into final result
# We use a temp file to build the final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import sys

try:
    config = json.load(open('/tmp/parsed_config.json'))
    
    final = {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'initial_hash': '$INITIAL_HASH',
        'final_hash': '$FINAL_HASH',
        'config_changed': ('$INITIAL_HASH' != '$FINAL_HASH'),
        'mail_config': config,
        'screenshot_path': '/tmp/task_final.png'
    }
    
    print(json.dumps(final, indent=2))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="