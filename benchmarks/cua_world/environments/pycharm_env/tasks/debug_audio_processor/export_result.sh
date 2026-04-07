#!/bin/bash
echo "=== Exporting debug_audio_processor results ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/PycharmProjects/audio_core"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final state
take_screenshot /tmp/task_end.png

# Run pytest and capture output
echo "Running test suite..."
cd "$PROJECT_DIR" || exit 1

# Install deps if needed (agent might have missed this, but we need it for verification)
pip3 install -r requirements.txt -q 2>/dev/null || true

# Run tests
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

echo "Pytest exit code: $PYTEST_EXIT_CODE"

# --- Independent Verification Script ---
# We will run a python script that imports the agent's code and tests it against
# known inputs. This protects against "gaming" (e.g., deleting test assertions).
cat > /tmp/verify_fix.py << 'EOF'
import sys
import os
import numpy as np
import json

# Add project to path
sys.path.append(os.getcwd())

try:
    from audio_processor.utils import get_audio_duration
    from audio_processor.filters import apply_low_cut_filter
    from audio_processor.loudness import calculate_rms_amplitude
except ImportError as e:
    print(json.dumps({"error": f"Import failed: {e}"}))
    sys.exit(0)

results = {
    "bug1_duration_fixed": False,
    "bug2_filter_fixed": False,
    "bug3_rms_fixed": False
}

# Verify Bug 1: Duration
try:
    sr = 44100
    # Stereo array: (44100, 2) -> 1 second
    data = np.zeros((sr, 2))
    dur = get_audio_duration(data, sr)
    # Buggy version returns 2.0 (size/rate), Fixed returns 1.0
    if abs(dur - 1.0) < 0.001:
        results["bug1_duration_fixed"] = True
except Exception:
    pass

# Verify Bug 2: Filter
try:
    sr = 1000
    # Pass a cutoff of 100Hz. 
    # Buggy version: signal.butter(2, 100, ...) -> interprets 100 as normalized freq? 
    # Actually if cutoff > 1, scipy raises ValueError: "Digital filter critical frequencies must be 0 < Wn < 1"
    # So the buggy code likely CRASHES for Hz values > 1.
    # If the agent fixed it by normalizing or passing fs=sr, it won't crash.
    data = np.zeros(sr)
    try:
        apply_low_cut_filter(data, sr, cutoff_freq=100)
        # If we get here without crash, check if it's reasonable
        results["bug2_filter_fixed"] = True
    except ValueError as e:
        # Crash means likely not fixed
        pass
except Exception:
    pass

# Verify Bug 3: RMS
try:
    # Sine wave RMS = 0.707 * Amp
    # Mean Abs = 0.637 * Amp
    t = np.linspace(0, 1, 1000)
    data = np.sin(2 * np.pi * 50 * t)
    rms = calculate_rms_amplitude(data)
    if abs(rms - 0.7071) < 0.01:
        results["bug3_rms_fixed"] = True
except Exception:
    pass

print(json.dumps(results))
EOF

# Run verification script
VERIFY_JSON=$(python3 /tmp/verify_fix.py)

# Parse pytest output for specific test statuses
TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
TESTS_ERROR=$(echo "$PYTEST_OUTPUT" | grep -c " ERROR" || true)

# Construct result JSON
# Use python to merge the json string from verify script
python3 -c "
import json
import sys

verify_results = json.loads('$VERIFY_JSON')
output = {
    'pytest_exit_code': $PYTEST_EXIT_CODE,
    'tests_passed': $TESTS_PASSED,
    'tests_failed': $TESTS_FAILED,
    'tests_error': $TESTS_ERROR,
    'verify_script': verify_results,
    'task_start': $TASK_START,
    'timestamp': '$(date -Iseconds)'
}
print(json.dumps(output))
" > /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="