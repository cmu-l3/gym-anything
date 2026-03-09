#!/bin/bash
set -e
echo "=== Setting up implement_soft_delete_view task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB to be ready
wait_for_orientdb 60

# 1. Clean up any previous attempts to ensure clean state
echo "Cleaning up previous runs..."
# Drop view if exists
orientdb_sql "demodb" "DROP VIEW PublicReviews UNSAFE" >/dev/null 2>&1 || true
# Drop property if exists
orientdb_sql "demodb" "DROP PROPERTY Reviews.IsHidden FORCE" >/dev/null 2>&1 || true

# 2. Inject Deterministic Data (Marker Records)
# We need these to be absolutely sure of the ground truth for verification
echo "Injecting marker reviews..."

# Delete existing markers if they exist (idempotency)
orientdb_sql "demodb" "DELETE VERTEX Reviews WHERE Text LIKE 'MARKER_%'" >/dev/null 2>&1 || true

# Marker 1: Toxic Review (1 star) - Should be HIDDEN
orientdb_sql "demodb" "INSERT INTO Reviews SET Stars=1, Text='MARKER_TOXIC_REVIEW', Date='2023-01-01'" >/dev/null

# Marker 2: Bad Review (2 stars) - Should be HIDDEN
orientdb_sql "demodb" "INSERT INTO Reviews SET Stars=2, Text='MARKER_BAD_REVIEW', Date='2023-01-02'" >/dev/null

# Marker 3: Good Review (5 stars) - Should be VISIBLE
orientdb_sql "demodb" "INSERT INTO Reviews SET Stars=5, Text='MARKER_GOOD_REVIEW', Date='2023-01-03'" >/dev/null

# Marker 4: Average Review (3 stars) - Should be VISIBLE
orientdb_sql "demodb" "INSERT INTO Reviews SET Stars=3, Text='MARKER_AVG_REVIEW', Date='2023-01-04'" >/dev/null

echo "Marker reviews injected."

# 3. Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# 4. Save Initial State Evidence
echo "Capturing initial screenshot..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="