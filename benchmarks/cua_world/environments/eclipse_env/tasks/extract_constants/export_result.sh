#!/bin/bash
echo "=== Exporting extract_constants result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/PhysicsCalc"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Run Maven Compile & Test to verify integrity
echo "Running Maven build..."
cd "$PROJECT_DIR"
# Clean output files
rm -f /tmp/mvn_output.log
su - ga -c "cd $PROJECT_DIR && JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean compile test > /tmp/mvn_output.log 2>&1"
MVN_EXIT_CODE=$?

COMPILE_SUCCESS="false"
TESTS_PASSED="false"

if [ $MVN_EXIT_CODE -eq 0 ]; then
    COMPILE_SUCCESS="true"
    TESTS_PASSED="true"
else
    # Check if compile worked but tests failed
    if grep -q "BUILD SUCCESS" /tmp/mvn_output.log; then
        COMPILE_SUCCESS="true"
        TESTS_PASSED="true"
    elif grep -q "Compilation failure" /tmp/mvn_output.log; then
        COMPILE_SUCCESS="false"
    else
        # Compile might have worked, but tests failed
        if [ -d "$PROJECT_DIR/target/classes" ]; then
            COMPILE_SUCCESS="true"
        fi
    fi
fi

# 2. Analyze Source Code for Magic Numbers and Constants
# We use a python script embedded here to do robust checking
cat > /tmp/analyze_code.py << 'PYEOF'
import sys
import os
import re
import json
import glob

project_dir = sys.argv[1]
src_dir = os.path.join(project_dir, "src/main/java/com/physicscalc")

results = {
    "files": {},
    "all_magic_gone": True,
    "constants_defined": 0
}

# Regex to find 'static final' declarations
constant_decl_regex = re.compile(r'static\s+final\s+\w+\s+[A-Z0-9_]+\s*=\s*([^;]+);')

# Specific literals we wanted removed
target_literals = {
    "PhysicsConstants.java": ["9.80665", "299792458", "1.380649e-23"],
    "UnitConverter.java": ["1.60934", "0.453592", "32.0", "1.8"],
    "OrbitalMechanics.java": ["3.986004418e14", "6371000"],
    "NetworkConfig.java": ["8080", "30000", "3"]
}

for filename, literals in target_literals.items():
    filepath = os.path.join(src_dir, filename)
    file_result = {
        "modified": False,
        "constants_found": [],
        "magic_numbers_remaining": []
    }
    
    if os.path.exists(filepath):
        with open(filepath, 'r') as f:
            content = f.read()
            
        # Check modification time
        mtime = os.path.getmtime(filepath)
        start_time = float(sys.argv[2])
        if mtime > start_time:
            file_result["modified"] = True
            
        # Find defined constants
        for match in constant_decl_regex.finditer(content):
            file_result["constants_found"].append(match.group(0))
            results["constants_defined"] += 1
            
        # Check for remaining magic numbers in non-constant lines
        lines = content.split('\n')
        for line in lines:
            stripped = line.strip()
            # Skip comments and constant declarations
            if stripped.startswith('//') or 'static final' in line:
                continue
                
            for lit in literals:
                # Naive check: literal exists in line
                # Better: Check word boundaries or simple containment for numbers
                if lit in line:
                    file_result["magic_numbers_remaining"].append(lit)
                    results["all_magic_gone"] = False
                    
    results["files"][filename] = file_result

print(json.dumps(results))
PYEOF

echo "Analyzing code..."
ANALYSIS_JSON=$(python3 /tmp/analyze_code.py "$PROJECT_DIR" "$TASK_START")

# Escape analysis output for embedding
ANALYSIS_ESCAPED=$(echo "$ANALYSIS_JSON" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

# Create final result JSON
cat > /tmp/task_result.json << EOF
{
    "mvn_exit_code": $MVN_EXIT_CODE,
    "compile_success": $COMPILE_SUCCESS,
    "tests_passed": $TESTS_PASSED,
    "code_analysis": $ANALYSIS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe copy to output location
cp /tmp/task_result.json /tmp/result_copy.json
chmod 666 /tmp/result_copy.json
mv /tmp/result_copy.json /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json