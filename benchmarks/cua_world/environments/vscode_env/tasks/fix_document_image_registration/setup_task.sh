#!/bin/bash
set -e

echo "=== Setting up Fix Document Image Registration Task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp
date +%s > /tmp/task_start_time.txt

# Install dependencies needed for the CV pipeline
echo "Installing OpenCV and Pytest..."
su - ga -c "pip3 install --no-cache-dir opencv-python-headless numpy pytest"

WORKSPACE_DIR="/home/ga/workspace/doc_processor"
sudo -u ga mkdir -p "$WORKSPACE_DIR/pipeline"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
sudo -u ga mkdir -p "$WORKSPACE_DIR/assets/samples"
sudo -u ga mkdir -p "$WORKSPACE_DIR/output"
cd "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# 1. Generate realistic skewed document data
# ─────────────────────────────────────────────────────────────
echo "Preparing document datasets..."
cat > "$WORKSPACE_DIR/generate_data.py" << 'PYEOF'
import cv2
import numpy as np
import os
import urllib.request

os.makedirs("assets/samples", exist_ok=True)

def create_fallback_form():
    """Generates a synthetic medical claim form if network download fails."""
    img = np.ones((1100, 850, 3), dtype=np.uint8) * 255
    cv2.putText(img, "HEALTH INSURANCE CLAIM FORM", (150, 100), cv2.FONT_HERSHEY_SIMPLEX, 1, (0,0,0), 2)
    cv2.putText(img, "PATIENT NAME: JOHN DOE", (100, 200), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0,0,0), 2)
    cv2.putText(img, "DOB: 01/01/1980", (100, 250), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0,0,0), 2)
    # ROI areas
    cv2.rectangle(img, (90, 170), (400, 210), (0,0,0), 2)
    cv2.rectangle(img, (90, 220), (300, 260), (0,0,0), 2)
    return img

# Try downloading a real public domain 1040EZ tax form as our base document
try:
    url = "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c8/1040EZ_2011.pdf/page1-800px-1040EZ_2011.pdf.jpg"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as response:
        img_arr = np.asarray(bytearray(response.read()), dtype=np.uint8)
        img = cv2.imdecode(img_arr, cv2.IMREAD_COLOR)
        if img is None:
            img = create_fallback_form()
except Exception as e:
    print(f"Download failed ({e}), using fallback form.")
    img = create_fallback_form()

# Add a distinct anchor logo to the top right
cv2.rectangle(img, (img.shape[1]-150, 50), (img.shape[1]-50, 150), (0,0,0), -1)
cv2.circle(img, (img.shape[1]-100, 100), 25, (255,255,255), -1)
cv2.imwrite("assets/base_form.jpg", img)

# Save the template logo for matching
template = img[50:150, img.shape[1]-150:img.shape[1]-50]
cv2.imwrite("assets/template.jpg", template)

# Generate skewed, misaligned variations
h, w = img.shape[:2]
center = (w // 2, h // 2)
for i, angle in enumerate([-4.5, 3.2, -1.8, 5.0]):
    M = cv2.getRotationMatrix2D(center, angle, 1.0)
    skewed = cv2.warpAffine(img, M, (w, h), borderValue=(255,255,255))
    cv2.imwrite(f"assets/samples/doc_{i}.jpg", skewed)
PYEOF

sudo -u ga python3 "$WORKSPACE_DIR/generate_data.py"

# ─────────────────────────────────────────────────────────────
# 2. Create the buggy pipeline files
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/pipeline/aligner.py" << 'PYEOF'
import cv2
import numpy as np

def find_anchor(image, template):
    """Finds the anchor logo to determine spatial offsets."""
    res = cv2.matchTemplate(image, template, cv2.TM_CCOEFF_NORMED)
    min_val, max_val, min_loc, max_loc = cv2.minMaxLoc(res)
    
    # BUG 1: TM_CCOEFF_NORMED requires max_loc for the best match, not min_loc
    return min_loc

def order_points(pts):
    """Orders 4 points: top-left, top-right, bottom-right, bottom-left."""
    rect = np.zeros((4, 2), dtype="float32")
    s = pts.sum(axis=1)
    diff = np.diff(pts, axis=1)
    
    # BUG 2: Incorrect corner assignments cause bowtie twisting in perspective transform
    rect[0] = pts[np.argmin(s)]     # top-left
    rect[1] = pts[np.argmax(s)]     # bottom-right (WRONG)
    rect[2] = pts[np.argmin(diff)]  # top-right (WRONG)
    rect[3] = pts[np.argmax(diff)]  # bottom-left
    
    return rect

def deskew(image, pts, width, height):
    """Applies a 4-point perspective transform to deskew the document."""
    rect = order_points(pts)
    dst = np.array([
        [0, 0],
        [width - 1, 0],
        [width - 1, height - 1],
        [0, height - 1]], dtype="float32")
    
    M = cv2.getPerspectiveTransform(rect, dst)
    warped = cv2.warpPerspective(image, M, (width, height))
    return warped
PYEOF

cat > "$WORKSPACE_DIR/pipeline/preprocessor.py" << 'PYEOF'
import cv2

def binarize_image(image):
    """Converts the image to a binary threshold format."""
    # BUG 3: Converting to HSV and using Hue channel instead of Grayscale
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    wrong_channel = hsv[:, :, 0]
    
    _, binary = cv2.threshold(wrong_channel, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    return binary

def get_horizontal_lines(binary_image):
    """Extracts horizontal lines used for form field detection."""
    # BUG 4: Structuring element dimensions inverted (width=1, height=25 instead of 25, 1)
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (1, 25))
    lines = cv2.morphologyEx(binary_image, cv2.MORPH_OPEN, kernel, iterations=2)
    return lines
PYEOF

cat > "$WORKSPACE_DIR/pipeline/roi_extractor.py" << 'PYEOF'
import numpy as np

def crop_roi(image, x, y, w, h):
    """Extracts the Region of Interest defined by a bounding box."""
    # BUG 5: NumPy array slicing is row-major [y, x], not [x, y]
    # This causes out of bounds errors or crops the wrong axis
    return image[x:x+w, y:y+h]
PYEOF

# ─────────────────────────────────────────────────────────────
# 3. Create the test suite
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tests/test_pipeline.py" << 'PYEOF'
import cv2
import pytest
import numpy as np
import os
from pipeline.aligner import find_anchor, deskew
from pipeline.preprocessor import binarize_image, get_horizontal_lines
from pipeline.roi_extractor import crop_roi

@pytest.fixture
def sample_data():
    base_dir = os.path.dirname(os.path.dirname(__file__))
    img = cv2.imread(os.path.join(base_dir, "assets", "samples", "doc_0.jpg"))
    template = cv2.imread(os.path.join(base_dir, "assets", "template.jpg"))
    return img, template

def test_template_matching(sample_data):
    img, template = sample_data
    loc = find_anchor(img, template)
    # The anchor is always top right. x should be > width/2
    assert loc[0] > img.shape[1] / 2, f"Anchor found at wrong X coord: {loc[0]}"

def test_perspective_transform():
    img = np.zeros((500, 500, 3), dtype=np.uint8)
    cv2.rectangle(img, (100, 100), (400, 400), (255, 255, 255), -1)
    # Define a slightly rotated square
    pts = np.array([[100, 120], [380, 100], [400, 380], [120, 400]], dtype="float32")
    deskewed = deskew(img, pts, 300, 300)
    # If ordered incorrectly, the image will twist and the center will be black
    assert deskewed[150, 150, 0] > 200, "Deskewed image is twisted (bowtie effect)"

def test_color_binarization(sample_data):
    img, _ = sample_data
    binary = binarize_image(img)
    # If the right channel is used, the white background should become 0 (black) in THRESH_BINARY_INV
    # HSV Hue of white/gray is highly erratic, leading to noise
    noise_level = np.mean(binary)
    assert noise_level < 50, "Binarization failed: output is too noisy due to wrong color space"

def test_horizontal_lines(sample_data):
    img, _ = sample_data
    binary = binarize_image(cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)) # Force correct binarization for this test
    lines = get_horizontal_lines(binary)
    # Ensure it's detecting horizontal streaks, meaning height should be smaller than width bounding boxes
    contours, _ = cv2.findContours(lines, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if contours:
        x, y, w, h = cv2.boundingRect(contours[0])
        assert w > h, f"Line detection found vertical structures instead of horizontal (w:{w}, h:{h})"

def test_roi_cropping():
    img = np.zeros((100, 200, 3), dtype=np.uint8)
    img[20:40, 50:100] = 255  # Fill a rectangle
    roi = crop_roi(img, 50, 20, 50, 20)
    assert roi.shape == (20, 50, 3), f"Crop returned wrong shape: {roi.shape}"
    assert np.mean(roi) == 255, "Crop returned empty region, slicing coordinates are inverted"
PYEOF

# Set ownership
chown -R ga:ga "$WORKSPACE_DIR"

# Ensure VSCode opens to the workspace
echo "Launching VSCode..."
if ! pgrep -f "code.*--ms-enable-electron" > /dev/null; then
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR &"
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="