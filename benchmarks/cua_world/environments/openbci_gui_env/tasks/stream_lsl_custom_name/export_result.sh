#!/bin/bash
echo "=== Exporting stream_lsl_custom_name results ==="

# 1. Take final screenshot immediately (before potential app closure)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Check if App is running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Run Python verification script to discover LSL stream
# We create the script on the fly to ensure it uses the current environment
cat > /tmp/verify_lsl_stream.py << 'EOF'
import sys
import json
import time
from pylsl import resolve_streams, StreamInlet

result = {
    "stream_found": False,
    "stream_name": None,
    "stream_type": None,
    "data_received": False,
    "error": None
}

target_name = "OpenBCI_Station_A"

try:
    print(f"Scanning for LSL streams (target: {target_name})...")
    # Scan for 2 seconds
    streams = resolve_streams(wait_time=2.0)
    
    found_streams = []
    for s in streams:
        s_name = s.name()
        s_type = s.type()
        found_streams.append({"name": s_name, "type": s_type})
        
        if s_name == target_name:
            result["stream_found"] = True
            result["stream_name"] = s_name
            result["stream_type"] = s_type
            
            # Try to pull a sample to verify data flow
            try:
                inlet = StreamInlet(s)
                # pull_sample returns (sample, timestamp) or (None, None) on timeout
                sample, timestamp = inlet.pull_sample(timeout=2.0)
                if sample is not None:
                    result["data_received"] = True
            except Exception as e:
                result["error"] = f"Pull error: {str(e)}"
            
            break
            
    result["all_streams"] = found_streams

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# Run the verification script
echo "Running LSL verification..."
LSL_RESULT="{}"
if [ "$APP_RUNNING" = "true" ]; then
    LSL_RESULT=$(python3 /tmp/verify_lsl_stream.py 2>/dev/null || echo '{"error": "Script execution failed"}')
else
    LSL_RESULT='{"error": "App not running, cannot verify LSL"}'
fi

echo "LSL Result: $LSL_RESULT"

# 4. Construct Final JSON
# Use a temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "app_running": $APP_RUNNING,
    "lsl_verification": $LSL_RESULT,
    "task_end_time": $(date +%s),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="