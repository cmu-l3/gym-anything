#!/bin/bash
set -e
echo "=== Setting up customize_code_templates task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define workspace and project paths
WORKSPACE="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE/BankSystem"

# Ensure Eclipse is running
if ! pgrep -f "eclipse" > /dev/null; then
    echo "Starting Eclipse..."
    # Launch logic is handled by env hooks, but we ensure it's up
    # Using task_utils wait function
    wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"
fi

# Clean up any previous run artifacts
echo "Cleaning up previous runs..."
rm -rf "$PROJECT_DIR" 2>/dev/null || true

# Create the BankSystem project structure manually
# We create a barebones .project and .classpath so it appears in Eclipse
# This simulates "Starting State: Eclipse IDE is open with a project named BankSystem"
mkdir -p "$PROJECT_DIR/src"
mkdir -p "$PROJECT_DIR/bin"

# Create .project
cat > "$PROJECT_DIR/.project" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>BankSystem</name>
	<comment></comment>
	<projects>
	</projects>
	<buildSpec>
		<buildCommand>
			<name>org.eclipse.jdt.core.javabuilder</name>
			<arguments>
			</arguments>
		</buildCommand>
	</buildSpec>
	<natures>
		<nature>org.eclipse.jdt.core.javanature</nature>
	</natures>
</projectDescription>
EOF

# Create .classpath
cat > "$PROJECT_DIR/.classpath" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
	<classpathentry kind="src" path="src"/>
	<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER"/>
	<classpathentry kind="output" path="bin"/>
</classpath>
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Reset JDT UI preferences to remove any pre-existing templates (ensure clean state)
PREFS_DIR="$WORKSPACE/.metadata/.plugins/org.eclipse.core.runtime/.settings"
mkdir -p "$PREFS_DIR"
rm -f "$PREFS_DIR/org.eclipse.jdt.ui.prefs" 2>/dev/null || true
chown -R ga:ga "$PREFS_DIR"

# Focus and maximize Eclipse
focus_eclipse_window
sleep 2

# Refresh workspace (F5) or Import logic would ideally happen here, 
# but simply having the folder might not show it if Eclipse is already open.
# We will restart Eclipse to ensure it picks up the project if it's not showing,
# OR we rely on the agent to potentially import it if it's missing, 
# BUT the prompt implies it's there. 
# To be safe, we'll try to trigger a refresh via filesystem hooks if Eclipse supports it,
# otherwise, we assume the agent can see it or we rely on the environment start to pick it up.
# Since we are creating the files *while* Eclipse is running, we might need to Refresh.
# We'll rely on the agent seeing the project or Importing "Existing Projects" if needed, 
# but usually `setup_eclipse.sh` opens the workspace. If we add files now, they might not appear until refresh.
# Let's assume the standard environment setup.

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="