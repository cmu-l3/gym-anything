#!/bin/bash
# Export script for Configure Global Tools task
# Extract tool configuration from Jenkins via Groovy script

echo "=== Exporting Configure Global Tools Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Create Groovy script to inspect tool configuration
cat > /tmp/inspect_tools.groovy << 'GROOVY'
import jenkins.model.*
import hudson.model.*
import hudson.tasks.Maven.*
import hudson.tools.*
import groovy.json.JsonOutput

def result = [:]
def inst = Jenkins.instance

// Inspect JDKs
def jdkDesc = inst.getDescriptor("hudson.model.JDK")
result.jdks = jdkDesc.installations.collect { jdk ->
    [
        name: jdk.name,
        home: jdk.home
    ]
}

// Inspect Maven installations
def mavenDesc = inst.getDescriptor("hudson.tasks.Maven$DescriptorImpl")
result.mavens = mavenDesc.installations.collect { mvn ->
    // Check for auto installer
    def installer = mvn.properties.get(InstallSourceProperty.class)?.installers?.find { it instanceof hudson.tasks.Maven.MavenInstaller }
    
    [
        name: mvn.name,
        home: mvn.home,
        auto_install: installer != null,
        installer_id: installer?.id 
    ]
}

println JsonOutput.toJson(result)
GROOVY

# Execute script and capture JSON output
echo "Querying Jenkins for tool configuration..."
TOOLS_JSON=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" --data-urlencode "script=$(cat /tmp/inspect_tools.groovy)" "$JENKINS_URL/scriptText")

# Validate JSON output (simple check)
if [[ "$TOOLS_JSON" != *"{"* ]]; then
    echo "ERROR: Failed to get valid JSON from Jenkins API"
    echo "Response: $TOOLS_JSON"
    TOOLS_JSON="{}"
fi

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/tool_config_result.XXXXXX.json)
jq -n \
    --argjson tools "$TOOLS_JSON" \
    --argjson start_time "$TASK_START" \
    --argjson end_time "$TASK_END" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        tools: $tools,
        task_start: $start_time,
        task_end: $end_time,
        export_timestamp: $timestamp
    }' > "$TEMP_JSON"

# Save to final location
rm -f /tmp/configure_global_tools_result.json 2>/dev/null || sudo rm -f /tmp/configure_global_tools_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/configure_global_tools_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/configure_global_tools_result.json
chmod 666 /tmp/configure_global_tools_result.json 2>/dev/null || sudo chmod 666 /tmp/configure_global_tools_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/configure_global_tools_result.json"
cat /tmp/configure_global_tools_result.json

echo ""
echo "=== Export Complete ==="