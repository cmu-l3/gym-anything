#!/bin/bash
echo "=== Setting up fix_build_errors task ==="

source /workspace/scripts/task_utils.sh

# Copy the broken project from data directory
rm -rf /home/ga/IdeaProjects/gs-maven-broken 2>/dev/null || true
cp -r /workspace/data/gs-maven-broken /home/ga/IdeaProjects/gs-maven-broken
chown -R ga:ga /home/ga/IdeaProjects/gs-maven-broken

# Record initial file states for verification
md5sum /home/ga/IdeaProjects/gs-maven-broken/pom.xml > /tmp/initial_checksums.txt 2>/dev/null
md5sum /home/ga/IdeaProjects/gs-maven-broken/src/main/java/hello/HelloWorld.java >> /tmp/initial_checksums.txt 2>/dev/null
md5sum /home/ga/IdeaProjects/gs-maven-broken/src/main/java/hello/Greeter.java >> /tmp/initial_checksums.txt 2>/dev/null

# Open the project in IntelliJ and wait for it to fully load
setup_intellij_project "/home/ga/IdeaProjects/gs-maven-broken" "gs-maven-broken" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
