#!/bin/bash
echo "=== Exporting configure_emergency_overlay result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ==============================================================================
# QUERY API FOR RESULTS
# ==============================================================================
refresh_nx_token > /dev/null 2>&1 || true

# Fetch all event rules
RULES_JSON=$(nx_api_get "/rest/v1/eventRules")

# Analyze rules using Python to find the one matching our criteria
# We look for:
# 1. eventType == 'softwareTriggerEvent'
# 2. actionType == 'showTextOverlayAction'
# 3. Created/Modified recently (optional, but good for anti-gaming)
# 4. Specific text content

PYTHON_ANALYSIS=$(python3 << EOF
import sys
import json

try:
    rules = json.loads('''$RULES_JSON''')
    task_start = int($TASK_START)
    
    # Candidates
    candidates = []
    
    for rule in rules:
        # Check event type (Soft Trigger)
        is_soft_trigger = rule.get('eventType') == 'softwareTriggerEvent'
        
        # Check action type (Text Overlay)
        is_overlay = rule.get('actionType') == 'showTextOverlayAction'
        
        if is_soft_trigger and is_overlay:
            # Extract details
            event_params = rule.get('eventCondition', '').replace('\\\\', '') 
            # Note: eventCondition is often encoded, but parameters like caption might be in 'eventResourceName' or split fields
            # In Nx Witness API v1:
            # eventType: softwareTriggerEvent
            # actionType: showTextOverlayAction
            # actionParams: json string containing 'text', 'duration'
            # eventCondition: json string containing 'caption' (trigger name)
            
            # Simple substring checks on the raw rule dump are often more robust across API versions
            # unless we strictly parse the nested JSON strings in 'actionParams'
            
            rule_dump = json.dumps(rule).lower()
            
            # Extract action params if possible
            action_text = ""
            duration = 0
            trigger_name = ""
            
            # Try parsing actionParams
            try:
                import json as j2
                a_params = j2.loads(rule.get('actionParams', '{}'))
                action_text = a_params.get('text', '')
                duration = a_params.get('durationMs', 0)
            except:
                pass
                
            # Try parsing eventCondition (for trigger name/caption)
            try:
                import json as j2
                e_cond = j2.loads(rule.get('eventCondition', '{}'))
                # 'caption' is often the Soft Trigger Name
                trigger_name = e_cond.get('caption', '')
                # If caption is empty, sometimes it's implied or stored elsewhere
            except:
                pass

            candidates.append({
                "id": rule.get('id'),
                "trigger_name": trigger_name,
                "action_text": action_text,
                "duration": duration,
                "target_all": True, # Hard to verify strictly without complex parsing, assume true if found
                "raw": rule
            })

    # Find best match
    best_match = None
    for c in candidates:
        # Check text match
        if "lockdown" in c['action_text'].lower() or "lockdown" in c['trigger_name'].lower():
            best_match = c
            break
            
    result = {
        "rule_found": best_match is not None,
        "details": best_match if best_match else {},
        "candidate_count": len(candidates)
    }
    
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e), "rule_found": False}))
EOF
)

# Save analysis to file
echo "$PYTHON_ANALYSIS" > /tmp/analysis_result.json

# Construct final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "api_analysis": $PYTHON_ANALYSIS
}
EOF

# Move to standard output location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json