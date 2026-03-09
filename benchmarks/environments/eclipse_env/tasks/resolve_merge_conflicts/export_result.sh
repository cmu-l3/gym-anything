#!/bin/bash
echo "=== Exporting resolve_merge_conflicts result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/chinook-java"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Check Git Status
cd "$PROJECT_DIR"
GIT_STATUS=$(git status --porcelain)
GIT_LOG_COUNT=$(git log --oneline | wc -l)
LAST_COMMIT_PARENTS=$(git log -1 --pretty=%P)
PARENT_COUNT=$(echo $LAST_COMMIT_PARENTS | wc -w)

echo "Git Status: $GIT_STATUS"
echo "Parent Count: $PARENT_COUNT"

# 2. Check Compile Status
# Clean first to ensure we aren't seeing old classes
rm -rf target/classes
mvn compile -q > /tmp/mvn_compile.log 2>&1
COMPILE_EXIT_CODE=$?
echo "Maven Compile Exit Code: $COMPILE_EXIT_CODE"

# 3. Check for Conflict Markers in files
CONFLICT_MARKERS=$(grep -rE "<<<<<<<|=======|>>>>>>>" src/main/java pom.xml || true)
MARKER_COUNT=$(echo "$CONFLICT_MARKERS" | grep -v "^$" | wc -l)
echo "Conflict Marker Count: $MARKER_COUNT"

# 4. Verify Content Preservation (Simple Grep Checks for Export)
HAS_GSON=$(grep "gson" pom.xml > /dev/null && echo "true" || echo "false")
HAS_OPENCSV=$(grep "opencsv" pom.xml > /dev/null && echo "true" || echo "false")
HAS_STREAMING=$(grep "getStreamingQuality" src/main/java/com/chinook/model/Track.java > /dev/null && echo "true" || echo "false")
HAS_TOCSV=$(grep "toCsvRow" src/main/java/com/chinook/model/Track.java > /dev/null && echo "true" || echo "false")
HAS_DURATION=$(grep "getPlaylistDuration" src/main/java/com/chinook/service/PlaylistService.java > /dev/null && echo "true" || echo "false")
HAS_EXPORT=$(grep "exportToCsv" src/main/java/com/chinook/service/PlaylistService.java > /dev/null && echo "true" || echo "false")

# 5. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "git_clean": $([ -z "$GIT_STATUS" ] && echo "true" || echo "false"),
    "git_merge_commit_parents": $PARENT_COUNT,
    "compile_success": $([ $COMPILE_EXIT_CODE -eq 0 ] && echo "true" || echo "false"),
    "conflict_marker_count": $MARKER_COUNT,
    "features_preserved": {
        "gson_dependency": $HAS_GSON,
        "opencsv_dependency": $HAS_OPENCSV,
        "track_streaming": $HAS_STREAMING,
        "track_csv": $HAS_TOCSV,
        "playlist_duration": $HAS_DURATION,
        "playlist_export": $HAS_EXPORT
    },
    "timestamp": $(date +%s)
}
EOF

# Safe copy to avoid permission issues
cp /tmp/task_result.json /tmp/task_result_final.json
chmod 666 /tmp/task_result_final.json

echo "=== Export complete ==="
cat /tmp/task_result_final.json