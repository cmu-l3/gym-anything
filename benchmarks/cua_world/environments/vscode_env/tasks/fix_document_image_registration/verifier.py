#!/usr/bin/env python3
"""
Verifier for the fix_document_image_registration task.

Evaluates 5 specific bugs in the OpenCV/NumPy document processing pipeline:
1. Template matching (max_loc instead of min_loc)
2. Order points for perspective transform (correct sorting)
3. Color binarization (Grayscale instead of HSV)
4. Morphological operations (horizontal kernel dimensions)
5. NumPy array slicing (row-major [y, x])

Each fix is worth 20 points.
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_image_registration_pipeline(traj, env_info, task_info):
    """Verifies that the agent fixed the CV pipeline logic."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/doc_registration_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    files = result.get('files', {})
    aligner_src = files.get('aligner', '')
    preprocessor_src = files.get('preprocessor', '')
    roi_src = files.get('roi_extractor', '')
    
    score = 0
    feedback_parts = []

    # -------------------------------------------------------------
    # Bug 1: Template Matching `min_loc` -> `max_loc`
    # -------------------------------------------------------------
    if "return max_loc" in aligner_src or re.search(r'return\s+max_loc', aligner_src):
        score += 20
        feedback_parts.append("[+] Aligner: Fixed template matching to use max_loc (20/20)")
    else:
        feedback_parts.append("[-] Aligner: Still returning min_loc for TM_CCOEFF_NORMED (0/20)")

    # -------------------------------------------------------------
    # Bug 2: Perspective Transform `order_points`
    # -------------------------------------------------------------
    # Correct mapping: rect[1] should be top-right (argmin diff), rect[2] should be bottom-right (argmax sum)
    has_fixed_sort = (
        (re.search(r'rect\[1\]\s*=\s*pts\[np\.argmin\(diff\)\]', aligner_src) and 
         re.search(r'rect\[2\]\s*=\s*pts\[np\.argmax\(s\)\]', aligner_src)) or
        (re.search(r'rect\[2\]\s*=\s*pts\[np\.argmax\(s\)\]', aligner_src) and
         re.search(r'rect\[1\]\s*=\s*pts\[np\.argmin\(diff\)\]', aligner_src))
    )
    if has_fixed_sort:
        score += 20
        feedback_parts.append("[+] Aligner: Fixed spatial corner ordering (20/20)")
    else:
        feedback_parts.append("[-] Aligner: Incorrect corner point sorting remains (0/20)")

    # -------------------------------------------------------------
    # Bug 3: Color Binarization `HSV` -> `Grayscale`
    # -------------------------------------------------------------
    has_grayscale = "cv2.COLOR_BGR2GRAY" in preprocessor_src
    still_has_hsv = "cv2.COLOR_BGR2HSV" in preprocessor_src
    
    if has_grayscale and not still_has_hsv:
        score += 20
        feedback_parts.append("[+] Preprocessor: Fixed binarization to use Grayscale channel (20/20)")
    elif has_grayscale:
        score += 10
        feedback_parts.append("[~] Preprocessor: Grayscale added but HSV remains partially (10/20)")
    else:
        feedback_parts.append("[-] Preprocessor: Still binarizing using HSV Hue channel (0/20)")

    # -------------------------------------------------------------
    # Bug 4: Morphological Filter Dimensions `(1, 25)` -> `(25, 1)`
    # -------------------------------------------------------------
    has_horizontal_kernel = re.search(r'\(\s*(25|30|40)\s*,\s*1\s*\)', preprocessor_src)
    if has_horizontal_kernel:
        score += 20
        feedback_parts.append("[+] Preprocessor: Fixed structuring element to detect horizontal lines (20/20)")
    else:
        feedback_parts.append("[-] Preprocessor: Structuring element still favors vertical lines (0/20)")

    # -------------------------------------------------------------
    # Bug 5: NumPy array slicing `[x, y]` -> `[y, x]`
    # -------------------------------------------------------------
    # Checks if returned slice is y-major e.g. return image[y:y+h, x:x+w]
    has_y_major_slice = re.search(r'image\s*\[\s*y\s*:\s*y\s*\+\s*h\s*,\s*x\s*:\s*x\s*\+\s*w\s*\]', roi_src)
    if has_y_major_slice:
        score += 20
        feedback_parts.append("[+] ROI Extractor: Fixed NumPy row-major slicing array logic (20/20)")
    else:
        feedback_parts.append("[-] ROI Extractor: Still using incorrect column-major slicing [x, y] (0/20)")

    # -------------------------------------------------------------
    # Test Suite Verification (Anti-gaming check)
    # -------------------------------------------------------------
    pytest_passed = result.get('pytest_passed', 0)
    if pytest_passed == 5:
        feedback_parts.append("[+] Pytest Suite: All 5 tests passed successfully.")
    else:
        feedback_parts.append(f"[-] Pytest Suite: Only {pytest_passed}/5 tests passed.")

    passed = (score >= 60 and pytest_passed >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }