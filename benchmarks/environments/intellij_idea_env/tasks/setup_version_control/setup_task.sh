#!/bin/bash
echo "=== Setting up setup_version_control task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/sort-algorithms"

# Copy project from data directory
rm -rf "$PROJECT_DIR" 2>/dev/null || true
cp -r /workspace/data/sort-algorithms "$PROJECT_DIR"
chown -R ga:ga "$PROJECT_DIR"

# Ensure there is NO .git directory (the agent must create it)
rm -rf "$PROJECT_DIR/.git" 2>/dev/null || true
rm -f "$PROJECT_DIR/.gitignore" 2>/dev/null || true

# Pre-resolve Maven dependencies
su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn -q dependency:resolve -f '$PROJECT_DIR/pom.xml'" 2>/dev/null || true

# Verify git is available
if ! command -v git &>/dev/null; then
    apt-get install -y git 2>/dev/null || true
fi
git config --global user.email "ga@localhost" 2>/dev/null || true
git config --global user.name "Developer" 2>/dev/null || true

# Record that no .git exists at task start
echo "no_git" > /tmp/initial_git_state.txt
echo "$(ls -la $PROJECT_DIR)" >> /tmp/initial_git_state.txt

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Open the project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "sort-algorithms" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="
echo "Project: $PROJECT_DIR"
echo "No .git directory present — agent must initialize VCS"
