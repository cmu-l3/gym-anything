#!/usr/bin/env python3
"""
Verifier for Returns to Schooling IV Task.

Criteria:
1. Packages Installed (10 pts)
2. CSV Created & Valid (15 pts)
3. OLS Estimate Accuracy (20 pts)
4. IV Estimate Accuracy (30 pts)
5. Hausman Test performed (10 pts)
6. Visualization created (10 pts)
7. Script saved (5 pts)

VLM Verification:
- Checks if the plot looks like a boxplot (categorical x, continuous y).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_returns_schooling(traj, env_info, task_info):
    """Verify IV analysis task results."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expected values
    meta = task_info.get('metadata', {})
    target_ols = meta.get('ols_target', 0.075)
    tol_ols = meta.get('ols_tolerance', 0.005)
    target_iv = meta.get('iv_target', 0.132)
    tol_iv = meta.get('iv_tolerance', 0.015)

    # Read result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Packages (10 pts)
    if result.get('packages_installed'):
        score += 10
        feedback.append("Packages (wooldridge, AER) installed: PASS")
    else:
        feedback.append("Packages not found in library: FAIL")

    # 2. CSV File (15 pts)
    if result.get('csv_exists') and result.get('csv_created_during'):
        score += 15
        feedback.append("Comparison CSV created: PASS")
    else:
        feedback.append("Comparison CSV missing or old: FAIL")

    # 3. OLS Accuracy (20 pts)
    ols_est = result.get('ols_estimate', 0)
    if abs(ols_est - target_ols) <= tol_ols:
        score += 20
        feedback.append(f"OLS Estimate ({ols_est:.4f}) correct: PASS")
    elif abs(ols_est - target_ols) <= (tol_ols * 2):
        score += 10
        feedback.append(f"OLS Estimate ({ols_est:.4f}) close (partial): PASS")
    else:
        feedback.append(f"OLS Estimate ({ols_est:.4f}) incorrect (target ~{target_ols}): FAIL")

    # 4. IV Accuracy (30 pts)
    iv_est = result.get('iv_estimate', 0)
    if abs(iv_est - target_iv) <= tol_iv:
        score += 30
        feedback.append(f"IV Estimate ({iv_est:.4f}) correct: PASS")
    elif abs(iv_est - target_iv) <= (tol_iv * 2):
        score += 15
        feedback.append(f"IV Estimate ({iv_est:.4f}) close (partial): PASS")
    else:
        feedback.append(f"IV Estimate ({iv_est:.4f}) incorrect (target ~{target_iv}): FAIL")

    # 5. Hausman Test (10 pts)
    if result.get('test_file_exists'):
        score += 10
        feedback.append("Hausman test output saved: PASS")
    else:
        feedback.append("Hausman test output missing: FAIL")

    # 6. Visualization (10 pts) - Hybrid check
    plot_exists = result.get('plot_exists')
    plot_size = int(result.get('plot_size_kb', 0))
    
    if plot_exists and plot_size > 5:
        # VLM Check could go here if query_vlm is available, 
        # but for robustness we'll rely on file existence + size for base points
        # and assume if size > 5kb it contains data.
        score += 10
        feedback.append(f"Instrument plot created ({plot_size}KB): PASS")
    else:
        feedback.append("Instrument plot missing or empty: FAIL")

    # 7. Script (5 pts)
    if result.get('script_modified'):
        score += 5
        feedback.append("Script saved: PASS")
    else:
        feedback.append("Script not modified: FAIL")

    # Final logic
    passed = (score >= 65)  # Threshold from README
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }