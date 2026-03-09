#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Organize Lecture Library Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Create raw lectures directory
RAW_DIR="/home/ga/Downloads/lectures_raw"
mkdir -p "$RAW_DIR"
chown -R ga:ga "$RAW_DIR"

# Ensure Courses directory exists but is empty
COURSES_DIR="/home/ga/Videos/Courses"
if [ -d "$COURSES_DIR" ]; then
    rm -rf "$COURSES_DIR"
fi
mkdir -p "$COURSES_DIR"
chown -R ga:ga "$COURSES_DIR"

echo "Creating lecture recording files with cryptic names..."

# Define lecture files with metadata
# Format: filename|course|week|topic
declare -a LECTURES=(
    "GMT20241015-140052_Recording_1920x1080.mp4|Biology101|1|CellStructure"
    "zoom_recording_3829471.mp4|Biology101|2|DNAReplication"
    "recording_2024_10_29_093045.mp4|Biology101|3|Mitosis"
    "GMT20241022-150000_Rec_640x480.mp4|History202|1|AncientRome"
    "conference_audio_1698234982.mp4|History202|2|MedievalEurope"
    "online_class_rec_20241105.mp4|History202|3|Renaissance"
    "zoom_audio_only_9876543.mp4|Math150|1|Calculus_Derivatives"
    "meeting_recording_final.mp4|Math150|2|Integration_Techniques"
)

# Create JSON mapping for verification
cat > /tmp/lecture_mapping.json <<'EOF'
{
    "courses": {
        "Biology101": [
            {
                "original_name": "GMT20241015-140052_Recording_1920x1080.mp4",
                "expected_pattern": "Bio",
                "week": 1,
                "topic": "CellStructure"
            },
            {
                "original_name": "zoom_recording_3829471.mp4",
                "expected_pattern": "Bio",
                "week": 2,
                "topic": "DNAReplication"
            },
            {
                "original_name": "recording_2024_10_29_093045.mp4",
                "expected_pattern": "Bio",
                "week": 3,
                "topic": "Mitosis"
            }
        ],
        "History202": [
            {
                "original_name": "GMT20241022-150000_Rec_640x480.mp4",
                "expected_pattern": "Hist",
                "week": 1,
                "topic": "AncientRome"
            },
            {
                "original_name": "conference_audio_1698234982.mp4",
                "expected_pattern": "Hist",
                "week": 2,
                "topic": "MedievalEurope"
            },
            {
                "original_name": "online_class_rec_20241105.mp4",
                "expected_pattern": "Hist",
                "week": 3,
                "topic": "Renaissance"
            }
        ],
        "Math150": [
            {
                "original_name": "zoom_audio_only_9876543.mp4",
                "expected_pattern": "Math",
                "week": 1,
                "topic": "Calculus"
            },
            {
                "original_name": "meeting_recording_final.mp4",
                "expected_pattern": "Math",
                "week": 2,
                "topic": "Integration"
            }
        ]
    }
}
EOF

chown ga:ga /tmp/lecture_mapping.json

# Generate video files with embedded metadata
for lecture_info in "${LECTURES[@]}"; do
    IFS='|' read -r filename course week topic <<< "$lecture_info"
    
    OUTPUT_FILE="$RAW_DIR/$filename"
    
    echo "Creating: $filename (Course: $course, Week: $week, Topic: $topic)"
    
    # Create a 12-second video with text overlay showing course info
    # Using lavfi to generate test video with text
    ffmpeg -f lavfi -i "color=c=blue:s=640x480:d=12,format=yuv420p" \
        -vf "drawtext=text='$course - Week $week':fontsize=30:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2-30,\
             drawtext=text='$topic':fontsize=24:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2+30" \
        -metadata title="$course - Week $week: $topic" \
        -metadata artist="$course" \
        -metadata album="Week $week" \
        -metadata comment="$topic" \
        -c:v libx264 -preset ultrafast -crf 28 \
        -t 12 \
        "$OUTPUT_FILE" \
        -y -loglevel error 2>/dev/null || {
            echo "Warning: Failed to create $filename with text overlay, creating simple video"
            # Fallback: simple colored video
            ffmpeg -f lavfi -i "testsrc=duration=12:size=640x480:rate=10" \
                -metadata title="$course - Week $week: $topic" \
                -metadata artist="$course" \
                -metadata album="Week $week" \
                -c:v libx264 -preset ultrafast -crf 28 \
                "$OUTPUT_FILE" \
                -y -loglevel error
        }
    
    chown ga:ga "$OUTPUT_FILE"
    echo "  ✓ Created: $OUTPUT_FILE"
done

echo ""
echo "=== Organize Lecture Library Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  1. Navigate to /home/ga/Downloads/lectures_raw/"
echo "  2. Identify 8 lecture files with cryptic names"
echo "  3. Create course folders under /home/ga/Videos/Courses/:"
echo "     - Biology101/"
echo "     - History202/"
echo "     - Math150/"
echo "  4. Move and rename files to: [Course]_Week[N]_[Topic].mp4"
echo "     Examples:"
echo "     - Bio101_Week1_CellStructure.mp4"
echo "     - History202_Week2_MedievalEurope.mp4"
echo "     - Math150_Week1_Calculus.mp4"
echo "  5. Create playlist.m3u in each course folder"
echo "  6. Clean up lectures_raw folder"
echo ""
echo "💡 Hints:"
echo "  - Use VLC to preview files and check metadata"
echo "  - Metadata shows: Course - Week N: Topic"
echo "  - Can use: Tools → Media Information (Ctrl+I)"
echo "  - Or use file manager / terminal to inspect"
echo ""

# List the created files for debugging
echo "Created lecture files:"
ls -lh "$RAW_DIR"