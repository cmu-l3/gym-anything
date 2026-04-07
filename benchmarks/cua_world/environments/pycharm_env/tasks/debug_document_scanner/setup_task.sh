#!/bin/bash
echo "=== Setting up debug_document_scanner task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/PycharmProjects/scanner_pro"

# Clean any previous state
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/debug_scanner_result.json /tmp/debug_scanner_start_ts 2>/dev/null || true

# Record start time
date +%s > /tmp/debug_scanner_start_ts

# Create project structure
su - ga -c "mkdir -p $PROJECT_DIR/scanner_pro $PROJECT_DIR/tests $PROJECT_DIR/data $PROJECT_DIR/output"

# --- Install dependencies ---
# Ensure opencv-python is installed
pip3 install opencv-python-headless numpy imutils scikit-image > /dev/null 2>&1 || true

# --- Create requirements.txt ---
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
numpy>=1.24.0
opencv-python>=4.8.0
imutils>=0.5.4
pytest>=7.0
EOF

# --- Create utils.py ---
cat > "$PROJECT_DIR/scanner_pro/utils.py" << 'PYEOF'
import cv2
import numpy as np

def resize_image(image, width=None, height=None, inter=cv2.INTER_AREA):
    dim = None
    (h, w) = image.shape[:2]

    if width is None and height is None:
        return image

    if width is None:
        r = height / float(h)
        dim = (int(w * r), int(height))
    else:
        r = width / float(w)
        dim = (int(width), int(h * r))

    return cv2.resize(image, dim, interpolation=inter)

def show_image(title, image):
    # Headless mode wrapper
    pass 
PYEOF

# --- Create the BUGGY processor.py ---
cat > "$PROJECT_DIR/scanner_pro/processor.py" << 'PYEOF'
import cv2
import numpy as np

class DocumentScanner:
    def __init__(self):
        pass

    def order_points(self, pts):
        """
        Initialize a list of coordinates that will be ordered
        such that the first entry in the list is the top-left,
        the second entry is the top-right, the third is the
        bottom-right, and the fourth is the bottom-left.
        """
        rect = np.zeros((4, 2), dtype="float32")

        # The top-left point will have the smallest sum, whereas
        # the bottom-right point will have the largest sum
        s = pts.sum(axis=1)
        rect[0] = pts[np.argmin(s)] # Top-left
        rect[2] = pts[np.argmax(s)] # Bottom-right

        # BUG 2: Geometric Logic Error
        # The top-right point will have the smallest difference,
        # whereas the bottom-left point will have the largest difference.
        # CORRECT: Top-Right is min(diff), Bottom-Left is max(diff)
        # BUG: The code below SWAPS them, causing mirrored/twisted output
        diff = np.diff(pts, axis=1)
        rect[1] = pts[np.argmax(diff)] # Bug: Assigned Max diff to TR (Should be BL)
        rect[3] = pts[np.argmin(diff)] # Bug: Assigned Min diff to BL (Should be TR)

        return rect

    def four_point_transform(self, image, pts):
        rect = self.order_points(pts)
        (tl, tr, br, bl) = rect

        # Compute width of new image
        widthA = np.sqrt(((br[0] - bl[0]) ** 2) + ((br[1] - bl[1]) ** 2))
        widthB = np.sqrt(((tr[0] - tl[0]) ** 2) + ((tr[1] - tl[1]) ** 2))
        maxWidth = max(int(widthA), int(widthB))

        # Compute height of new image
        heightA = np.sqrt(((tr[0] - br[0]) ** 2) + ((tr[1] - br[1]) ** 2))
        heightB = np.sqrt(((tl[0] - bl[0]) ** 2) + ((tl[1] - bl[1]) ** 2))
        maxHeight = max(int(heightA), int(heightB))

        dst = np.array([
            [0, 0],
            [maxWidth - 1, 0],
            [maxWidth - 1, maxHeight - 1],
            [0, maxHeight - 1]], dtype="float32")

        M = cv2.getPerspectiveTransform(rect, dst)
        warped = cv2.warpPerspective(image, M, (maxWidth, maxHeight))
        return warped

    def apply_threshold(self, image):
        # BUG 3: OpenCV Error
        # blockSize must be an odd number (e.g., 11, 13, 15)
        # 12 is even -> Causes cv2.error: Assertion failed (blockSize % 2 == 1 && blockSize > 1)
        return cv2.adaptiveThreshold(image, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                                     cv2.THRESH_BINARY, 12, 2)

    def scan(self, image_path):
        image = cv2.imread(image_path)
        if image is None:
            raise ValueError(f"Could not read image: {image_path}")
            
        ratio = image.shape[0] / 500.0
        orig = image.copy()
        image = cv2.resize(image, (int(image.shape[1] / ratio), 500))

        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        gray = cv2.GaussianBlur(gray, (5, 5), 0)
        edged = cv2.Canny(gray, 75, 200)

        cnts = cv2.findContours(edged.copy(), cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
        cnts = cnts[0] if len(cnts) == 2 else cnts[1]
        
        # BUG 1: Contour Selection Logic
        # We assume the largest contour is the document.
        # But we simply take the FIRST contour found without sorting.
        # OpenCV findContours order is not guaranteed to be by area.
        # This often picks up noise/speckles instead of the document.
        # MISSING: cnts = sorted(cnts, key=cv2.contourArea, reverse=True)[:5]
        
        screenCnt = None
        for c in cnts: # Looping through unsorted contours
            peri = cv2.arcLength(c, True)
            approx = cv2.approxPolyDP(c, 0.02 * peri, True)

            if len(approx) == 4:
                screenCnt = approx
                break

        if screenCnt is None:
            print("No document contour found")
            return None

        warped = self.four_point_transform(orig, screenCnt.reshape(4, 2) * ratio)
        
        # This will crash due to Bug 3
        try:
            processed = self.apply_threshold(cv2.cvtColor(warped, cv2.COLOR_BGR2GRAY))
        except cv2.error as e:
            print(f"CRITICAL ERROR in thresholding: {e}")
            return None
            
        return processed
PYEOF

# --- Create tests ---
cat > "$PROJECT_DIR/tests/test_geometry.py" << 'PYEOF'
import numpy as np
import pytest
from scanner_pro.processor import DocumentScanner

def test_order_points():
    scanner = DocumentScanner()
    # Define a simple rectangle: TL=(0,0), TR=(10,0), BR=(10,10), BL=(0,10)
    # Points can be in any order in input
    pts = np.array([[10, 10], [0, 0], [0, 10], [10, 0]], dtype="float32")
    
    ordered = scanner.order_points(pts)
    
    # Expected: TL, TR, BR, BL
    expected = np.array([[0, 0], [10, 0], [10, 10], [0, 10]], dtype="float32")
    
    np.testing.assert_array_equal(ordered, expected, 
        err_msg="Points are not ordered correctly (TL, TR, BR, BL). Check logic.")
PYEOF

cat > "$PROJECT_DIR/tests/test_pipeline.py" << 'PYEOF'
import cv2
import numpy as np
import pytest
from scanner_pro.processor import DocumentScanner

def test_threshold_crash():
    scanner = DocumentScanner()
    # Create a dummy grayscale image
    img = np.zeros((100, 100), dtype="uint8")
    # Should not raise cv2.error
    try:
        scanner.apply_threshold(img)
    except cv2.error:
        pytest.fail("apply_threshold crashed! Check blockSize.")

def test_contour_selection_logic(mocker):
    """
    Test that the scanner picks the LARGEST 4-point contour, not just the first one.
    """
    scanner = DocumentScanner()
    
    # Mock finding contours to return a small square (noise) FIRST, 
    # and a large rectangle (document) SECOND.
    # If code doesn't sort, it will pick the small square.
    
    small_square = np.array([[[10,10]], [[20,10]], [[20,20]], [[10,20]]], dtype="int32") # Area 100
    large_doc = np.array([[[50,50]], [[450,50]], [[450,450]], [[50,450]]], dtype="int32") # Area 160000
    
    # Create a mock image that would produce these contours
    # We'll just bypass detect logic and test the sorting logic if we could, 
    # but since we can't easily unit test the monolithic scan method, 
    # we'll create a synthetic image where the first contour found is noise.
    
    # White background
    img = np.zeros((500, 500, 3), dtype="uint8")
    
    # Draw large document (should be selected)
    cv2.rectangle(img, (50, 50), (450, 450), (255, 255, 255), 2)
    
    # Draw small noise boxes (might be detected first depending on impl)
    cv2.rectangle(img, (10, 10), (20, 20), (255, 255, 255), 2)
    cv2.rectangle(img, (480, 480), (490, 490), (255, 255, 255), 2)
    
    cv2.imwrite("/tmp/test_contours.jpg", img)
    
    res = scanner.scan("/tmp/test_contours.jpg")
    assert res is not None, "Scanner failed to process image"
    
    # If it picked the small square, the output size would be tiny
    h, w = res.shape
    assert h > 300 and w > 300, f"Result image too small ({w}x{h}). Scanner likely picked noise contour."
PYEOF

# --- Create main.py ---
cat > "$PROJECT_DIR/main.py" << 'PYEOF'
import sys
import cv2
from scanner_pro.processor import DocumentScanner

def main():
    if len(sys.argv) < 2:
        print("Usage: python main.py <image_path>")
        sys.exit(1)
        
    path = sys.argv[1]
    scanner = DocumentScanner()
    
    print(f"Scanning {path}...")
    try:
        result = scanner.scan(path)
        if result is not None:
            output_path = "output/scanned_" + path.split("/")[-1]
            cv2.imwrite(output_path, result)
            print(f"Success! Saved to {output_path}")
        else:
            print("Failed to scan document.")
    except Exception as e:
        print(f"Error during scanning: {e}")

if __name__ == "__main__":
    main()
PYEOF

# --- Create Data Generation Script ---
# We need "real-looking" data to ensure the bugs manifest correctly.
# A white rectangle on black background is too simple.
cat > /tmp/gen_data.py << 'PYEOF'
import cv2
import numpy as np
import os

def create_receipt_image(filename, angle=0, noise=False):
    # Background (Table)
    img = np.zeros((800, 600, 3), dtype=np.uint8)
    img[:] = (40, 40, 40) # Dark gray table
    
    # Receipt dimensions
    w, h = 300, 500
    receipt = np.ones((h, w, 3), dtype=np.uint8) * 240 # Light gray paper
    
    # Add text-like noise to receipt
    for i in range(20, h-20, 20):
        cv2.line(receipt, (20, i), (w-20, i), (100, 100, 100), 2)
        
    # Rotate receipt
    center = (w // 2, h // 2)
    M = cv2.getRotationMatrix2D(center, angle, 1.0)
    receipt_rotated = cv2.warpAffine(receipt, M, (w, h), borderValue=(40,40,40))
    
    # Place on table (center)
    y_off = (800 - h) // 2
    x_off = (600 - w) // 2
    
    # Create mask for composition
    # Simple manual placement logic for rotation handling
    # We'll just draw a rotated rectangle on the main image for simplicity and robustness
    
    # Reset and draw directly on main image using polygon
    img[:] = (40, 40, 40)
    
    # Define rectangle points centered
    pts = np.array([
        [-w/2, -h/2],
        [w/2, -h/2],
        [w/2, h/2],
        [-w/2, h/2]
    ])
    
    # Rotate points
    theta = np.radians(angle)
    c, s = np.cos(theta), np.sin(theta)
    R = np.array(((c, -s), (s, c)))
    pts_rot = np.dot(pts, R.T)
    
    # Shift to center
    pts_rot[:, 0] += 300
    pts_rot[:, 1] += 400
    pts_int = pts_rot.astype(np.int32)
    
    # Draw filled polygon (Receipt)
    cv2.fillPoly(img, [pts_int], (240, 240, 240))
    
    # Add some noise/speckles to trigger contour confusion
    if noise:
        # Draw small bright box (noise)
        cv2.rectangle(img, (50, 50), (80, 80), (200, 200, 200), -1)
        # Draw another one
        cv2.rectangle(img, (550, 750), (580, 780), (200, 200, 200), -1)

    # Save
    cv2.imwrite(filename, img)

os.makedirs("/home/ga/PycharmProjects/scanner_pro/data", exist_ok=True)
create_receipt_image("/home/ga/PycharmProjects/scanner_pro/data/sample_receipt.jpg", angle=10, noise=True)
create_receipt_image("/home/ga/PycharmProjects/scanner_pro/data/hidden_test.jpg", angle=-15, noise=True)
PYEOF

# Run data generation
python3 /tmp/gen_data.py

# Setup PyCharm project
source /workspace/scripts/task_utils.sh
setup_pycharm_project "$PROJECT_DIR" "scanner_pro"

echo "=== Task setup complete ==="