#!/bin/bash
echo "=== Exporting optimize_power_flow_solver result ==="

PROJECT_DIR="/home/ga/PycharmProjects/power_grid_sim"
RESULT_FILE="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Run Correctness Tests
echo "Running functional tests..."
cd "$PROJECT_DIR"
PYTEST_OUTPUT=$(su - ga -c "cd $PROJECT_DIR && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?
echo "$PYTEST_OUTPUT"

# 2. Run Performance Benchmark
echo "Running performance benchmark..."
su - ga -c "cd $PROJECT_DIR && python3 benchmark.py"
BENCHMARK_FILE="$PROJECT_DIR/benchmark_result.json"

# 3. Code Analysis (Check for numpy usage in loops)
# Heuristic: Check if 'for' loops over lines/buses are gone or reduced
ADMITTANCE_FILE="$PROJECT_DIR/power_grid/admittance.py"
SOLVER_FILE="$PROJECT_DIR/power_grid/solver.py"

# Check for numpy vectorization keywords/patterns
USES_NUMPY_SUM=$(grep -c "np.sum" "$SOLVER_FILE" || echo "0")
USES_MATMUL=$(grep -c "@" "$SOLVER_FILE" || echo "0")
USES_NUMPY_ADD_AT=$(grep -c "np.add.at" "$ADMITTANCE_FILE" || echo "0")

# Count remaining loops (less is better)
# Simple grep count of 'for ... in ...'
LOOP_COUNT_SOLVER=$(grep -c "for .* in .*" "$SOLVER_FILE" || echo "0")
LOOP_COUNT_ADMITTANCE=$(grep -c "for .* in .*" "$ADMITTANCE_FILE" || echo "0")

# 4. Read Benchmark Results
Y_BUS_TIME=0
SOLVE_TIME=0
TOTAL_TIME=0
V_REAL_SUM=0

if [ -f "$BENCHMARK_FILE" ]; then
    Y_BUS_TIME=$(python3 -c "import json; print(json.load(open('$BENCHMARK_FILE'))['y_bus_time'])" 2>/dev/null || echo "0")
    SOLVE_TIME=$(python3 -c "import json; print(json.load(open('$BENCHMARK_FILE'))['solve_time'])" 2>/dev/null || echo "0")
    TOTAL_TIME=$(python3 -c "import json; print(json.load(open('$BENCHMARK_FILE'))['total_time'])" 2>/dev/null || echo "0")
    V_REAL_SUM=$(python3 -c "import json; print(json.load(open('$BENCHMARK_FILE'))['voltage_sum_real'])" 2>/dev/null || echo "0")
fi

# 5. Take Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 6. Create Result JSON
cat > "$RESULT_FILE" << EOF
{
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "y_bus_time": $Y_BUS_TIME,
    "solve_time": $SOLVE_TIME,
    "total_time": $TOTAL_TIME,
    "voltage_checksum": $V_REAL_SUM,
    "static_analysis": {
        "uses_numpy_sum": $USES_NUMPY_SUM,
        "uses_matmul": $USES_MATMUL,
        "uses_add_at": $USES_NUMPY_ADD_AT,
        "loops_solver": $LOOP_COUNT_SOLVER,
        "loops_admittance": $LOOP_COUNT_ADMITTANCE
    }
}
EOF

# Ensure permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Export complete. Result:"
cat "$RESULT_FILE"