#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_executive_dashboard(traj, env_info, task_info):
    """
    Verify the fix_executive_dashboard task.
    
    Criteria:
    1. Chronological Sorting Fixed (25 pts)
    2. Stacked Bars Fixed (25 pts)
    3. Axis Scaling Fixed (25 pts)
    4. Pie Legend Fixed (25 pts)
    
    Deduction if dashboard.png not generated.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}
    
    task_name = "fix_executive_dashboard"
    result_file = f"/tmp/{task_name}_result.json"
    
    # Read Result
    tmp_path = tempfile.mktemp()
    try:
        copy_from_env(result_file, tmp_path)
        with open(tmp_path, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
            
    score = 0
    feedback = []
    
    # Check Test Results
    if data.get("pass_date_sort", 0) > 0:
        score += 25
        feedback.append("Fixed: Timeline is now chronological.")
    else:
        feedback.append("Failed: Timeline is still not chronological.")
        
    if data.get("pass_stacked_bars", 0) > 0:
        score += 25
        feedback.append("Fixed: Bar chart is properly stacked.")
    else:
        feedback.append("Failed: Bar chart is not stacked (overlapping).")
        
    if data.get("pass_axis_scaling", 0) > 0:
        score += 25
        feedback.append("Fixed: Y-Axis scaling matches label.")
    else:
        feedback.append("Failed: Y-Axis scaling mismatch.")
        
    if data.get("pass_pie_legend", 0) > 0:
        score += 25
        feedback.append("Fixed: Pie chart legend matches slices.")
    else:
        feedback.append("Failed: Pie chart legend mismatch.")
        
    # Check Output Generation
    if not data.get("output_generated_during_task", False):
        score = max(0, score - 10)
        feedback.append("Warning: dashboard.png was not regenerated (-10 pts).")
    
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }