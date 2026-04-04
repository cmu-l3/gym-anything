#!/bin/bash
echo "=== Exporting animate_ghibli_scene task result ==="

TASK_DIR="/home/ga/OpenToonz/task"
OUTPUT_DIR="$TASK_DIR/agent_output"
REFERENCE_VIDEO="$TASK_DIR/reference_animation.mp4"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

# Initialize result variables
AGENT_VIDEO_FOUND="false"
AGENT_VIDEO_PATH=""
AGENT_VIDEO_SIZE_KB=0
AGENT_FRAME_COUNT=0
HAS_MOTION="false"
MOTION_SCORE=0

# Check for agent output video
if [ -d "$OUTPUT_DIR" ]; then
    # Look for video files
    AGENT_VIDEO=$(find "$OUTPUT_DIR" -name "*.mp4" -type f 2>/dev/null | head -1)

    if [ -z "$AGENT_VIDEO" ]; then
        # Try other formats
        AGENT_VIDEO=$(find "$OUTPUT_DIR" -name "*.avi" -o -name "*.mov" -o -name "*.gif" -type f 2>/dev/null | head -1)
    fi

    if [ -n "$AGENT_VIDEO" ] && [ -f "$AGENT_VIDEO" ]; then
        AGENT_VIDEO_FOUND="true"
        AGENT_VIDEO_PATH="$AGENT_VIDEO"
        AGENT_VIDEO_SIZE_KB=$(du -k "$AGENT_VIDEO" | cut -f1)

        # Get frame count using ffprobe
        AGENT_FRAME_COUNT=$(ffprobe -v error -count_frames -select_streams v:0 \
            -show_entries stream=nb_read_frames -of default=nokey=1:noprint_wrappers=1 \
            "$AGENT_VIDEO" 2>/dev/null || echo "0")

        # Check for motion by comparing frames
        # Extract first and last frames and compare
        TEMP_FIRST="/tmp/agent_first.png"
        TEMP_LAST="/tmp/agent_last.png"

        ffmpeg -y -i "$AGENT_VIDEO" -vf "select=eq(n\\,0)" -vframes 1 "$TEMP_FIRST" 2>/dev/null
        ffmpeg -y -i "$AGENT_VIDEO" -vf "select=eq(n\\,$((AGENT_FRAME_COUNT-1)))" -vframes 1 "$TEMP_LAST" 2>/dev/null

        if [ -f "$TEMP_FIRST" ] && [ -f "$TEMP_LAST" ]; then
            # Calculate difference using ImageMagick
            DIFF_RESULT=$(compare -metric RMSE "$TEMP_FIRST" "$TEMP_LAST" /tmp/diff.png 2>&1 | head -1)
            # Extract numeric value
            DIFF_VALUE=$(echo "$DIFF_RESULT" | grep -oE '^[0-9.]+' || echo "0")

            if [ -n "$DIFF_VALUE" ] && [ "$(echo "$DIFF_VALUE > 100" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
                HAS_MOTION="true"
                # Normalize to 0-1 score (higher diff = more motion)
                MOTION_SCORE=$(echo "scale=2; $DIFF_VALUE / 10000" | bc -l 2>/dev/null || echo "0.5")
                if [ "$(echo "$MOTION_SCORE > 1" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
                    MOTION_SCORE="1.0"
                fi
            fi
        fi

        rm -f "$TEMP_FIRST" "$TEMP_LAST" /tmp/diff.png 2>/dev/null
    fi

    # Also check for frame sequences
    if [ "$AGENT_VIDEO_FOUND" = "false" ]; then
        FRAME_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -type f 2>/dev/null | wc -l)
        if [ "$FRAME_COUNT" -gt 10 ]; then
            AGENT_VIDEO_FOUND="true"
            AGENT_VIDEO_PATH="$OUTPUT_DIR (frame sequence)"
            AGENT_FRAME_COUNT=$FRAME_COUNT
            AGENT_VIDEO_SIZE_KB=$(du -sk "$OUTPUT_DIR" | cut -f1)

            # Check motion between first and last frames
            FIRST_FRAME=$(find "$OUTPUT_DIR" -name "*.png" | sort | head -1)
            LAST_FRAME=$(find "$OUTPUT_DIR" -name "*.png" | sort | tail -1)

            if [ -f "$FIRST_FRAME" ] && [ -f "$LAST_FRAME" ]; then
                DIFF_RESULT=$(compare -metric RMSE "$FIRST_FRAME" "$LAST_FRAME" /tmp/diff.png 2>&1 | head -1)
                DIFF_VALUE=$(echo "$DIFF_RESULT" | grep -oE '^[0-9.]+' || echo "0")
                if [ -n "$DIFF_VALUE" ] && [ "$(echo "$DIFF_VALUE > 100" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
                    HAS_MOTION="true"
                    MOTION_SCORE=$(echo "scale=2; $DIFF_VALUE / 10000" | bc -l 2>/dev/null || echo "0.5")
                fi
            fi
            rm -f /tmp/diff.png 2>/dev/null
        fi
    fi
fi

# Check reference video exists
REFERENCE_EXISTS="false"
REFERENCE_FRAME_COUNT=0
if [ -f "$REFERENCE_VIDEO" ]; then
    REFERENCE_EXISTS="true"
    REFERENCE_FRAME_COUNT=$(ffprobe -v error -count_frames -select_streams v:0 \
        -show_entries stream=nb_read_frames -of default=nokey=1:noprint_wrappers=1 \
        "$REFERENCE_VIDEO" 2>/dev/null || echo "60")
fi

# Check OpenToonz project state
PROJECT_MODIFIED="false"
CLEAN_PROJECT="$TASK_DIR/clean_project.tnz"
if [ -f "$CLEAN_PROJECT" ]; then
    # Check if project was modified (file mod time)
    ORIGINAL_TIME=$(stat -c %Y "$CLEAN_PROJECT" 2>/dev/null || echo "0")
    CURRENT_TIME=$(date +%s)
    if [ $((CURRENT_TIME - ORIGINAL_TIME)) -lt 600 ]; then
        PROJECT_MODIFIED="true"
    fi
fi

# Check if agent saved a modified project
AGENT_PROJECT_FOUND="false"
AGENT_PROJECT_PATH=""
AGENT_PROJECT=$(find "$TASK_DIR" -name "*.tnz" -newer /tmp/task_start.png 2>/dev/null | head -1)
if [ -n "$AGENT_PROJECT" ] && [ "$AGENT_PROJECT" != "$CLEAN_PROJECT" ]; then
    AGENT_PROJECT_FOUND="true"
    AGENT_PROJECT_PATH="$AGENT_PROJECT"
fi

# Get output file count
INITIAL_COUNT=$(cat /tmp/initial_output_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(find "$OUTPUT_DIR" -type f \( -name "*.mp4" -o -name "*.png" -o -name "*.gif" -o -name "*.avi" \) 2>/dev/null | wc -l)

# Check OpenToonz windows
OPENTOONZ_RUNNING="false"
WINDOW_TITLE=""
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "opentoonz"; then
    OPENTOONZ_RUNNING="true"
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "opentoonz" | head -1)
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "agent_video_found": $AGENT_VIDEO_FOUND,
    "agent_video_path": "$AGENT_VIDEO_PATH",
    "agent_video_size_kb": $AGENT_VIDEO_SIZE_KB,
    "agent_frame_count": $AGENT_FRAME_COUNT,
    "has_motion": $HAS_MOTION,
    "motion_score": $MOTION_SCORE,
    "reference_exists": $REFERENCE_EXISTS,
    "reference_frame_count": $REFERENCE_FRAME_COUNT,
    "reference_video_path": "$REFERENCE_VIDEO",
    "project_modified": $PROJECT_MODIFIED,
    "agent_project_found": $AGENT_PROJECT_FOUND,
    "agent_project_path": "$AGENT_PROJECT_PATH",
    "opentoonz_running": $OPENTOONZ_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "initial_output_count": $INITIAL_COUNT,
    "current_output_count": $CURRENT_COUNT,
    "ghibli_image_path": "$TASK_DIR/ghibli_scene.jpg",
    "clean_project_path": "$CLEAN_PROJECT",
    "output_dir": "$OUTPUT_DIR",
    "screenshot_path": "/tmp/task_end.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Copy agent video for verification if it exists
if [ "$AGENT_VIDEO_FOUND" = "true" ] && [ -f "$AGENT_VIDEO_PATH" ]; then
    cp "$AGENT_VIDEO_PATH" /tmp/agent_animation.mp4 2>/dev/null || true
    chmod 666 /tmp/agent_animation.mp4 2>/dev/null || true
fi

# Copy reference video for verification
if [ -f "$REFERENCE_VIDEO" ]; then
    cp "$REFERENCE_VIDEO" /tmp/reference_animation.mp4 2>/dev/null || true
    chmod 666 /tmp/reference_animation.mp4 2>/dev/null || true
fi

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
