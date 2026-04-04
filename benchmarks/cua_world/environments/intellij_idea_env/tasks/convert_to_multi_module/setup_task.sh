#!/bin/bash
echo "=== Setting up convert_to_multi_module task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/java-library"

# Copy project from data directory
rm -rf "$PROJECT_DIR" 2>/dev/null || true
cp -r /workspace/data/java-library "$PROJECT_DIR"
chown -R ga:ga "$PROJECT_DIR"

# Pre-resolve Maven dependencies
su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn -q dependency:resolve -f '$PROJECT_DIR/pom.xml'" 2>/dev/null || true

# Verify the single-module project builds correctly at start
INITIAL_BUILD=$(su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn -q test -f '$PROJECT_DIR/pom.xml' 2>&1" && echo "BUILD_OK" || echo "BUILD_FAIL")
echo "$INITIAL_BUILD" > /tmp/initial_build_state.txt

# Record baseline: snapshot of the single-module structure
md5sum "$PROJECT_DIR/pom.xml" > /tmp/initial_root_pom_checksum.txt
echo "single_module" > /tmp/initial_module_structure.txt
find "$PROJECT_DIR/src" -name "*.java" | sort >> /tmp/initial_module_structure.txt

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Open the project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "java-library" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="
echo "Project: $PROJECT_DIR"
echo "Initial build state: $INITIAL_BUILD"
echo "The project is currently a single-module Maven build."
echo "Agent must convert it to a multi-module build with math/, strings/, collections/ modules."
