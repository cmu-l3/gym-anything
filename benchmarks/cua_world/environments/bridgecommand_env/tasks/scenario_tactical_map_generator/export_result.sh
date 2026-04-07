#!/bin/bash
echo "=== Exporting Tactical Map Generator Result ==="

# Define paths
SCRIPT_NAME="generate_tactical_map.py"
OUTPUT_IMAGE="tactical_map.png"
PUBLIC_SCENARIO="/opt/bridgecommand/Scenarios/m) Portsmouth Approach Custom"
HIDDEN_SCENARIO="/opt/bridgecommand/Scenarios/VALIDATION_HIDDEN_SCENARIO"

# Locate the agent's script
AGENT_SCRIPT=""
if [ -f "/home/ga/Desktop/$SCRIPT_NAME" ]; then
    AGENT_SCRIPT="/home/ga/Desktop/$SCRIPT_NAME"
elif [ -f "/home/ga/$SCRIPT_NAME" ]; then
    AGENT_SCRIPT="/home/ga/$SCRIPT_NAME"
fi

SCRIPT_FOUND="false"
PUBLIC_RUN_SUCCESS="false"
HIDDEN_RUN_SUCCESS="false"
PUBLIC_IMG_EXISTS="false"
HIDDEN_IMG_EXISTS="false"

# Create a temporary directory for verification outputs
VERIFY_DIR=$(mktemp -d)
chmod 777 "$VERIFY_DIR"

if [ -n "$AGENT_SCRIPT" ]; then
    SCRIPT_FOUND="true"
    echo "Found agent script at: $AGENT_SCRIPT"

    # --- TEST 1: Run against Public Scenario ---
    echo "Running script against Public Scenario..."
    cd "$VERIFY_DIR"
    # Run as ga user to simulate agent environment
    if su - ga -c "python3 '$AGENT_SCRIPT' '$PUBLIC_SCENARIO'" > "$VERIFY_DIR/public_stdout.log" 2>&1; then
        PUBLIC_RUN_SUCCESS="true"
        # Check if image was created in CWD (home dir of ga usually, or wherever script ran)
        # We need to find where the script dumped the image. Most likely PWD.
        # Since we ran `su - ga -c`, PWD is /home/ga.
        if [ -f "/home/ga/$OUTPUT_IMAGE" ]; then
            mv "/home/ga/$OUTPUT_IMAGE" "$VERIFY_DIR/public_map.png"
            PUBLIC_IMG_EXISTS="true"
        elif [ -f "$AGENT_SCRIPT_DIR/$OUTPUT_IMAGE" ]; then
             # Try script dir
             mv "$(dirname "$AGENT_SCRIPT")/$OUTPUT_IMAGE" "$VERIFY_DIR/public_map.png"
             PUBLIC_IMG_EXISTS="true"
        fi
    else
        echo "Public run failed."
    fi

    # --- TEST 2: Run against HIDDEN Scenario (Generalization Test) ---
    echo "Running script against Hidden Scenario..."
    # Clean up any previous image
    rm -f "/home/ga/$OUTPUT_IMAGE"
    
    if su - ga -c "python3 '$AGENT_SCRIPT' '$HIDDEN_SCENARIO'" > "$VERIFY_DIR/hidden_stdout.log" 2>&1; then
        HIDDEN_RUN_SUCCESS="true"
        if [ -f "/home/ga/$OUTPUT_IMAGE" ]; then
            mv "/home/ga/$OUTPUT_IMAGE" "$VERIFY_DIR/hidden_map.png"
            HIDDEN_IMG_EXISTS="true"
        fi
    else
        echo "Hidden run failed."
    fi
    
    # Analyze the script source for keywords
    SCRIPT_CONTENT=$(cat "$AGENT_SCRIPT")
else
    echo "Agent script not found."
    SCRIPT_CONTENT=""
fi

# Take final screenshot of desktop
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare images for export (rename for VLM)
cp "$VERIFY_DIR/public_map.png" /tmp/public_map.png 2>/dev/null || true
cp "$VERIFY_DIR/hidden_map.png" /tmp/hidden_map.png 2>/dev/null || true

# JSON Result Construction
cat > /tmp/task_result.json << EOF
{
    "script_found": $SCRIPT_FOUND,
    "script_path": "$AGENT_SCRIPT",
    "public_run_success": $PUBLIC_RUN_SUCCESS,
    "hidden_run_success": $HIDDEN_RUN_SUCCESS,
    "public_image_exists": $PUBLIC_IMG_EXISTS,
    "hidden_image_exists": $HIDDEN_IMG_EXISTS,
    "script_content_snippet": $(python3 -c "import json; print(json.dumps('''$SCRIPT_CONTENT'''[:1000]))"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Clean up
rm -rf "$VERIFY_DIR"

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export Complete ==="