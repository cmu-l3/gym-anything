#!/bin/bash
# Export script: fetch alerts configuration and analyze
echo "=== Exporting configure_error_alert task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve the expected channel ID
EXPECTED_CHANNEL_ID=$(cat /tmp/adt_channel_id.txt 2>/dev/null || echo "a1b2c3d4-e5f6-7890-abcd-ef1234567890")
INITIAL_ALERT_COUNT=$(cat /tmp/initial_alert_count.txt 2>/dev/null || echo "0")

# Fetch all alerts from API
echo "Fetching alerts from API..."
ALERTS_XML=$(curl -sk -u admin:admin \
    -H "X-Requested-With: OpenAPI" \
    -H "Accept: application/xml" \
    "https://localhost:8443/api/alerts" 2>/dev/null)

# Use Python to analyze the XML and produce a JSON result
# This runs inside the container where Python and dependencies are installed
echo "$ALERTS_XML" | python3 -c "
import sys
import json
import xml.etree.ElementTree as ET

result = {
    'alert_found': False,
    'alert_name': '',
    'alert_enabled': False,
    'channel_ids_monitored': [],
    'error_event_types': [],
    'regex_pattern': '',
    'has_action_group': False,
    'action_subject': '',
    'action_template': '',
    'action_recipients': [],
    'total_alerts': 0,
    'target_channel_id': '$EXPECTED_CHANNEL_ID'
}

try:
    # Handle empty response gracefully
    content = sys.stdin.read().strip()
    if not content:
        print(json.dumps(result))
        sys.exit(0)

    root = ET.fromstring(content)
    
    # Count total alerts
    alerts = list(root.iter('alertModel'))
    result['total_alerts'] = len(alerts)
    
    # Find the target alert by name
    target_alert = None
    for alert in alerts:
        name_elem = alert.find('name')
        if name_elem is not None and name_elem.text:
            if 'ADT Critical Error Monitor' in name_elem.text:
                target_alert = alert
                result['alert_name'] = name_elem.text
                result['alert_found'] = True
                break
    
    if target_alert is not None:
        # Check enabled status
        enabled_elem = target_alert.find('enabled')
        if enabled_elem is not None:
            result['alert_enabled'] = (enabled_elem.text.lower() == 'true')
        
        # Check trigger configuration
        trigger = target_alert.find('trigger')
        if trigger is not None:
            # Check monitored channels
            # Different Mirth versions use alertChannel/id or just channelId
            for ac in trigger.iter('alertChannel'):
                id_elem = ac.find('id')
                if id_elem is not None and id_elem.text:
                    result['channel_ids_monitored'].append(id_elem.text)
            
            # Legacy/Alternate structure
            for cid in trigger.iter('channelId'):
                if cid.text:
                    result['channel_ids_monitored'].append(cid.text)
            
            # Check error event types
            for eet in trigger.iter('errorEventType'):
                if eet.text:
                    result['error_event_types'].append(eet.text)
            
            # Deep search for event types if not found at top level
            if not result['error_event_types']:
                eet_container = trigger.find('.//errorEventTypes')
                if eet_container is not None:
                    for child in eet_container:
                        if child.text:
                            result['error_event_types'].append(child.text)
            
            # Check regex
            regex_elem = trigger.find('regex')
            if regex_elem is not None and regex_elem.text:
                result['regex_pattern'] = regex_elem.text
        
        # Check action groups
        for ag in target_alert.iter('alertActionGroup'):
            result['has_action_group'] = True
            
            subj = ag.find('subject')
            if subj is not None and subj.text:
                result['action_subject'] = subj.text
            
            tmpl = ag.find('template')
            if tmpl is not None and tmpl.text:
                result['action_template'] = tmpl.text
            
            # Check recipients
            for action in ag.iter('alertAction'):
                recipient = action.find('recipient')
                protocol = action.find('protocol')
                if recipient is not None and recipient.text:
                    result['action_recipients'].append({
                        'recipient': recipient.text,
                        'protocol': protocol.text if protocol is not None else 'UNKNOWN'
                    })
            
            # Only analyze the first valid group found
            if result['action_subject'] or result['action_recipients']:
                break
    
except Exception as e:
    result['error'] = str(e)

# Add timestamp info
result['initial_alert_count'] = int('$INITIAL_ALERT_COUNT')
result['task_start_time'] = int('$TASK_START')
result['task_end_time'] = int('$TASK_END')

print(json.dumps(result, indent=2))
" > /tmp/task_result.json

# Ensure result file permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export complete ==="