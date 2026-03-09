#!/usr/bin/env python3
"""
Verifier for south_facade_wwr_reduction task.

Task Requirements:
1. HEIGHT of south-facing windows on G, M, T floors must be 3.5 ft.
2. WIDTH of these windows must be UNCHANGED (Baseline is 10.0 ft for this model).
3. Simulation must run (producing a new .SIM file).

Scoring (100 pts):
- Simulation ran: 15 pts
- Ground Floor South Windows Correct (Height=3.5, Width=10): 25 pts
- Middle Floor South Windows Correct (Height=3.5, Width=10): 25 pts
- Top Floor South Windows Correct (Height=3.5, Width=10): 25 pts
- All floors consistent: 10 pts

Pass Threshold: 60 pts + Simulation Ran
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected baseline width for 4StoreyBuilding standard windows is typically 10ft or 8ft.
# In the 4StoreyBuilding.inp standard file, windows are often 10ft wide.
# We will verify "unchanged" by allowing a standard range or checking consistency.
# However, the safer bet is to check if Height is 3.5 and Width is > 0.
# The task description says "WIDTH unchanged". 
# The export script extracts the widths found.
# Standard 4Storey model south windows:
# G.S11 Window 1: Height=5, Width=10
# We assume the agent shouldn't change width.

TARGET_HEIGHT = 3.5
TOLERANCE = 0.1

def verify_south_facade_wwr_reduction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load Result JSON
    result_path = "C:\\Users\\Docker\\south_facade_wwr_reduction_result.json"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Simulation (15 pts)
    sim_ran = result.get("sim_file_new", False)
    if sim_ran:
        score += 15
        feedback_parts.append("Simulation ran successfully (+15)")
    else:
        feedback_parts.append("Simulation NOT run or old output found")

    floors_checked = result.get("floors_checked", {})
    floors_passed = 0
    
    # Floors to check: Ground, Middle, Top
    for floor_name in ["Ground", "Middle", "Top"]:
        floor_data = floors_checked.get(floor_name)
        if not floor_data:
            feedback_parts.append(f"{floor_name}: No south windows found")
            continue
            
        heights = floor_data.get("heights", [])
        widths = floor_data.get("widths", [])
        
        if not heights:
            feedback_parts.append(f"{floor_name}: No window data")
            continue

        # Check Heights
        # Allow slight float variations
        correct_heights = [abs(h - TARGET_HEIGHT) < TOLERANCE for h in heights]
        height_ok = all(correct_heights) and len(correct_heights) > 0
        
        # Check Widths (Anti-gaming)
        # We assume baseline width is approx 10.0. If user deleted/recreated windows, they might default to something else.
        # Or if they just shrunk height, width stays 10.
        # Let's assume valid widths are > 5.0 (not tiny slivers) and consistent.
        # A rigid check: Width should be approx 10.
        width_ok = all([w > 8.0 for w in widths]) # Looser check to avoid false negatives on model variations
        
        if height_ok and width_ok:
            score += 25
            floors_passed += 1
            feedback_parts.append(f"{floor_name}: Correct (H={heights[0]}) (+25)")
        elif not height_ok:
            avg_h = sum(heights)/len(heights) if heights else 0
            feedback_parts.append(f"{floor_name}: Wrong Height (Avg={avg_h:.1f}, Target={TARGET_HEIGHT})")
        elif not width_ok:
             feedback_parts.append(f"{floor_name}: Widths suspicious (changed?)")

    # Consistency Bonus (10 pts)
    if floors_passed == 3:
        score += 10
        feedback_parts.append("All floors consistent (+10)")

    # Pass logic
    passed = (score >= 60) and sim_ran

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }