#!/bin/bash
echo "=== Exporting VOD Chapter Indexing Package Result ==="

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
VOD_DIR="/home/ga/Videos/vod_package"

# Collect information about the Chaptered Video
CHAPTERED_VIDEO_EXISTS="false"
CHAPTERED_VIDEO_SIZE=0
CHAPTERED_VIDEO_MTIME=0
CHAPTERED_VIDEO_DURATION=0
CHAPTERS_JSON='{"chapters": []}'

if [ -f "$VOD_DIR/documentary_chaptered.mp4" ]; then
    CHAPTERED_VIDEO_EXISTS="true"
    CHAPTERED_VIDEO_SIZE=$(stat -c %s "$VOD_DIR/documentary_chaptered.mp4" 2>/dev/null || echo "0")
    CHAPTERED_VIDEO_MTIME=$(stat -c %Y "$VOD_DIR/documentary_chaptered.mp4" 2>/dev/null || echo "0")
    CHAPTERED_VIDEO_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VOD_DIR/documentary_chaptered.mp4" 2>/dev/null || echo "0")
    CHAPTERS_JSON=$(ffprobe -v error -show_chapters -of json "$VOD_DIR/documentary_chaptered.mp4" 2>/dev/null || echo '{"chapters": []}')
fi

# Use a Python script to fetch all image dimensions safely
cat > /tmp/get_image_info.py << 'EOF'
import sys, json
try:
    from PIL import Image
    results = {}
    for path in sys.argv[1:]:
        try:
            img = Image.open(path)
            results[path] = {"width": img.width, "height": img.height}
        except Exception:
            results[path] = {"width": 0, "height": 0}
    with open('/tmp/image_dims.json', 'w') as f:
        json.dump(results, f)
except Exception as e:
    with open('/tmp/image_dims.json', 'w') as f:
        json.dump({}, f)
EOF

FILES_TO_CHECK=""
for i in {1..6}; do
    FILES_TO_CHECK="$FILES_TO_CHECK $VOD_DIR/chapter_$i.png"
done
FILES_TO_CHECK="$FILES_TO_CHECK $VOD_DIR/scrub_preview.png"

python3 /tmp/get_image_info.py $FILES_TO_CHECK

# Collect Thumbnail metrics
THUMBNAILS_JSON="["
for i in {1..6}; do
    TFILE="$VOD_DIR/chapter_$i.png"
    if [ -f "$TFILE" ]; then
        TSIZE=$(stat -c %s "$TFILE" 2>/dev/null || echo "0")
        TMTIME=$(stat -c %Y "$TFILE" 2>/dev/null || echo "0")
        TW=$(python3 -c "import json; print(json.load(open('/tmp/image_dims.json')).get('$TFILE', {}).get('width', 0))" 2>/dev/null || echo "0")
        TH=$(python3 -c "import json; print(json.load(open('/tmp/image_dims.json')).get('$TFILE', {}).get('height', 0))" 2>/dev/null || echo "0")
        THUMBNAILS_JSON="${THUMBNAILS_JSON}{\"id\": $i, \"exists\": true, \"size\": $TSIZE, \"mtime\": $TMTIME, \"width\": $TW, \"height\": $TH},"
    else
        THUMBNAILS_JSON="${THUMBNAILS_JSON}{\"id\": $i, \"exists\": false},"
    fi
done
THUMBNAILS_JSON="${THUMBNAILS_JSON%?}]"

# Collect JSON Chapter Index content
CHAPTER_INDEX_EXISTS="false"
CHAPTER_INDEX_MTIME=0
CHAPTER_INDEX_CONTENT='{"error": "not found"}'
if [ -f "$VOD_DIR/chapter_index.json" ]; then
    CHAPTER_INDEX_EXISTS="true"
    CHAPTER_INDEX_MTIME=$(stat -c %Y "$VOD_DIR/chapter_index.json" 2>/dev/null || echo "0")
    # Quick parse to validate structure before including in final report
    if python3 -c "import json; json.load(open('$VOD_DIR/chapter_index.json'))" >/dev/null 2>&1; then
        CHAPTER_INDEX_CONTENT=$(cat "$VOD_DIR/chapter_index.json")
    else
        CHAPTER_INDEX_CONTENT='{"error": "Invalid JSON syntax"}'
    fi
fi

# Collect Sprite Sheet metrics
SPRITE_EXISTS="false"
SPRITE_SIZE=0
SPRITE_MTIME=0
SPRITE_W=0
SPRITE_H=0
SFILE="$VOD_DIR/scrub_preview.png"
if [ -f "$SFILE" ]; then
    SPRITE_EXISTS="true"
    SPRITE_SIZE=$(stat -c %s "$SFILE" 2>/dev/null || echo "0")
    SPRITE_MTIME=$(stat -c %Y "$SFILE" 2>/dev/null || echo "0")
    SPRITE_W=$(python3 -c "import json; print(json.load(open('/tmp/image_dims.json')).get('$SFILE', {}).get('width', 0))" 2>/dev/null || echo "0")
    SPRITE_H=$(python3 -c "import json; print(json.load(open('/tmp/image_dims.json')).get('$SFILE', {}).get('height', 0))" 2>/dev/null || echo "0")
fi

# Stitch findings into a master result json using python to avoid bash interpolation issues
cat > /tmp/gen_result.py << 'EOF'
import json, sys

try:
    with open('/tmp/chapters.json', 'r') as f:
        chapters = json.load(f)
except:
    chapters = {"chapters": []}

try:
    with open('/tmp/thumbnails.json', 'r') as f:
        thumbnails = json.load(f)
except:
    thumbnails = []

try:
    with open('/tmp/chapter_index_content.json', 'r') as f:
        chapter_index_content = json.load(f)
except:
    chapter_index_content = {"error": "Invalid JSON"}

result = {
    "task_start_time": int(sys.argv[1]),
    "video": {
        "exists": sys.argv[2] == "true",
        "size": int(sys.argv[3]),
        "mtime": int(sys.argv[4]),
        "duration": float(sys.argv[5] if sys.argv[5].strip() else 0),
        "chapters_data": chapters
    },
    "thumbnails": thumbnails,
    "chapter_index": {
        "exists": sys.argv[6] == "true",
        "mtime": int(sys.argv[7]),
        "content": chapter_index_content
    },
    "sprite": {
        "exists": sys.argv[8] == "true",
        "size": int(sys.argv[9]),
        "mtime": int(sys.argv[10]),
        "width": int(sys.argv[11]),
        "height": int(sys.argv[12])
    }
}

with open('/tmp/vod_package_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

echo "$CHAPTERS_JSON" > /tmp/chapters.json
echo "$THUMBNAILS_JSON" > /tmp/thumbnails.json
echo "$CHAPTER_INDEX_CONTENT" > /tmp/chapter_index_content.json

python3 /tmp/gen_result.py \
    "$TASK_START" \
    "$CHAPTERED_VIDEO_EXISTS" "$CHAPTERED_VIDEO_SIZE" "$CHAPTERED_VIDEO_MTIME" "$CHAPTERED_VIDEO_DURATION" \
    "$CHAPTER_INDEX_EXISTS" "$CHAPTER_INDEX_MTIME" \
    "$SPRITE_EXISTS" "$SPRITE_SIZE" "$SPRITE_MTIME" "$SPRITE_W" "$SPRITE_H"

chmod 666 /tmp/vod_package_result.json

# Cleanup instances
pkill -f "vlc" 2>/dev/null || true
rm -f /tmp/chapters.json /tmp/thumbnails.json /tmp/chapter_index_content.json /tmp/get_image_info.py /tmp/image_dims.json /tmp/gen_result.py

echo "=== Export complete ==="