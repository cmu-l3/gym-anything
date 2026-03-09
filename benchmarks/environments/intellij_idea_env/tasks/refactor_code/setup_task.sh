#!/bin/bash
echo "=== Setting up refactor_code task ==="

source /workspace/scripts/task_utils.sh

# Copy the project from data directory
rm -rf /home/ga/IdeaProjects/refactor-demo 2>/dev/null || true
cp -r /workspace/data/refactor-demo /home/ga/IdeaProjects/refactor-demo
chown -R ga:ga /home/ga/IdeaProjects/refactor-demo

# Record initial state (original Calculator.java content hash)
md5sum /home/ga/IdeaProjects/refactor-demo/src/main/java/org/lable/oss/helloworld/Calculator.java > /tmp/initial_calculator_hash.txt 2>/dev/null

# Open the project in IntelliJ and wait for it to fully load
setup_intellij_project "/home/ga/IdeaProjects/refactor-demo" "refactor-demo" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
