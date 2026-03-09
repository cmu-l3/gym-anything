#!/bin/bash
echo "=== Setting up Identify Large Artifacts Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Prepare Artifacts (Real Data)
# ============================================================
ARTIFACTS_DIR="/home/ga/artifacts"
mkdir -p "$ARTIFACTS_DIR"

# Ensure we have the small artifacts (from env setup)
# Commons Lang (~600KB)
LANG_JAR="${ARTIFACTS_DIR}/commons-lang3/commons-lang3-3.14.0.jar"
if [ ! -f "$LANG_JAR" ]; then
    echo "Downloading commons-lang3..."
    mkdir -p "$(dirname "$LANG_JAR")"
    wget -q -O "$LANG_JAR" "https://repo1.maven.org/maven2/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"
fi

# Commons IO (~500KB)
IO_JAR="${ARTIFACTS_DIR}/commons-io/commons-io-2.15.1.jar"
if [ ! -f "$IO_JAR" ]; then
    echo "Downloading commons-io..."
    mkdir -p "$(dirname "$IO_JAR")"
    wget -q -O "$IO_JAR" "https://repo1.maven.org/maven2/org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar"
fi

# Download a LARGE artifact (> 5MB)
# Apache Tomcat 9.0.85 .tar.gz is ~11.5 MB
TOMCAT_VERSION="9.0.85"
TOMCAT_FILE="apache-tomcat-${TOMCAT_VERSION}.tar.gz"
TOMCAT_PATH="${ARTIFACTS_DIR}/${TOMCAT_FILE}"
TOMCAT_URL="https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/${TOMCAT_FILE}"

if [ ! -f "$TOMCAT_PATH" ]; then
    echo "Downloading large artifact (Tomcat)..."
    wget -q -O "$TOMCAT_PATH" "$TOMCAT_URL" || echo "Failed to download Tomcat"
fi

# Fallback generation if download fails (ensure task is playable)
if [ ! -f "$TOMCAT_PATH" ] || [ ! -s "$TOMCAT_PATH" ]; then
    echo "Creating synthetic large file (fallback)..."
    dd if=/dev/zero of="$TOMCAT_PATH" bs=1M count=12
fi

# ============================================================
# 2. Deploy Artifacts to Artifactory
# ============================================================
echo "Waiting for Artifactory..."
wait_for_artifactory 60

REPO="example-repo-local"

# Function to deploy file
deploy_file() {
    local file_path="$1"
    local target_path="$2"
    
    if [ -f "$file_path" ]; then
        echo "Deploying $(basename "$file_path") to $REPO..."
        curl -s -u admin:password -X PUT \
            "http://localhost:8082/artifactory/${REPO}/${target_path}" \
            -T "$file_path" > /dev/null
    else
        echo "Warning: Source file $file_path not found, skipping deployment."
    fi
}

# Deploy Small Files
deploy_file "$LANG_JAR" "org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"
deploy_file "$IO_JAR" "org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar"

# Deploy Large File
deploy_file "$TOMCAT_PATH" "org/apache/tomcat/tomcat/${TOMCAT_VERSION}/${TOMCAT_FILE}"

# Add a medium file (boundary check, e.g., 2MB) - using a dummy for speed if needed, 
# but let's stick to real files. We'll verify against the 5MB threshold.

# ============================================================
# 3. UI Setup
# ============================================================
# Ensure previous result is gone
rm -f /home/ga/large_artifacts.txt

# Start Firefox and navigate to Artifacts browser
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082/ui/packages" 
sleep 5
navigate_to "http://localhost:8082/ui/repos/tree/General/${REPO}"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="