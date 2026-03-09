#!/bin/bash
echo "=== Exporting split_into_modules result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/petclinic-mono"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Attempt to run Maven build from the root
# This checks if the reactor is configured correctly (parent POM -> modules)
cd "$PROJECT_DIR"
echo "Running Maven build..."
MVN_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean package -DskipTests 2>&1)
MVN_EXIT_CODE=$?
echo "$MVN_OUTPUT" > /tmp/mvn_build.log

# 2. Check directory structure (Modules existence)
MODULE_MODEL_EXISTS="false"
MODULE_SERVICE_EXISTS="false"
MODULE_APP_EXISTS="false"
[ -d "$PROJECT_DIR/petclinic-model" ] && MODULE_MODEL_EXISTS="true"
[ -d "$PROJECT_DIR/petclinic-service" ] && MODULE_SERVICE_EXISTS="true"
[ -d "$PROJECT_DIR/petclinic-app" ] && MODULE_APP_EXISTS="true"

# 3. Check for JARs (proof of successful packaging per module)
JAR_MODEL_EXISTS="false"
JAR_SERVICE_EXISTS="false"
JAR_APP_EXISTS="false"
[ -f "$PROJECT_DIR/petclinic-model/target/petclinic-model-1.0-SNAPSHOT.jar" ] && JAR_MODEL_EXISTS="true"
[ -f "$PROJECT_DIR/petclinic-service/target/petclinic-service-1.0-SNAPSHOT.jar" ] && JAR_SERVICE_EXISTS="true"
[ -f "$PROJECT_DIR/petclinic-app/target/petclinic-app-1.0-SNAPSHOT.jar" ] && JAR_APP_EXISTS="true"

# 4. Check if root src folder is empty/removed (Clean split)
ROOT_SRC_CLEAN="false"
if [ ! -d "$PROJECT_DIR/src/main/java" ]; then
    ROOT_SRC_CLEAN="true"
elif [ -z "$(ls -A "$PROJECT_DIR/src/main/java" 2>/dev/null)" ]; then
    ROOT_SRC_CLEAN="true"
fi

# 5. Read POM contents for verifier analysis
cat "$PROJECT_DIR/pom.xml" > /tmp/pom_parent.xml 2>/dev/null || echo "" > /tmp/pom_parent.xml
cat "$PROJECT_DIR/petclinic-model/pom.xml" > /tmp/pom_model.xml 2>/dev/null || echo "" > /tmp/pom_model.xml
cat "$PROJECT_DIR/petclinic-service/pom.xml" > /tmp/pom_service.xml 2>/dev/null || echo "" > /tmp/pom_service.xml
cat "$PROJECT_DIR/petclinic-app/pom.xml" > /tmp/pom_app.xml 2>/dev/null || echo "" > /tmp/pom_app.xml

# Escape for JSON
escape_json() {
    python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))"
}

POM_PARENT_CONTENT=$(cat /tmp/pom_parent.xml | escape_json)
POM_MODEL_CONTENT=$(cat /tmp/pom_model.xml | escape_json)
POM_SERVICE_CONTENT=$(cat /tmp/pom_service.xml | escape_json)
POM_APP_CONTENT=$(cat /tmp/pom_app.xml | escape_json)
BUILD_LOG_CONTENT=$(tail -n 50 /tmp/mvn_build.log | escape_json)

# Create JSON Result
RESULT_JSON=$(cat << EOF
{
    "mvn_exit_code": $MVN_EXIT_CODE,
    "modules_found": {
        "model": $MODULE_MODEL_EXISTS,
        "service": $MODULE_SERVICE_EXISTS,
        "app": $MODULE_APP_EXISTS
    },
    "jars_found": {
        "model": $JAR_MODEL_EXISTS,
        "service": $JAR_SERVICE_EXISTS,
        "app": $JAR_APP_EXISTS
    },
    "root_src_clean": $ROOT_SRC_CLEAN,
    "pom_contents": {
        "parent": $POM_PARENT_CONTENT,
        "model": $POM_MODEL_CONTENT,
        "service": $POM_SERVICE_CONTENT,
        "app": $POM_APP_CONTENT
    },
    "build_log": $BUILD_LOG_CONTENT,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="