#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Integrate Custom Build Tool Task ==="

WORKSPACE_DIR="/home/ga/workspace/fastbuild_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$WORKSPACE_DIR/.vscode"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src"

# Create mock build tool (simulates proprietary compiler)
cat > "$WORKSPACE_DIR/fastbuild" << 'EOF'
#!/usr/bin/env python3
"""
FastBuild - Mock proprietary build tool
Outputs errors in non-standard format: <file>:<line>: <severity>: <message>
"""
import sys
import os

print("FastBuild Proprietary Compiler v3.2.1")
print("=" * 60)
print("Scanning dependencies...")
print("Building targets...")
print("")

# Simulate compilation errors
errors = [
    "src/main.cpp:15: ERROR: undefined variable 'counter'",
    "src/utils.cpp:42: WARNING: implicit type conversion from double to int",
    "src/parser.cpp:108: ERROR: expected ';' before '}' token",
]

for error in errors:
    print(error)

print("")
print("=" * 60)
print("Build FAILED: 2 errors, 1 warning")
print("")

sys.exit(1)
EOF

chmod +x "$WORKSPACE_DIR/fastbuild"

# Create source files with intentional errors (for realism)
cat > "$WORKSPACE_DIR/src/main.cpp" << 'EOF'
#include <iostream>

int main() {
    std::cout << "Hello World" << std::endl;
    
    // Line 15 will have error: undefined variable
    // This is just for context - the build tool is mocked
    counter++;  
    
    return 0;
}
EOF

cat > "$WORKSPACE_DIR/src/utils.cpp" << 'EOF'
#include <iostream>

// Line 42 will have warning: implicit conversion
void process(int value) {
    std::cout << "Processing: " << value << std::endl;
    
    double x = 3.14;
    int y = x;  // implicit conversion warning
    
    std::cout << "Result: " << y << std::endl;
}
EOF

cat > "$WORKSPACE_DIR/src/parser.cpp" << 'EOF'
#include <string>

// Line 108 will have error: missing semicolon
void parse() {
    bool flag = true;
    
    if (flag) {
        int x = 5
    }  // missing semicolon before }
    
    return;
}
EOF

# Create README with instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# FastBuild Project

This project uses a proprietary build tool called `fastbuild`.

## Problem

The build tool outputs errors but they don't show up in VSCode's Problems panel.

Error format: