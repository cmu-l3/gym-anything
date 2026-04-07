#!/bin/bash
echo "=== Setting up debug_pcb_defect_detector ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Define paths
PROJECT_DIR="/home/ga/PycharmProjects/pcb_inspector"
DATA_DIR="$PROJECT_DIR/data"

# Clean previous state
rm -rf "$PROJECT_DIR"
rm -f /tmp/debug_pcb_result.json /tmp/debug_pcb_start_ts

# Install required packages if missing
pip3 install opencv-python-headless numpy pytest --quiet

# Create project structure
mkdir -p "$PROJECT_DIR/pcb_inspector"
mkdir -p "$PROJECT_DIR/tests"
mkdir -p "$DATA_DIR"

# ==============================================================================
# 1. Generate Synthetic PCB Data (Python script)
# ==============================================================================
cat > "$PROJECT_DIR/generate_data.py" << 'PYEOF'
import numpy as np
import cv2
import os

def create_reference_pcb(h=400, w=600):
    # Green PCB background
    img = np.zeros((h, w, 3), dtype=np.uint8)
    img[:] = (34, 139, 34)  # Forest Green
    
    # Define components (x, y, w, h)
    components = [
        (50, 50, 100, 80),   # Chip 1
        (200, 50, 100, 80),  # Chip 2
        (350, 50, 100, 80),  # Chip 3
        (100, 200, 60, 60),  # Capacitor 1
        (300, 200, 60, 60),  # Capacitor 2
    ]
    
    # Draw components on reference
    for (x, y, wc, hc) in components:
        # Silver solder pads
        cv2.rectangle(img, (x-5, y-5), (x+wc+5, y+hc+5), (192, 192, 192), -1)
        # Black component body
        cv2.rectangle(img, (x, y), (x+wc, y+hc), (20, 20, 20), -1)
        
    return img, components

def main():
    if not os.path.exists("data"):
        os.makedirs("data")
        
    ref_img, components = create_reference_pcb()
    cv2.imwrite("data/reference.jpg", ref_img)
    
    # Test 01: Perfect match
    cv2.imwrite("data/test_01.jpg", ref_img)
    
    # Test 02: Missing first component
    t2 = ref_img.copy()
    x, y, wc, hc = components[0]
    # Draw over with PCB color (missing component)
    cv2.rectangle(t2, (x, y), (x+wc, y+hc), (34, 139, 34), -1)
    cv2.imwrite("data/test_02.jpg", t2)
    
    # Test 03: Missing last two components
    t3 = ref_img.copy()
    for i in [-1, -2]:
        x, y, wc, hc = components[i]
        cv2.rectangle(t3, (x, y), (x+wc, y+hc), (34, 139, 34), -1)
    cv2.imwrite("data/test_03.jpg", t3)
    
    # Save component metadata for inspection logic
    with open("data/config.txt", "w") as f:
        for c in components:
            f.write(f"{c[0]},{c[1]},{c[2]},{c[3]}\n")

if __name__ == "__main__":
    main()
PYEOF

# Run data generation
cd "$PROJECT_DIR" && python3 generate_data.py
rm "$PROJECT_DIR/generate_data.py"

# ==============================================================================
# 2. Create Source Code (With Bugs)
# ==============================================================================

# --- pcb_inspector/utils.py ---
# Bug 2: Mutable default argument in log_defect
# Bug 3: IndexError on grayscale image shape access
cat > "$PROJECT_DIR/pcb_inspector/utils.py" << 'PYEOF'
import cv2
import numpy as np

def load_image(path, as_grayscale=False):
    """Load an image from path."""
    if as_grayscale:
        img = cv2.imread(path, cv2.IMREAD_GRAYSCALE)
    else:
        img = cv2.imread(path)
        
    if img is None:
        raise FileNotFoundError(f"Could not load image at {path}")
    return img

def check_image_properties(image):
    """Verify image depth and dimensions."""
    height = image.shape[0]
    width = image.shape[1]
    
    # BUG 3: This raises IndexError if image is grayscale (len(shape)==2)
    # Correct check should verify len(image.shape) > 2
    channels = image.shape[2] 
    
    return height, width, channels

def log_defect(defect_info, defect_log=[]):
    """
    Append defect info to the log.
    
    Args:
        defect_info (dict): Information about the defect.
        defect_log (list): List to append to.
    """
    # BUG 2: Mutable default argument `defect_log=[]`.
    # This causes defects to accumulate across different calls if log is not provided.
    defect_log.append(defect_info)
    return defect_log
PYEOF

# --- pcb_inspector/core.py ---
# Bug 1: Slicing indices swapped [x:w, y:h] instead of [y:h, x:w]
# Bug 4: Threshold logic inverted (diff < thresh instead of diff > thresh)
cat > "$PROJECT_DIR/pcb_inspector/core.py" << 'PYEOF'
import cv2
import numpy as np
from pcb_inspector.utils import log_defect

class PCBInspector:
    def __init__(self, reference_path, config_path):
        self.reference = cv2.imread(reference_path)
        self.rois = self._load_rois(config_path)
        
    def _load_rois(self, config_path):
        rois = []
        with open(config_path, 'r') as f:
            for line in f:
                parts = line.strip().split(',')
                rois.append(tuple(map(int, parts)))
        return rois

    def inspect(self, test_image_path):
        test_img = cv2.imread(test_image_path)
        defects = []
        
        for i, (x, y, w, h) in enumerate(self.rois):
            # Extract ROI from Reference
            # Note: NumPy arrays are (row, col) -> (y, x)
            ref_roi = self.reference[y:y+h, x:x+w]
            
            # Extract ROI from Test Image
            # BUG 1: Wrong slicing indices. Using x for rows and y for cols.
            # Should be test_img[y:y+h, x:x+w]
            test_roi = test_img[x:x+w, y:y+h]
            
            # Ensure shapes match before comparison (resizing if bug caused mismatch)
            if ref_roi.shape != test_roi.shape:
                # This simplistic resize hides the crash but leads to garbage comparison
                test_roi = cv2.resize(test_roi, (ref_roi.shape[1], ref_roi.shape[0]))
            
            # Calculate difference
            diff = cv2.absdiff(ref_roi, test_roi)
            gray_diff = cv2.cvtColor(diff, cv2.COLOR_BGR2GRAY)
            score = np.mean(gray_diff)
            
            # BUG 4: Threshold logic inverted.
            # A missing component causes a LARGE difference (high score).
            # We want to flag if score > 50.
            # Current logic flags if score < 50, which is almost always true for good parts.
            if score < 50.0:
                log_defect({
                    "roi_index": i,
                    "score": score,
                    "location": (x, y)
                }, defects) # Using the mutable default from utils implicitly if we passed nothing, but here we pass 'defects'
                            # Wait, let's make the bug manifest in the report generation phase or usage
                
        return defects

    def generate_report_batch(self, image_paths):
        """Process a batch of images and return report."""
        full_report = {}
        
        for path in image_paths:
            # Here we rely on the utility function that has the mutable default bug
            # if we use it for aggregation
            
            # Actually, let's simplify usage to trigger Bug 2.
            # We will use log_defect to accumulate a global log if we aren't careful
            pass 
            
        return full_report
PYEOF

# Re-writing core.py slightly to better enable the mutable default bug trigger
cat > "$PROJECT_DIR/pcb_inspector/core.py" << 'PYEOF'
import cv2
import numpy as np
from pcb_inspector.utils import log_defect

class PCBInspector:
    def __init__(self, reference_path, config_path):
        self.reference = cv2.imread(reference_path)
        self.rois = self._load_rois(config_path)
        
    def _load_rois(self, config_path):
        rois = []
        with open(config_path, 'r') as f:
            for line in f:
                if line.strip():
                    parts = line.strip().split(',')
                    rois.append(tuple(map(int, parts)))
        return rois

    def inspect(self, test_image_path):
        test_img = cv2.imread(test_image_path)
        if test_img is None:
            return []
            
        # We don't initialize a list here, we rely on log_defect's default
        # to return the accumulated list. This is poor design that exposes the bug.
        current_defects = None 
        
        for i, (x, y, w, h) in enumerate(self.rois):
            # Correct Reference ROI
            ref_roi = self.reference[y:y+h, x:x+w]
            
            # BUG 1: Wrong slicing indices [x:w, y:h] instead of [y:h, x:w]
            try:
                test_roi = test_img[x:x+w, y:y+h]
            except:
                continue

            # Handle shape mismatch from bad slicing
            if ref_roi.shape != test_roi.shape:
                try:
                    test_roi = cv2.resize(test_roi, (ref_roi.shape[1], ref_roi.shape[0]))
                except:
                    continue
            
            # Calculate difference
            diff = cv2.absdiff(ref_roi, test_roi)
            gray_diff = cv2.cvtColor(diff, cv2.COLOR_BGR2GRAY)
            score = np.mean(gray_diff)
            
            # BUG 4: Threshold logic inverted.
            # Missing component -> High Diff. We should flag if score > 30.0
            # Current: flags if score < 30.0 (matches similar/good parts)
            if score < 30.0:
                 # BUG 2 Trigger: Calling log_defect without 2nd arg uses mutable default
                 # So defects from Image 1 stay in the list when Image 2 is processed
                 current_defects = log_defect({
                    "roi_index": i,
                    "score": score,
                    "file": test_image_path
                })
        
        return current_defects if current_defects is not None else []
PYEOF

# --- main.py ---
cat > "$PROJECT_DIR/main.py" << 'PYEOF'
import json
import os
from pcb_inspector.core import PCBInspector

def main():
    inspector = PCBInspector("data/reference.jpg", "data/config.txt")
    
    files = ["data/test_01.jpg", "data/test_02.jpg", "data/test_03.jpg"]
    report = {}
    
    print("Starting inspection...")
    for f in files:
        if os.path.exists(f):
            print(f"Inspecting {f}...")
            # Note: Because of Bug 2 (mutable default), the list returned 
            # will keep growing with previous files' defects
            defects = inspector.inspect(f)
            # Make a copy to snapshot current state (otherwise all report entries point to same big list)
            report[os.path.basename(f)] = list(defects)
            
    with open("report.json", "w") as f:
        json.dump(report, f, indent=2)
    print("Report saved to report.json")

if __name__ == "__main__":
    main()
PYEOF

# ==============================================================================
# 3. Create Tests
# ==============================================================================

cat > "$PROJECT_DIR/tests/test_utils.py" << 'PYEOF'
import pytest
import numpy as np
from pcb_inspector.utils import check_image_properties, log_defect

def test_load_image_safety():
    """Test that checking properties doesn't crash on grayscale images."""
    # Create grayscale image (2D array)
    gray_img = np.zeros((100, 100), dtype=np.uint8)
    
    # This should return (100, 100, 1) or handle it gracefully, but currently raises IndexError
    try:
        h, w, c = check_image_properties(gray_img)
        assert h == 100
        assert w == 100
    except IndexError:
        pytest.fail("check_image_properties crashed on grayscale image (IndexError)")

def test_defect_accumulation():
    """Test that defect logs don't accumulate across calls."""
    # Call 1
    log1 = log_defect({"id": 1})
    assert len(log1) == 1
    
    # Call 2 (should be fresh if not passed)
    # But with mutable default bug, it will have 2 items
    log2 = log_defect({"id": 2})
    
    # We expect a new list, so length 1. 
    # If bug exists, len(log2) will be 2.
    assert len(log2) == 1, "Mutable default argument detected! Defects are leaking between calls."
    assert log2[0]["id"] == 2
PYEOF

cat > "$PROJECT_DIR/tests/test_core.py" << 'PYEOF'
import pytest
import numpy as np
import cv2
import os
from pcb_inspector.core import PCBInspector

@pytest.fixture
def inspector():
    # Setup dummy data
    if not os.path.exists("tests/data"):
        os.makedirs("tests/data")
    
    # Create reference (100x100 green)
    ref = np.zeros((100, 100, 3), dtype=np.uint8)
    ref[:] = (0, 255, 0)
    # Feature at 10,10 size 20x20 (Red)
    cv2.rectangle(ref, (10, 10), (30, 30), (0, 0, 255), -1)
    cv2.imwrite("tests/data/ref.jpg", ref)
    
    # Config
    with open("tests/data/cfg.txt", "w") as f:
        f.write("10,10,20,20\n")
        
    return PCBInspector("tests/data/ref.jpg", "tests/data/cfg.txt")

def test_roi_extraction(inspector):
    """Test if ROI is extracted from correct coordinates."""
    # Create test image with feature shifted
    # If slicing is [x:x+w, y:y+h], it interprets x as row index.
    # We use non-square ROI/Position to catch swapped indices.
    
    # Let's verify by checking internal behavior manually or using a non-square image
    # If x=10, y=50. 
    # Correct: img[50:70, 10:30] (rows 50-70, cols 10-30)
    # Buggy:   img[10:30, 50:70]
    
    inspector.reference = np.zeros((100, 100, 3), dtype=np.uint8)
    # Write unique values to the correct region
    # Region: x=10, y=50, w=20, h=20 -> rows 50:70, cols 10:30
    inspector.reference[50:70, 10:30] = 255
    
    # Update ROI to match
    inspector.rois = [(10, 50, 20, 20)]
    
    # We can't easily access the private extraction logic, but we can infer from results.
    # If we inspect the SAME image, diff should be 0.
    # If slicing is wrong, it will compare Region A (Correct) in Reference against Region B (Swapped) in Test.
    # Since Reference and Test are identical, Region B in Test == Region B in Reference.
    # Region A in Reference != Region B in Test (unless image is uniform).
    
    # So, if we inspect the reference image itself, we should get 0 defects IF the slicing logic is consistent 
    # (even if wrong, consistency might mask it).
    # However, core.py does: ref_roi = ref[y:h, x:w] (CORRECT), test_roi = test[x:w, y:h] (WRONG).
    # This mismatch ensures failure even on identical images.
    
    defects = inspector.inspect("tests/data/ref.jpg")
    
    # Note: With Bug 4 (Threshold inverted), a match (score 0) triggers a defect (< 30).
    # So initially this fails for multiple reasons. 
    # But specifically for ROI, if we fix threshold, this should pass.
    # To isolate ROI bug, we check if the code crashes or produces mismatch.
    
    # Actually, simpler check:
    # NumPy slicing: [row, col]. Row is Y, Col is X.
    # Code has ref[y:y+h, x:x+w] (Correct)
    # Code has test[x:x+w, y:y+h] (Wrong)
    # This guarantees a mismatch diff for non-uniform images.
    
    pass # This test relies on the integration behavior being fixed.

def test_defect_detection_accuracy(inspector):
    """Test that true defects are caught and good parts are passed."""
    # Create Good Image (Same as Ref)
    good_img = np.zeros((100, 100, 3), dtype=np.uint8)
    good_img[:] = (0, 255, 0)
    cv2.rectangle(good_img, (10, 10), (30, 30), (0, 0, 255), -1) # Match
    cv2.imwrite("tests/data/good.jpg", good_img)
    
    # Create Bad Image (Green where Red should be)
    bad_img = np.zeros((100, 100, 3), dtype=np.uint8)
    bad_img[:] = (0, 255, 0)
    # Missing the red rectangle
    cv2.imwrite("tests/data/bad.jpg", bad_img)
    
    # Inspect Good (Expect 0 defects)
    # (Currently fails due to threshold inversion bug: score 0 < 30 -> defect)
    defects_good = inspector.inspect("tests/data/good.jpg")
    
    # Inspect Bad (Expect 1 defect)
    # (Currently fails: score high (e.g. 100) > 30 -> no defect found)
    defects_bad = inspector.inspect("tests/data/bad.jpg")
    
    # Logic for assertion
    # If bugs are fixed: Good=0, Bad=1
    assert len(defects_good) == 0, f"Found false positives in good image: {len(defects_good)}"
    assert len(defects_bad) == 1, f"Failed to detect defect in bad image. Found: {len(defects_bad)}"
PYEOF

# ==============================================================================
# 4. Launch PyCharm
# ==============================================================================

# Record start time
date +%s > /tmp/debug_pcb_start_ts

# Launch PyCharm
echo "Launching PyCharm..."
su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /tmp/pycharm_log.txt 2>&1 &"

# Wait for window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "pcb_inspector"; then
        break
    fi
    sleep 2
done

# Maximize
DISPLAY=:1 wmctrl -r "pcb_inspector" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/pcb_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="