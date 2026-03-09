#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Experiment Compiler Flags Task ==="

WORKSPACE_DIR="/home/ga/workspace/performance_test"
ASSETS_DIR="/workspace/tasks/experiment_compiler_flags/assets"

# Create workspace directory
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Install g++ if not present
if ! command -v g++ &> /dev/null; then
    echo "Installing g++..."
    apt-get update -qq
    apt-get install -y -qq g++ build-essential
fi

# Copy benchmark.cpp from assets
if [ -f "$ASSETS_DIR/benchmark.cpp" ]; then
    sudo -u ga cp "$ASSETS_DIR/benchmark.cpp" "$WORKSPACE_DIR/"
    echo "✅ Copied benchmark.cpp"
else
    echo "⚠️ Warning: benchmark.cpp not found, creating default"
    cat > "$WORKSPACE_DIR/benchmark.cpp" << 'EOF'
#include <iostream>
#include <chrono>
#include <cmath>

// Compute-intensive function for testing optimization
double compute_intensive(int iterations) {
    double result = 0.0;
    for (int i = 0; i < iterations; i++) {
        result += std::sqrt(i) * std::sin(i) * std::cos(i);
    }
    return result;
}

int main() {
    auto start = std::chrono::high_resolution_clock::now();
    
    double result = compute_intensive(10000000);
    
    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
    
    std::cout << "Result: " << result << std::endl;
    std::cout << "Time: " << duration.count() << "ms" << std::endl;
    
    return 0;
}
EOF
fi

# Copy README.txt from assets
if [ -f "$ASSETS_DIR/README.txt" ]; then
    sudo -u ga cp "$ASSETS_DIR/README.txt" "$WORKSPACE_DIR/"
    echo "✅ Copied README.txt"
else
    cat > "$WORKSPACE_DIR/README.txt" << 'EOF'
GCC Optimization Levels:
- O0: No optimization (default), best for debugging
- O2: Moderate optimization, good balance (recommended for production)
- O3: Aggressive optimization, may increase binary size
- Ofast: Enables all O3 optimizations plus unsafe math optimizations

Your task: Set up VSCode tasks to easily compare these optimization levels.

Instructions:
1. Create .vscode/tasks.json in this directory
2. Define at least 4 tasks with different optimization flags
3. Each task should compile benchmark.cpp with g++
4. Use different output names (e.g., benchmark_O0, benchmark_O2)
5. Give each task a descriptive label
EOF
fi

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Experiment Compiler Flags Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Create .vscode/ directory in workspace"
echo "  2. Create tasks.json with version 2.0.0"
echo "  3. Add 4+ build tasks with different optimization flags"
echo "  4. Each task should:"
echo "     - Use g++ to compile benchmark.cpp"
echo "     - Have unique optimization flag (-O0, -O2, -O3, -Ofast)"
echo "     - Output to unique binary name (e.g., benchmark_O0)"
echo "     - Have descriptive label"
echo ""
echo "Workspace: $WORKSPACE_DIR"