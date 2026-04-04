#!/usr/bin/env python3
"""
Verifier for join_table_to_layer task.

Verifies:
1. Output shapefile exists with valid extensions
2. Output was created during the task (anti-gaming)
3. Output contains joined fields from CSV
4. Data integrity: Check specific values (USA CO2, China LifeExp)
5. Visual verification using VLM
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_join_table_to_layer(traj, env_info, task_info):
    """
    Verify that the agent joined the CSV table to the shapefile and exported it.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # ----------------------------------------------------------------
    # Criterion 1: File Existence (20 pts)
    # ----------------------------------------------------------------
    if result.get("files_exist", False):
        score += 20
        feedback.append("Output shapefile and companion files exist (+20)")
    elif result.get("shp_exists", False):
        score += 10
        feedback.append("Output .shp exists but missing .shx/.dbf (+10)")
    else:
        feedback.append("Output shapefile NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # ----------------------------------------------------------------
    # Criterion 2: Anti-Gaming / Timestamp (10 pts)
    # ----------------------------------------------------------------
    if result.get("file_created_during_task", False):
        score += 10
        feedback.append("File created during task session (+10)")
    else:
        feedback.append("File timestamp predates task (possible gaming)")

    # ----------------------------------------------------------------
    # Criterion 3: Schema Verification (25 pts)
    # ----------------------------------------------------------------
    field_names = result.get("field_names", [])
    joined_fields_found = 0
    target_keywords = ["CO2", "LIFE", "LE00", "INTERNET", "NET_USER"]
    
    # Check if we have fields matching the CSV columns
    found_keywords = set()
    for f in field_names:
        for kw in target_keywords:
            if kw in f.upper():
                found_keywords.add(kw)
    
    # Group by concept (CO2, Life, Internet)
    has_co2 = any("CO2" in k for k in found_keywords)
    has_life = any("LIFE" in k or "LE00" in k for k in found_keywords)
    has_net = any("NET" in k or "INTERNET" in k for k in found_keywords)
    
    joined_count = sum([has_co2, has_life, has_net])
    
    if joined_count >= 3:
        score += 25
        feedback.append("All 3 indicator fields found in output (+25)")
    elif joined_count > 0:
        pts = joined_count * 8
        score += pts
        feedback.append(f"{joined_count}/3 indicator fields found (+{pts})")
    else:
        feedback.append("No joined indicator fields found in output schema")

    # Check field count increase
    orig_count = result.get("original_field_count", 0)
    curr_count = result.get("field_count", 0)
    if orig_count > 0 and curr_count > orig_count:
        score += 5
        feedback.append("Field count increased (+5)")

    # ----------------------------------------------------------------
    # Criterion 4: Data Value Verification (30 pts)
    # ----------------------------------------------------------------
    # USA CO2 (Expected ~13.68)
    usa_val = result.get("usa_co2")
    if usa_val is not None and abs(usa_val - 13.68) < 3.0:
        score += 15
        feedback.append(f"USA CO2 value correct ({usa_val}) (+15)")
    else:
        feedback.append(f"USA CO2 value incorrect or missing (Got: {usa_val})")

    # China Life Exp (Expected ~77.10)
    chn_val = result.get("chn_life_exp")
    if chn_val is not None and abs(chn_val - 77.10) < 3.0:
        score += 15
        feedback.append(f"China Life Expectancy correct ({chn_val}) (+15)")
    else:
        feedback.append(f"China Life Expectancy incorrect or missing (Got: {chn_val})")

    # ----------------------------------------------------------------
    # Criterion 5: VLM Verification (10 pts)
    # ----------------------------------------------------------------
    # Use VLM to check if the user actually interacted with the Join dialog
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    Analyze these screenshots of a GIS software (gvSIG).
    Did the user perform a table join operation?
    Look for:
    1. The "Join" or "Enlace" dialog box.
    2. Selection of "Table" and "Layer".
    3. The attribute table being open showing many columns.
    
    Answer YES or NO and explain briefly.
    """
    
    vlm_response = query_vlm(images=frames, prompt=vlm_prompt).strip().lower()
    
    if "yes" in vlm_response:
        score += 10
        feedback.append("Visual verification passed (Join dialog detected) (+10)")
    else:
        feedback.append("Visual verification inconclusive")

    # ----------------------------------------------------------------
    # Final Result
    # ----------------------------------------------------------------
    # Pass threshold: 60 points + Key Data Criteria met
    key_criteria_met = (result.get("files_exist") and joined_count >= 1)
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }