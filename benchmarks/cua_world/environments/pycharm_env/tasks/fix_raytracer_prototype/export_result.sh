#!/bin/bash
echo "=== Exporting fix_raytracer_prototype result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_raytracer_prototype"
PROJECT_DIR="/home/ga/PycharmProjects/pytracer"
OUTPUT_IMG="$PROJECT_DIR/output/render.png"

# 1. Run Tests
echo "Running tests..."
PYTEST_OUTPUT=$(cd "$PROJECT_DIR" && python3 -m pytest tests/ -v 2>&1)
PYTEST_EXIT_CODE=$?
echo "$PYTEST_OUTPUT"

# 2. Force Render (to verify fix visually even if agent didn't)
# We run main.py. If bugs are fixed, it produces good image.
echo "Running renderer..."
cd "$PROJECT_DIR" && python3 main.py > /tmp/render_log.txt 2>&1

# 3. Analyze Output Image (Pixel Probing)
# We use a python script to check key pixels
PIXEL_CHECK_JSON="{}"
if [ -f "$OUTPUT_IMG" ]; then
    PIXEL_CHECK_JSON=$(python3 -c "
from PIL import Image
import json

try:
    img = Image.open('$OUTPUT_IMG')
    w, h = img.size
    rgb_img = img.convert('RGB')
    
    # Sample points (approximate coords based on scene)
    # 1. Shadow under sphere (should be dark)
    # Ground sphere is big, center at (0, -100.5, -1). Center sphere at (0,0,-1).
    # Shadow should be below center sphere.
    shadow_p = rgb_img.getpixel((w//2, h//2 + 50)) 
    
    # 2. Sky/Background (top of image)
    sky_p = rgb_img.getpixel((w//2, 10))
    
    # 3. Reflection (on the left metal sphere)
    # Metal sphere at (-1, 0, -1). In 320x180 image, this is left of center.
    reflect_p = rgb_img.getpixel((50, h//2))

    print(json.dumps({
        'shadow_rgb': shadow_p,
        'sky_rgb': sky_p,
        'reflect_rgb': reflect_p,
        'width': w,
        'height': h
    }))
except Exception as e:
    print(json.dumps({'error': str(e)}))
")
fi

# 4. Take screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON
cat > /tmp/task_result.json << EOF
{
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "pytest_output": $(echo "$PYTEST_OUTPUT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
    "render_exists": $([ -f "$OUTPUT_IMG" ] && echo "true" || echo "false"),
    "pixel_analysis": $PIXEL_CHECK_JSON,
    "task_timestamp": $(date +%s)
}
EOF

chmod 666 /tmp/task_result.json
echo "Export complete."