#!/bin/bash
echo "=== Setting up resolve_maven_dependencies task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/data-processor"

# Copy project from data directory
rm -rf "$PROJECT_DIR" 2>/dev/null || true
cp -r /workspace/data/data-processor "$PROJECT_DIR"
chown -R ga:ga "$PROJECT_DIR"

# Pre-resolve Maven dependencies (including commons-codec from central)
su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn -q dependency:resolve -f '$PROJECT_DIR/pom.xml'" 2>/dev/null || true

# Record baseline: checksum of pom.xml (must be modified by agent)
md5sum "$PROJECT_DIR/pom.xml" > /tmp/initial_pom_checksum.txt 2>/dev/null

# Record initial pom.xml content for comparison
cp "$PROJECT_DIR/pom.xml" /tmp/initial_pom.xml

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Open the project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "data-processor" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="
echo "Project: $PROJECT_DIR"
echo "Initial pom.xml saved to /tmp/initial_pom.xml"
