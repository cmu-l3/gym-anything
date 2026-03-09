#!/bin/bash
echo "=== Setting up add_junit_tests task ==="

source /workspace/scripts/task_utils.sh

# Copy the project from data directory
rm -rf /home/ga/IdeaProjects/calculator-test 2>/dev/null || true
cp -r /workspace/data/calculator-test /home/ga/IdeaProjects/calculator-test
chown -R ga:ga /home/ga/IdeaProjects/calculator-test

# Record initial pom.xml hash (should be modified to add JUnit)
md5sum /home/ga/IdeaProjects/calculator-test/pom.xml > /tmp/initial_pom_hash.txt 2>/dev/null

# Open the project in IntelliJ and wait for it to fully load
setup_intellij_project "/home/ga/IdeaProjects/calculator-test" "calculator-test" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
