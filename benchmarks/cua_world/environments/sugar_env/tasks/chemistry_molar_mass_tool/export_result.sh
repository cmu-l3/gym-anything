#!/bin/bash
echo "=== Exporting chemistry_molar_mass_tool task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_final.png" 2>/dev/null || true

SCRIPT_PATH="/home/ga/Documents/molar_mass.py"
RESULTS_PATH="/home/ga/Documents/results.txt"

# Ensure the python script is executable if it exists
if [ -f "$SCRIPT_PATH" ]; then
    chmod +x "$SCRIPT_PATH"
fi

# Run dynamic tests securely inside the container and capture outputs
# Timeout of 5 seconds per execution prevents infinite loops
TEST_HCL=$(su - ga -c "timeout 5 python3 $SCRIPT_PATH HCl" 2>/dev/null || echo "EXEC_FAILED")
TEST_NA2SO4=$(su - ga -c "timeout 5 python3 $SCRIPT_PATH Na2SO4" 2>/dev/null || echo "EXEC_FAILED")
TEST_CAFFEINE=$(su - ga -c "timeout 5 python3 $SCRIPT_PATH C8H10N4O2" 2>/dev/null || echo "EXEC_FAILED")
TEST_O2=$(su - ga -c "timeout 5 python3 $SCRIPT_PATH O2" 2>/dev/null || echo "EXEC_FAILED")

# Export everything nicely via Python to avoid Bash escaping hell
python3 << PYEOF
import json
import os

result = {
    "script_exists": os.path.exists("$SCRIPT_PATH"),
    "results_exists": os.path.exists("$RESULTS_PATH"),
    "results_content": "",
    "dynamic_tests": {
        "HCl": """$TEST_HCL""",
        "Na2SO4": """$TEST_NA2SO4""",
        "C8H10N4O2": """$TEST_CAFFEINE""",
        "O2": """$TEST_O2"""
    }
}

if result["results_exists"]:
    try:
        with open("$RESULTS_PATH", "r", encoding="utf-8") as f:
            result["results_content"] = f.read()
    except Exception as e:
        result["results_content"] = f"ERROR_READING_FILE: {e}"

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="