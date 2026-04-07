#!/usr/bin/env python3
import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_debug_pcb_defect_detector(traj, env_info, task_info):
    """
    Verify the PCB Defect Detector debugging task.
    
    Criteria:
    1. Tests Passed (40 pts): Code logic corrected.
    2. Report Accuracy (40 pts): Correct defect counts in report.json.
    3. Code Check (20 pts): Static analysis of key lines.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/debug_pcb_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Test Results (Max 40)
    pytest_out_b64 = result.get("pytest_output", "")
    try:
        pytest_out = base64.b64decode(pytest_out_b64).decode('utf-8')
    except:
        pytest_out = ""
        
    passed_tests = pytest_out.count("PASSED")
    failed_tests = pytest_out.count("FAILED")
    
    # We expect roughly 3 specific tests: test_load_image_safety, test_defect_accumulation, test_defect_detection_accuracy
    if "test_load_image_safety PASSED" in pytest_out:
        score += 10
        feedback.append("Fixed grayscale crash (IndexError).")
    else:
        feedback.append("Failed test_load_image_safety.")
        
    if "test_defect_accumulation PASSED" in pytest_out:
        score += 10
        feedback.append("Fixed mutable default argument.")
    else:
        feedback.append("Failed test_defect_accumulation.")
        
    if "test_defect_detection_accuracy PASSED" in pytest_out:
        score += 20
        feedback.append("Fixed defect detection accuracy (ROI + Threshold).")
    else:
        feedback.append("Failed test_defect_detection_accuracy.")

    # 2. Report Accuracy (Max 40)
    report = result.get("report_json", {})
    expected = {
        "test_01.jpg": 0, # Clean
        "test_02.jpg": 1, # 1 defect
        "test_03.jpg": 2  # 2 defects
    }
    
    report_score = 0
    for filename, expected_count in expected.items():
        actual = report.get(filename, [])
        # Actual is a list of defects, we count them
        actual_count = len(actual)
        
        if actual_count == expected_count:
            report_score += 13 # 13*3 = 39 approx
            feedback.append(f"Correct count for {filename}.")
        else:
            feedback.append(f"Wrong count for {filename}: Expected {expected_count}, Got {actual_count}.")
            
    # Cap report score
    if report_score > 40: report_score = 40
    score += report_score

    # 3. Static Analysis (Max 20)
    # This is a fallback to verify specifically HOW it was fixed if tests are ambiguous
    static = result.get("static_analysis", {})
    if static.get("roi_fixed"):
        score += 10
    if static.get("thresh_fixed"):
        score += 10
        
    # Cap total
    if score > 100: score = 100
    
    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " ".join(feedback)
    }