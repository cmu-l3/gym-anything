#!/bin/bash
echo "=== Exporting refactor_robot_kinematics results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/robot_control"
RESULT_FILE="/tmp/task_result.json"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run tests (capture output and exit code)
echo "Running tests..."
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?
echo "Pytest exit code: $PYTEST_EXIT_CODE"

# Parse test results
PASSED_TESTS=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || echo "0")
FAILED_TESTS=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || echo "0")
TOTAL_TESTS=$((PASSED_TESTS + FAILED_TESTS))

# 3. Analyze File Structure
ROBOT_DIR_EXISTS=false
[ -d "$PROJECT_DIR/robot" ] && ROBOT_DIR_EXISTS=true

INIT_EXISTS=false
[ -f "$PROJECT_DIR/robot/__init__.py" ] && INIT_EXISTS=true

KINEMATICS_EXISTS=false
[ -f "$PROJECT_DIR/robot/kinematics.py" ] && KINEMATICS_EXISTS=true

TRAJECTORY_EXISTS=false
[ -f "$PROJECT_DIR/robot/trajectory.py" ] && TRAJECTORY_EXISTS=true

SAFETY_EXISTS=false
[ -f "$PROJECT_DIR/robot/safety.py" ] && SAFETY_EXISTS=true

ARM_EXISTS=false
[ -f "$PROJECT_DIR/robot/arm.py" ] && ARM_EXISTS=true

# 4. Analyze Code Content (AST Checks)
# We use a python script to verify classes exist and verify test imports
PYTHON_CHECKS=$(python3 - <<END_PYTHON
import ast
import os
import json

results = {
    "kinematics_class": False,
    "trajectory_class": False,
    "safety_class": False,
    "arm_class": False,
    "init_exports": False,
    "test_imports_correct": False,
    "composition_used": False
}

project_dir = "$PROJECT_DIR"

def check_class(path, class_name):
    if not os.path.exists(path): return False
    try:
        with open(path, 'r') as f:
            tree = ast.parse(f.read())
            for node in ast.walk(tree):
                if isinstance(node, ast.ClassDef) and node.name == class_name:
                    return True
    except:
        pass
    return False

# Check classes in new modules
results["kinematics_class"] = check_class(os.path.join(project_dir, "robot/kinematics.py"), "Kinematics")
results["trajectory_class"] = check_class(os.path.join(project_dir, "robot/trajectory.py"), "TrajectoryPlanner")
results["safety_class"] = check_class(os.path.join(project_dir, "robot/safety.py"), "SafetyMonitor")
results["arm_class"] = check_class(os.path.join(project_dir, "robot/arm.py"), "RobotArm")

# Check __init__.py exports (naive text check)
try:
    init_path = os.path.join(project_dir, "robot/__init__.py")
    if os.path.exists(init_path):
        with open(init_path, 'r') as f:
            content = f.read()
            if "RobotArm" in content and "Kinematics" in content:
                results["init_exports"] = True
except:
    pass

# Check composition in arm.py
# Look for instantiation of Kinematics/Trajectory/Safety in RobotArm
try:
    arm_path = os.path.join(project_dir, "robot/arm.py")
    if os.path.exists(arm_path):
        with open(arm_path, 'r') as f:
            content = f.read()
            # Loose check: does it mention the other classes?
            if "Kinematics(" in content and "TrajectoryPlanner(" in content:
                results["composition_used"] = True
            elif "self.kinematics" in content and "self.trajectory" in content:
                results["composition_used"] = True
except:
    pass

# Check test imports
# Should NOT import from robot_arm
try:
    test_path = os.path.join(project_dir, "tests/test_robot.py")
    with open(test_path, 'r') as f:
        content = f.read()
        if "from robot import" in content or "from robot.arm import" in content:
            if "from robot_arm import" not in content:
                results["test_imports_correct"] = True
except:
    pass

print(json.dumps(results))
END_PYTHON
)

# 5. Compile Result
cat > "$RESULT_FILE" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "passed_tests": $PASSED_TESTS,
    "total_tests": $TOTAL_TESTS,
    "structure": {
        "robot_dir": $ROBOT_DIR_EXISTS,
        "init_py": $INIT_EXISTS,
        "kinematics_py": $KINEMATICS_EXISTS,
        "trajectory_py": $TRAJECTORY_EXISTS,
        "safety_py": $SAFETY_EXISTS,
        "arm_py": $ARM_EXISTS
    },
    "content_analysis": $PYTHON_CHECKS
}
EOF

# Move result to safe location
cp "$RESULT_FILE" /tmp/task_result.json.final
mv /tmp/task_result.json.final /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="