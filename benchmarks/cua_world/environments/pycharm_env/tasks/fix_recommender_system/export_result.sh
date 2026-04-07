#!/bin/bash
echo "=== Exporting fix_recommender_system result ==="

PROJECT_DIR="/home/ga/PycharmProjects/recommender_system"
RESULT_FILE="/tmp/recommender_result.json"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Run the visible test suite
echo "Running visible tests..."
cd "$PROJECT_DIR"
# Force install deps if missing (anti-frustration)
pip install -r requirements.txt > /dev/null 2>&1 || true

VISIBLE_TEST_OUTPUT=$(su - ga -c "cd $PROJECT_DIR && python3 -m pytest tests/ -v 2>&1")
VISIBLE_EXIT_CODE=$?

TESTS_PASSED=$(echo "$VISIBLE_TEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$VISIBLE_TEST_OUTPUT" | grep -c " FAILED" || true)
ALL_TESTS_PASS=false
[ "$VISIBLE_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

# 2. Run HIDDEN verification
# We create a temporary verification script that imports the agent's code
# and tests it against known logic cases. This prevents hardcoding to pass visible tests.
cat > /tmp/hidden_verify.py << 'VERIFY_EOF'
import sys
import json
import numpy as np

# Add project to path
sys.path.append("/home/ga/PycharmProjects/recommender_system")

results = {
    "bug1_fixed": False,
    "bug2_fixed": False,
    "bug3_fixed": False
}

try:
    from engine.similarity import calculate_cosine_similarity
    # Test: v1=[1,1], v2=[2,2]. Cosine should be 1.0.
    # Buggy (sum): (1+1+2+2) = 6 denom? No, sum(A)*sum(B) = 2*4 = 8. Dot = 4. 4/8 = 0.5 (WRONG)
    # Correct (norm): sqrt(2)*sqrt(8) = 1.414*2.828 = 4. 4/4 = 1.0 (CORRECT)
    v1 = np.array([1, 1])
    v2 = np.array([2, 2])
    sim = calculate_cosine_similarity(v1, v2)
    if abs(sim - 1.0) < 0.01:
        results["bug1_fixed"] = True
except Exception as e:
    print(f"Error checking Bug 1: {e}")

try:
    from engine.selection import get_top_k_neighbors
    # Test: [0.1, 0.9, 0.2]. Top 1 should be index 1 (0.9).
    # Buggy (argsort[:k]): sorted=[0.1, 0.2, 0.9] indices=[0, 2, 1]. [:1] -> 0 (0.1) WRONG
    # Correct: index 1
    indices = get_top_k_neighbors([0.1, 0.9, 0.2], k=1)
    if len(indices) == 1 and indices[0] == 1:
        results["bug2_fixed"] = True
    # Also check if they reversed it or took tail
    elif len(indices) == 1 and 1 in indices:
        results["bug2_fixed"] = True
except Exception as e:
    print(f"Error checking Bug 2: {e}")

try:
    from engine.prediction import predict_score
    # Test: ratings=[10], weights=[0.5]. 
    # Buggy (div by count): (10*0.5) / 1 = 5.0 (WRONG logic for weighted avg, usually)
    # Actually wait - weighted average formula: sum(r*w)/sum(w).
    # Correct: (10*0.5)/0.5 = 10.0.
    # Buggy code was: sum(r*w) / len(r) = 5.0 / 1 = 5.0.
    pred = predict_score([10.0], [0.5])
    if abs(pred - 10.0) < 0.1:
        results["bug3_fixed"] = True
except Exception as e:
    print(f"Error checking Bug 3: {e}")

print(json.dumps(results))
VERIFY_EOF

echo "Running hidden logic verification..."
HIDDEN_OUTPUT=$(su - ga -c "python3 /tmp/hidden_verify.py" 2>/dev/null || echo '{"bug1_fixed": false, "bug2_fixed": false, "bug3_fixed": false}')

# Extract boolean values from JSON
BUG1_FIXED=$(echo "$HIDDEN_OUTPUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('bug1_fixed', False))")
BUG2_FIXED=$(echo "$HIDDEN_OUTPUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('bug2_fixed', False))")
BUG3_FIXED=$(echo "$HIDDEN_OUTPUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('bug3_fixed', False))")

# Create final JSON result
cat > "$RESULT_FILE" << EOF
{
    "visible_tests_passed": $ALL_TESTS_PASS,
    "tests_passed_count": $TESTS_PASSED,
    "tests_failed_count": $TESTS_FAILED,
    "bug1_logic_correct": $BUG1_FIXED,
    "bug2_logic_correct": $BUG2_FIXED,
    "bug3_logic_correct": $BUG3_FIXED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Fix permissions
chmod 666 "$RESULT_FILE"

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"