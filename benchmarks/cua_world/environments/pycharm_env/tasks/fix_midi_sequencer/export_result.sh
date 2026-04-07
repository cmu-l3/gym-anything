#!/bin/bash
echo "=== Exporting fix_midi_sequencer result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_midi_sequencer"
PROJECT_DIR="/home/ga/PycharmProjects/midi_builder"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run Tests
# We run the tests and capture the output to see if the agent fixed logic
echo "Running pytest..."
cd "$PROJECT_DIR" || exit 1
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

# 3. Analyze Code Fixes using grep (Secondary Verification)
# Check Encoder Fix
ENCODER_FIXED="false"
# Correct shift is >>= 7
if grep -q ">>=\s*7" "$PROJECT_DIR/midi_builder/encoder.py"; then
    ENCODER_FIXED="true"
fi

# Check Sequencer Delta Fix
# Looking for delta = ... - last_tick
SEQUENCER_DELTA_FIXED="false"
if grep -q "\-\s*last_tick" "$PROJECT_DIR/midi_builder/sequencer.py"; then
    SEQUENCER_DELTA_FIXED="true"
fi

# Check Sequencer EOT Fix
# Looking for FF 2F 00 write
SEQUENCER_EOT_FIXED="false"
if grep -q "x2F" "$PROJECT_DIR/midi_builder/sequencer.py" || grep -q "END_OF_TRACK" "$PROJECT_DIR/midi_builder/sequencer.py"; then
    if grep -q "write_varlen(0)" "$PROJECT_DIR/midi_builder/sequencer.py"; then
        SEQUENCER_EOT_FIXED="true"
    fi
fi

# 4. Export Generated MIDI File (if exists)
# The tests generate files in output/
# We copy one for the verifier to check binary structure
MIDI_FILE_EXISTS="false"
if [ -f "$PROJECT_DIR/output/test_rhythm.mid" ]; then
    cp "$PROJECT_DIR/output/test_rhythm.mid" /tmp/agent_output.mid
    MIDI_FILE_EXISTS="true"
fi

# 5. Create Result JSON
cat > "$RESULT_FILE" << EOF
{
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "pytest_output": $(echo "$PYTEST_OUTPUT" | jq -R -s '.'),
    "code_analysis": {
        "encoder_fixed": $ENCODER_FIXED,
        "delta_fixed": $SEQUENCER_DELTA_FIXED,
        "eot_fixed": $SEQUENCER_EOT_FIXED
    },
    "midi_file_exists": $MIDI_FILE_EXISTS
}
EOF

# Handle permissions
chmod 666 "$RESULT_FILE"
if [ -f /tmp/agent_output.mid ]; then
    chmod 666 /tmp/agent_output.mid
fi

echo "Export complete."