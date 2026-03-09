#!/usr/bin/env python3
"""
Verifier for land_cover_stats_calculation task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_land_cover_stats_calculation(traj, env_info, task_info):
    """
    Verify land cover statistics calculation.
    
    Criteria:
    1. Output file exists and is valid GeoJSON.
    2. Contains histogram fields (counts of pixel classes).
    3. Contains `pct_water` field.
    4. `pct_water` values are numerically correct based on histogram counts.
    5. `pct_water` values match ground truth (Area A ~100%, Area B ~0%).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load result
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
            
    score = 0
    feedback_parts = []
    
    # 1. File Existence & Validity (20 pts)
    if result.get("file_exists", False) and result.get("valid_geojson", False):
        score += 20
        feedback_parts.append("Valid output file found")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file missing or invalid GeoJSON"}
        
    # 2. Feature Count (10 pts)
    if result.get("feature_count") == 2:
        score += 10
        feedback_parts.append("Correct feature count (2)")
    else:
        feedback_parts.append(f"Incorrect feature count: {result.get('feature_count')}")
        
    # 3. Histogram Fields (20 pts)
    # The export script checks for HIST_1 or 1
    if result.get("has_hist_1"):
        score += 20
        feedback_parts.append("Histogram fields found")
    else:
        feedback_parts.append("Missing histogram counts (HIST_1)")
        
    # 4. pct_water Field Existence (15 pts)
    if result.get("has_pct_water"):
        score += 15
        feedback_parts.append("'pct_water' field found")
    else:
        feedback_parts.append("Missing 'pct_water' field")
        
    # 5. Data Logic & Accuracy (35 pts)
    data = result.get("data", [])
    logic_correct_count = 0
    ground_truth_correct_count = 0
    
    for row in data:
        name = row.get("name")
        c1 = row.get("c1", 0)
        c2 = row.get("c2", 0)
        c3 = row.get("c3", 0)
        pct = row.get("pct_water", -1)
        
        total = c1 + c2 + c3
        
        # Check calculation logic
        if total > 0 and pct >= 0:
            expected_pct = (c1 / total) * 100
            if abs(pct - expected_pct) < 1.0: # 1% tolerance for rounding
                logic_correct_count += 1
                
        # Check ground truth
        # Area A (West) should be mostly Water (Class 1) -> High pct
        # Area B (East) should be mostly Forest (Class 2) -> Low pct (near 0)
        if name == "Area A":
            if pct > 80: ground_truth_correct_count += 1
        elif name == "Area B":
            if pct < 20: ground_truth_correct_count += 1
            
    # Score logic (max 15)
    if len(data) > 0 and logic_correct_count == len(data):
        score += 15
        feedback_parts.append("Calculation logic correct")
    elif logic_correct_count > 0:
        score += 7
        feedback_parts.append("Calculation logic partially correct")
    else:
        feedback_parts.append("Calculation logic incorrect (pct_water doesn't match histogram)")
        
    # Score ground truth (max 20)
    if len(data) > 0 and ground_truth_correct_count == len(data):
        score += 20
        feedback_parts.append("Values match ground truth")
    elif ground_truth_correct_count > 0:
        score += 10
        feedback_parts.append("Values partially match ground truth")
    else:
        feedback_parts.append("Values do not match ground truth (wrong data source?)")
        
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }