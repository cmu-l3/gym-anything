#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_file_carver(traj, env_info, task_info):
    """
    Verify that the file carver task was completed successfully.
    
    Criteria:
    1. Unit tests pass (20 pts)
    2. Recovered 4 files total (20 pts)
    3. Recovered JPEG 1 correctly (15 pts)
    4. Recovered JPEG 2 correctly (15 pts)
    5. Recovered PNG 1 correctly (15 pts)
    6. Recovered PNG 2 correctly (15 pts)
    
    Total: 100 pts
    Pass Threshold: 70 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    task_name = "implement_file_carver"
    result_path = f"/tmp/{task_name}_result.json"
    
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env(result_path, tmp_path)
            with open(tmp_path, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Result JSON malformed"}
        
    score = 0
    feedback_parts = []
    
    # 1. Unit Tests (20 pts)
    tests_passed = result.get("tests_passed", 0)
    pytest_code = result.get("pytest_exit_code", -1)
    
    if pytest_code == 0 and tests_passed >= 4:
        score += 20
        feedback_parts.append("Unit tests passed (20/20)")
    elif tests_passed > 0:
        score += 10
        feedback_parts.append(f"Some unit tests passed: {tests_passed} (10/20)")
    else:
        feedback_parts.append("Unit tests failed (0/20)")
        
    # 2. File Count (20 pts)
    recovered_count = result.get("recovered_count", 0)
    if recovered_count >= 4:
        score += 20
        feedback_parts.append(f"Recovered {recovered_count} files (20/20)")
    elif recovered_count > 0:
        score += 5 * recovered_count
        feedback_parts.append(f"Recovered {recovered_count} files ({5*recovered_count}/20)")
    else:
        feedback_parts.append("No files recovered (0/20)")
        
    # 3-6. Content Verification (60 pts total, 15 each)
    found_jpg_1 = result.get("found_jpg_1", False)
    found_jpg_2 = result.get("found_jpg_2", False)
    found_png_1 = result.get("found_png_1", False)
    found_png_2 = result.get("found_png_2", False)
    
    if found_jpg_1:
        score += 15
        feedback_parts.append("JPEG #1 recovered (15/15)")
    else:
        feedback_parts.append("JPEG #1 missing")

    if found_jpg_2:
        score += 15
        feedback_parts.append("JPEG #2 recovered (15/15)")
    else:
        feedback_parts.append("JPEG #2 missing")

    if found_png_1:
        score += 15
        feedback_parts.append("PNG #1 recovered (15/15)")
    else:
        feedback_parts.append("PNG #1 missing")

    if found_png_2:
        score += 15
        feedback_parts.append("PNG #2 recovered (15/15)")
    else:
        feedback_parts.append("PNG #2 missing")
        
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }