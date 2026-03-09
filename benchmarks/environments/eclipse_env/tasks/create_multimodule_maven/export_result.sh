#!/bin/bash
echo "=== Exporting create_multimodule_maven result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Task-specific variables
PARENT_DIR="/home/ga/eclipse-workspace/toolkit-parent"
CORE_DIR="$PARENT_DIR/toolkit-core"
APP_DIR="$PARENT_DIR/toolkit-app"

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- 1. Check File Existence ---
PARENT_EXISTS=$([ -d "$PARENT_DIR" ] && echo "true" || echo "false")
PARENT_POM_EXISTS=$([ -f "$PARENT_DIR/pom.xml" ] && echo "true" || echo "false")
CORE_POM_EXISTS=$([ -f "$CORE_DIR/pom.xml" ] && echo "true" || echo "false")
APP_POM_EXISTS=$([ -f "$APP_DIR/pom.xml" ] && echo "true" || echo "false")

STRING_UTILS_EXISTS=$(find "$CORE_DIR" -name "StringUtils.java" 2>/dev/null | wc -l)
MATH_UTILS_EXISTS=$(find "$CORE_DIR" -name "MathUtils.java" 2>/dev/null | wc -l)
MAIN_CLASS_EXISTS=$(find "$APP_DIR" -name "Main.java" 2>/dev/null | wc -l)

# --- 2. Run Maven Build ---
echo "Running Maven build..."
BUILD_SUCCESS="false"
MAVEN_OUTPUT=""

if [ "$PARENT_POM_EXISTS" = "true" ]; then
    # Run maven package skipping tests to focus on compilation/reactor structure first
    # We capture output to check for build success
    cd "$PARENT_DIR"
    MAVEN_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean package -DskipTests 2>&1)
    MAVEN_EXIT_CODE=$?
    
    if [ $MAVEN_EXIT_CODE -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
else
    MAVEN_OUTPUT="Parent directory or pom.xml not found."
fi

# --- 3. Run Application (Runtime Check) ---
echo "Running Application..."
RUNTIME_OUTPUT=""
RUNTIME_SUCCESS="false"

if [ "$BUILD_SUCCESS" = "true" ]; then
    # Try to find the built jars
    CORE_JAR=$(find "$CORE_DIR/target" -name "toolkit-core*.jar" | head -n 1)
    APP_JAR=$(find "$APP_DIR/target" -name "toolkit-app*.jar" | head -n 1)
    
    if [ -n "$CORE_JAR" ] && [ -n "$APP_JAR" ]; then
        # execute the main class
        RUNTIME_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 java -cp "$CORE_JAR:$APP_JAR" com.startup.toolkit.app.Main 2>&1)
        JAVA_EXIT_CODE=$?
        
        if [ $JAVA_EXIT_CODE -eq 0 ]; then
            RUNTIME_SUCCESS="true"
        fi
    else
        RUNTIME_OUTPUT="Build succeeded but JARs not found."
    fi
fi

# --- 4. Serialize content for verification ---
# We escape the output strings to ensure valid JSON
SAFE_MAVEN_OUTPUT=$(echo "$MAVEN_OUTPUT" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()[:5000]))")
SAFE_RUNTIME_OUTPUT=$(echo "$RUNTIME_OUTPUT" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()[:1000]))")

# Write result JSON
cat > /tmp/temp_result.json << EOF
{
    "parent_exists": $PARENT_EXISTS,
    "parent_pom_exists": $PARENT_POM_EXISTS,
    "core_pom_exists": $CORE_POM_EXISTS,
    "app_pom_exists": $APP_POM_EXISTS,
    "string_utils_exists": $STRING_UTILS_EXISTS,
    "math_utils_exists": $MATH_UTILS_EXISTS,
    "main_class_exists": $MAIN_CLASS_EXISTS,
    "build_success": $BUILD_SUCCESS,
    "maven_output": $SAFE_MAVEN_OUTPUT,
    "runtime_success": $RUNTIME_SUCCESS,
    "runtime_output": $SAFE_RUNTIME_OUTPUT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
write_json_result "$(cat /tmp/temp_result.json)" /tmp/task_result.json
rm -f /tmp/temp_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="