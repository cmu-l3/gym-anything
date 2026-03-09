#!/usr/bin/env python3
"""
Verifier for ftth_gpon_network_design task.
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

def verify_ftth_gpon_network_design(traj, env_info, task_info):
    """
    Verify the GPON network design and calculations.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Metadata contains the ground truth calculated values
    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    
    # Ground truth values
    target_a = ground_truth.get('house_a_dbm', -19.67)
    target_b = ground_truth.get('house_b_dbm', -20.51)
    target_c = ground_truth.get('house_c_dbm', -19.09)
    tolerance = ground_truth.get('tolerance', 0.5)

    # Read result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    analysis = result.get('analysis', {})
    score = 0
    feedback = []
    
    # 1. File Artifacts (20 pts)
    if result.get('file_exists') and result.get('file_modified'):
        score += 10
        feedback.append("Draw.io file saved and modified")
    else:
        feedback.append("Draw.io file missing or not modified")
        
    if result.get('pdf_exists'):
        score += 10
        feedback.append("PDF export found")
    else:
        feedback.append("PDF export missing")
        
    # 2. Topology / Keywords (30 pts)
    # Check if necessary components are mentioned in the diagram
    has_olt = analysis.get('has_olt', False)
    has_splitter = analysis.get('has_splitter', False)
    has_ont = analysis.get('has_ont', False)
    shape_count = analysis.get('shape_count', 0)
    
    if has_olt: score += 5
    if has_splitter: score += 5
    if has_ont: score += 5
    
    if shape_count >= 8:
        score += 15
        feedback.append(f"Sufficient shapes count: {shape_count}")
    elif shape_count >= 5:
        score += 5
        feedback.append(f"Low shape count: {shape_count}")
    else:
        feedback.append("Diagram is nearly empty")

    if not (has_olt and has_splitter and has_ont):
        feedback.append("Missing some required components (OLT, Splitter, or ONT)")
    else:
        feedback.append("All key components (OLT, Splitter, ONT) identified")

    # 3. Calculation Accuracy (50 pts)
    # We scan all numbers found in the diagram text and see if they match our targets
    numbers = analysis.get('numbers_found', [])
    
    def check_value(target, nums, tol):
        for n in nums:
            if math.isclose(n, target, abs_tol=tol):
                return True
        return False
        
    # Check House A (-19.67)
    if check_value(target_a, numbers, tolerance):
        score += 15
        feedback.append(f"House A calculation correct (found value near {target_a})")
    else:
        feedback.append(f"House A calculation incorrect or missing (expected ~{target_a})")
        
    # Check House B (-20.51)
    if check_value(target_b, numbers, tolerance):
        score += 15
        feedback.append(f"House B calculation correct (found value near {target_b})")
    else:
        feedback.append(f"House B calculation incorrect or missing (expected ~{target_b})")
        
    # Check House C (-19.09)
    if check_value(target_c, numbers, tolerance):
        score += 15
        feedback.append(f"House C calculation correct (found value near {target_c})")
    else:
        feedback.append(f"House C calculation incorrect or missing (expected ~{target_c})")
        
    # Bonus for labeling distances (5 pts)
    # Check if common distances like 12, 2, 4.5, 0.5 exist in the numbers
    distances_found = 0
    for d in [12, 2, 4.5, 0.5, 0.2, 0.1]:
        if check_value(d, numbers, 0.05):
            distances_found += 1
            
    if distances_found >= 3:
        score += 5
        feedback.append("Distance labels found")
        
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }