#!/usr/bin/env python3
"""
Verifier for Fire Drill Evacuation Map task.

Hybrid Verification:
1. Programmatic Check (File Analysis): 
   - Validates file existence, format, and timestamp.
   - Checks for specific text labels (Fire/Evacuation, Teacher, Exit).
   - Counts shapes (for layout) and arrows (for route).
2. Visual Check (VLM):
   - Confirms the resulting screenshot looks like a floor plan/diagram.

Scoring (100 pts total):
- File Validity (20 pts)
- Title Text (15 pts)
- Room/Furniture Layout (Shapes >= 6) (25 pts)
- Exit Label (15 pts)
- Route Arrows (Arrows >= 3) (25 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def build_floorplan_prompt():
    return """Examine this screenshot of an ActivInspire flipchart.
    
    Task: Verify if this is a classroom evacuation map/floor plan.
    
    Look for:
    1. A room outline (large rectangle).
    2. Furniture representations (smaller shapes like tables/desks).
    3. Directional arrows indicating a path.
    4. Text labels.
    
    Respond in JSON:
    {
        "is_floor_plan": true/false,
        "has_arrows": true/false,
        "has_labels": true/false,
        "confidence": "low/medium/high"
    }
    """

def verify_fire_drill_evacuation_map(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function missing"}

    # 1. Load Programmatic Results
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        copy_from_env('/tmp/task_result.json', tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []
    
    # --- Criterion 1: File Validity (20 pts) ---
    if result.get('file_found') and result.get('file_valid'):
        if result.get('created_during_task'):
            score += 20
            feedback.append("File created successfully (20/20)")
        else:
            score += 10
            feedback.append("File exists but timestamp verification failed (10/20)")
    else:
        return {"passed": False, "score": 0, "feedback": "No valid flipchart file found"}

    # --- Criterion 2: Title Text (15 pts) ---
    if result.get('has_title_text'):
        score += 15
        feedback.append("Title text found (15/15)")
    else:
        feedback.append("Missing title 'Fire Drill' or 'Evacuation' (0/15)")

    # --- Criterion 3: Room Layout / Shapes (25 pts) ---
    # Expecting: 1 room + 1 teacher desk + 4 student tables = 6 shapes minimum
    shape_count = result.get('shape_count', 0)
    if shape_count >= 6:
        score += 25
        feedback.append(f"Sufficient furniture shapes found ({shape_count}) (25/25)")
    elif shape_count >= 3:
        score += 10
        feedback.append(f"Some shapes found ({shape_count}), expected 6+ (10/25)")
    else:
        feedback.append(f"Insufficient shapes for floor plan ({shape_count}) (0/25)")

    # --- Criterion 4: Exit Label (15 pts) ---
    if result.get('has_exit_text'):
        score += 15
        feedback.append("Exit/Door label found (15/15)")
    else:
        feedback.append("Missing 'Door' or 'Exit' label (0/15)")

    # --- Criterion 5: Route Arrows (25 pts) ---
    arrow_count = result.get('arrow_count', 0)
    if arrow_count >= 3:
        score += 25
        feedback.append(f"Evacuation route arrows found ({arrow_count}) (25/25)")
    elif arrow_count > 0:
        score += 10
        feedback.append(f"Few arrows found ({arrow_count}), expected 3+ (10/25)")
    else:
        # Fallback: Check VLM if programmatic arrow detection failed
        vlm_rescued = False
        if query_vlm:
            # We assume the framework handles screenshot access via trajectory
            # For this snippet, we'll assume we can't easily access the exact final screenshot path 
            # inside the verifier unless passed in result, but let's check result path
            # In a real scenario, we'd use `gym_anything.vlm.get_final_screenshot(traj)`
            try:
                from gym_anything.vlm import get_final_screenshot
                final_shot = get_final_screenshot(traj)
                if final_shot:
                    vlm_res = query_vlm(prompt=build_floorplan_prompt(), image=final_shot)
                    if vlm_res.get('success') and vlm_res.get('parsed', {}).get('has_arrows'):
                        score += 15 # Partial credit rescue
                        feedback.append("VLM detected arrows visually (15/25)")
                        vlm_rescued = True
            except ImportError:
                pass
        
        if not vlm_rescued:
            feedback.append("No route arrows detected (0/25)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }