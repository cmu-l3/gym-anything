#!/usr/bin/env python3
"""
Verifier for Land Use Change Analysis (Union Overlay) task.

Verification Logic:
1.  CSV Existence & Creation Time: 10 pts
2.  Valid CSV Format: 10 pts
3.  Combined Attributes (Union Proof): 20 pts
    - Must have columns for both 2015 and 2025 classes.
4.  Area Calculation Field: 15 pts
5.  Data Accuracy (Conservation of Mass & Transition Correctness):
    - Forest -> Urban (~25km2): 20 pts
    - Forest -> Forest (~25km2) + Farm -> Farm (~50km2): 15 pts
    - Total Area (~100km2): 10 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_land_use_change(traj, env_info, task_info):
    """
    Verify the Land Use Change Analysis task.
    """
    # 1. Setup Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Load Results from Container
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

    # 3. Extract Metadata and Analysis
    metadata = task_info.get('metadata', {})
    expected_transitions = metadata.get('transitions', {})
    tolerance = metadata.get('tolerance_sqkm', 1.0)
    
    analysis = result.get('csv_analysis', {})
    
    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Existence & Creation (10 pts) ---
    if result.get('file_exists', False):
        if result.get('file_created_during_task', False):
            score += 10
            feedback_parts.append("CSV file created")
        else:
            score += 5
            feedback_parts.append("CSV file exists but timestamp is old")
    else:
        feedback_parts.append("CSV output file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # --- Criterion 2: Valid CSV Format (10 pts) ---
    if analysis.get('valid_csv', False) and analysis.get('row_count', 0) > 0:
        score += 10
        feedback_parts.append("Valid CSV format")
    else:
        feedback_parts.append("Invalid or empty CSV")
        
    # --- Criterion 3: Combined Attributes / Union Proof (20 pts) ---
    has_2015 = analysis.get('has_class_2015', False)
    has_2025 = analysis.get('has_class_2025', False)
    
    if has_2015 and has_2025:
        score += 20
        feedback_parts.append("Attributes from both years found (Union successful)")
    elif has_2015 or has_2025:
        score += 5
        feedback_parts.append("Only attributes from one year found (Overlay likely failed)")
    else:
        feedback_parts.append("No class attributes found")
        
    # --- Criterion 4: Area Field Present (15 pts) ---
    if analysis.get('has_area_field', False):
        score += 15
        feedback_parts.append("Area calculation field found")
    else:
        feedback_parts.append("No area/sqkm field found")
        
    # --- Criterion 5: Data Accuracy (45 pts total) ---
    sum_forest_urban = analysis.get('sum_forest_urban', 0.0)
    sum_forest_forest = analysis.get('sum_forest_forest', 0.0)
    sum_farm_farm = analysis.get('sum_farm_farm', 0.0)
    total_area = analysis.get('total_area', 0.0)
    
    # 5a. Transition: Forest -> Urban (Target: 25.0) (20 pts)
    target_fu = expected_transitions.get('forest_to_urban', 25.0)
    if abs(sum_forest_urban - target_fu) <= tolerance:
        score += 20
        feedback_parts.append(f"Forest->Urban area correct ({sum_forest_urban:.1f} km2)")
    elif abs(sum_forest_urban - target_fu) <= tolerance * 5: # Partial credit for being close (e.g. units wrong)
        score += 5
        feedback_parts.append(f"Forest->Urban area incorrect ({sum_forest_urban:.1f} km2)")
    else:
        feedback_parts.append(f"Forest->Urban area incorrect ({sum_forest_urban:.1f} km2)")
        
    # 5b. Stable Regions (Target: F->F 25.0, F->F 50.0) (15 pts)
    target_ff = expected_transitions.get('forest_to_forest', 25.0)
    target_farm = expected_transitions.get('farm_to_farm', 50.0)
    
    stable_ok = (abs(sum_forest_forest - target_ff) <= tolerance) and \
                (abs(sum_farm_farm - target_farm) <= tolerance)
    
    if stable_ok:
        score += 15
        feedback_parts.append("Stable land use areas correct")
    else:
        feedback_parts.append(f"Stable areas incorrect (For->For: {sum_forest_forest:.1f}, Farm->Farm: {sum_farm_farm:.1f})")
        
    # 5c. Total Area Conservation (Target: 100.0) (10 pts)
    # This checks if features were dropped or duplicated
    target_total = metadata.get('expected_total_area_sqkm', 100.0)
    if abs(total_area - target_total) <= tolerance:
        score += 10
        feedback_parts.append("Total study area conserved")
    else:
        feedback_parts.append(f"Total area mismatch ({total_area:.1f} vs {target_total} km2)")

    # Final Verification
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "analysis": analysis,
            "score_breakdown": score
        }
    }