#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_ecommerce_scraper(traj, env_info, task_info):
    """
    Verify that the ecommerce scraper was fixed to handle the new HTML structure.
    
    Scoring:
    - Title Extraction: 20 pts (Tests pass)
    - Price Extraction: 25 pts (Tests pass)
    - Availability: 20 pts (Tests pass)
    - Specs Parsing: 25 pts (Tests pass)
    - Clean Execution: 10 pts (All tests pass + no errors)
    
    Threshold: 85 pts
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    task_name = "fix_ecommerce_scraper"
    result_path = f"/tmp/{task_name}_result.json"

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env(result_path, tmp_path)
            with open(tmp_path, "r") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []

    # Criterion 1: Title Extraction (20 pts)
    if result.get("pass_title", False):
        score += 20
        feedback.append("Title extraction fixed (20/20)")
    else:
        feedback.append("Title extraction tests failed")

    # Criterion 2: Price Extraction (25 pts)
    if result.get("pass_price", False):
        score += 25
        feedback.append("Price extraction fixed (25/25)")
    else:
        feedback.append("Price extraction tests failed")

    # Criterion 3: Availability (20 pts)
    if result.get("pass_availability", False):
        score += 20
        feedback.append("Availability logic fixed (20/20)")
    else:
        feedback.append("Availability tests failed")

    # Criterion 4: Specs Parsing (25 pts)
    if result.get("pass_specs", False):
        score += 25
        feedback.append("Specs parsing fixed (25/25)")
    else:
        feedback.append("Specs parsing tests failed")

    # Criterion 5: Clean Run (10 pts)
    if result.get("all_tests_pass", False):
        score += 10
        feedback.append("All tests passed cleanly (10/10)")
    else:
        # Check robustness via parameterized tests results (implicit in all_tests_pass)
        # If specific tests passed but overall failed, user gets partial points above
        pass
    
    # Check for hardcoding suspicion (Optional feedback)
    if result.get("pass_title") and not result.get("uses_data_testid"):
        feedback.append("(Note: Title test passed but 'data-testid' not found in code - ensure robustness)")

    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }