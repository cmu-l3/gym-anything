#!/bin/bash
# Do NOT use set -e: some commands may return non-zero harmlessly

echo "=== Exporting export_diagram_as_png task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/export_task_end.png 2>/dev/null || true

EXPORT_FILE="/home/ga/Desktop/hospital_er_export.png"
FOUND="false"
FILE_EXISTS="false"
FILE_SIZE=0
IS_VALID_PNG="false"
IMAGE_WIDTH=0
IMAGE_HEIGHT=0

if [ -f "$EXPORT_FILE" ]; then
    FILE_EXISTS="true"
    FOUND="true"
    FILE_SIZE=$(stat --format=%s "$EXPORT_FILE" 2>/dev/null || echo "0")
    echo "Found export file: $EXPORT_FILE ($FILE_SIZE bytes)"

    # Check if it's a valid PNG using file command
    FILE_TYPE=$(file -b "$EXPORT_FILE" 2>/dev/null || echo "unknown")
    echo "File type: $FILE_TYPE"

    if echo "$FILE_TYPE" | grep -qi "PNG"; then
        IS_VALID_PNG="true"
    fi

    # Get image dimensions using identify (ImageMagick)
    if command -v identify &>/dev/null; then
        DIMENSIONS=$(identify -format "%wx%h" "$EXPORT_FILE" 2>/dev/null || echo "0x0")
        IMAGE_WIDTH=$(echo "$DIMENSIONS" | cut -d'x' -f1)
        IMAGE_HEIGHT=$(echo "$DIMENSIONS" | cut -d'x' -f2)
        echo "Image dimensions: ${IMAGE_WIDTH}x${IMAGE_HEIGHT}"
    fi

    # Alternative: Use Python PIL for dimensions
    if [ "$IMAGE_WIDTH" -eq 0 ] 2>/dev/null; then
        python3 << 'PYEOF' > /tmp/png_dimensions.txt 2>/dev/null || true
try:
    from PIL import Image
    img = Image.open("/home/ga/Desktop/hospital_er_export.png")
    print(f"{img.width} {img.height}")
except:
    print("0 0")
PYEOF
        if [ -f /tmp/png_dimensions.txt ]; then
            IMAGE_WIDTH=$(awk '{print $1}' /tmp/png_dimensions.txt)
            IMAGE_HEIGHT=$(awk '{print $2}' /tmp/png_dimensions.txt)
        fi
    fi
else
    echo "Export file not found: $EXPORT_FILE"

    # Check if file was saved with different name or location
    echo "Searching for any PNG files on Desktop..."
    ls -la /home/ga/Desktop/*.png 2>/dev/null || echo "  No PNG files found on Desktop"
    echo "Searching for PNG files in Diagrams folder..."
    ls -la /home/ga/Diagrams/*.png 2>/dev/null || echo "  No PNG files found in Diagrams"
    echo "Searching in exports folder..."
    ls -la /home/ga/Diagrams/exports/*.png 2>/dev/null || echo "  No PNG files found in exports"
fi

# Check source diagram still exists
SOURCE_EXISTS="false"
if [ -f "/home/ga/Diagrams/hospital_er_base.drawio" ]; then
    SOURCE_EXISTS="true"
fi

# Content verification: check that the exported PNG contains actual diagram content
# (not a blank image). We check color diversity and look for expected entity text
# in any embedded metadata or tEXt chunks.
HAS_DIAGRAM_CONTENT="false"
UNIQUE_COLORS=0
HAS_EMBEDDED_XML="false"

if [ "$IS_VALID_PNG" = "true" ]; then
    python3 << 'PYEOF' > /tmp/png_content_check.json 2>/dev/null || true
import json
result = {"has_diagram_content": False, "unique_colors": 0, "has_embedded_xml": False}
try:
    from PIL import Image
    img = Image.open("/home/ga/Desktop/hospital_er_export.png")

    # Sample pixels to count unique colors (a diagram should have many colors/shades)
    # A blank white image has ~1 color; a diagram has many
    pixels = list(img.getdata())
    sample = pixels[::max(1, len(pixels)//10000)]  # Sample up to 10000 pixels
    unique = len(set(sample))
    result["unique_colors"] = unique

    # A real diagram export should have >20 unique colors (text, borders, fills, background)
    if unique > 20:
        result["has_diagram_content"] = True

    # Check for embedded XML in PNG tEXt chunks (draw.io "Include copy of diagram")
    if hasattr(img, 'info'):
        for key in img.info:
            if isinstance(img.info[key], str) and ('mxfile' in img.info[key].lower() or 'mxgraph' in img.info[key].lower()):
                result["has_embedded_xml"] = True
                break
            if key.lower() == 'mxfile' or key.lower() == 'mxgraphmodel':
                result["has_embedded_xml"] = True
                break
except Exception as e:
    result["error"] = str(e)
print(json.dumps(result))
PYEOF

    if [ -f /tmp/png_content_check.json ]; then
        HAS_DIAGRAM_CONTENT=$(python3 -c "import json; d=json.load(open('/tmp/png_content_check.json')); print(str(d.get('has_diagram_content', False)).lower())" 2>/dev/null || echo "false")
        UNIQUE_COLORS=$(python3 -c "import json; d=json.load(open('/tmp/png_content_check.json')); print(d.get('unique_colors', 0))" 2>/dev/null || echo "0")
        HAS_EMBEDDED_XML=$(python3 -c "import json; d=json.load(open('/tmp/png_content_check.json')); print(str(d.get('has_embedded_xml', False)).lower())" 2>/dev/null || echo "false")
        echo "Content check: diagram_content=$HAS_DIAGRAM_CONTENT unique_colors=$UNIQUE_COLORS embedded_xml=$HAS_EMBEDDED_XML"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "found": $FOUND,
    "file_exists": $FILE_EXISTS,
    "file_path": "$EXPORT_FILE",
    "file_size": $FILE_SIZE,
    "is_valid_png": $IS_VALID_PNG,
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "source_diagram_exists": $SOURCE_EXISTS,
    "has_diagram_content": $HAS_DIAGRAM_CONTENT,
    "unique_colors": $UNIQUE_COLORS,
    "has_embedded_xml": $HAS_EMBEDDED_XML,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
