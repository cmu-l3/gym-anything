#!/bin/bash
set -e
echo "=== Setting up backup_large_artifacts task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Artifactory
echo "Waiting for Artifactory to be ready..."
wait_for_artifactory 300

# 2. Prepare Data (Generate files locally then upload)
echo "Generating test artifacts..."
DATA_GEN_DIR="/tmp/artifactory_data_gen"
mkdir -p "$DATA_GEN_DIR"

# File 1: Large SQL Dump (~6.5MB)
dd if=/dev/urandom of="$DATA_GEN_DIR/db_dump_2024.sql" bs=1024 count=6500 2>/dev/null
# File 2: Large Video (~8.2MB)
dd if=/dev/urandom of="$DATA_GEN_DIR/marketing_video_raw.mp4" bs=1024 count=8200 2>/dev/null
# File 3: Small Config (~1.5KB)
echo '{"settings": {"theme": "dark", "retries": 3}}' > "$DATA_GEN_DIR/app_config.json"
# File 4: Medium JAR (~1.2MB) - smaller than threshold
dd if=/dev/urandom of="$DATA_GEN_DIR/commons_util.jar" bs=1024 count=1200 2>/dev/null

# Calculate checksums for verification later
sha256sum "$DATA_GEN_DIR/"* > /tmp/ground_truth_checksums.txt

# 3. Upload artifacts to 'example-repo-local'
echo "Uploading artifacts to example-repo-local..."

# Ensure repo exists (it should be default, but just in case)
if ! repo_exists "example-repo-local"; then
    echo "Creating example-repo-local..."
    # Simple creation via curl if missing
    curl -u admin:password -X PUT -H "Content-Type: application/json" \
        -d '{"rclass":"local","packageType":"generic"}' \
        "http://localhost:8082/artifactory/api/repositories/example-repo-local"
fi

# Upload files
curl -u admin:password -T "$DATA_GEN_DIR/db_dump_2024.sql" "http://localhost:8082/artifactory/example-repo-local/backups/sql/db_dump_2024.sql"
curl -u admin:password -T "$DATA_GEN_DIR/marketing_video_raw.mp4" "http://localhost:8082/artifactory/example-repo-local/media/videos/marketing_video_raw.mp4"
curl -u admin:password -T "$DATA_GEN_DIR/app_config.json" "http://localhost:8082/artifactory/example-repo-local/config/app_config.json"
curl -u admin:password -T "$DATA_GEN_DIR/commons_util.jar" "http://localhost:8082/artifactory/example-repo-local/libs/commons_util.jar"

# Cleanup local generation files (so agent can't just find them in /tmp)
rm -rf "$DATA_GEN_DIR"

# 4. Ensure backup directory does NOT exist
rm -rf "/home/ga/large_files_backup"

# 5. Launch Firefox
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082/ui/packages"

# 6. Record timestamps
date +%s > /tmp/task_start_time.txt

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="