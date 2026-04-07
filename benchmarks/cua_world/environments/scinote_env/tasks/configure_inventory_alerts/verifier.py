#!/usr/bin/env python3
"""
Verifier for configure_inventory_alerts task.

HYBRID VERIFICATION STRATEGY:
1. Programmatic state: Queries SciNote's EAV structure for column existence.
2. Anti-gaming (Timestamps): Validates row `updated_at` timestamps > task start time.
3. Database explicit validation: Checks if the DB contains exact recorded values (200, 400).
4. VLM visual validation: Supplements DB check in case of schema variations by verifying 
   if the correct values are visible on the trajectory frames.
"""

import json
import os
import sys
import tempfile
import logging

# Ensure vlm_utils is available if executed in the framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_inventory_vlm_prompt(item1, val1, item2, val2):
    return f"""Examine this sequence of screenshots from an Electronic Lab Notebook (SciNote).

TASK: Verify that low-stock alert thresholds were configured in the inventory table.

Look closely at the table interface for these specific configurations:
1. Do you see a column indicating "Minimum Stock" (or similar threshold naming)?
2. Do you see the row '{item1}'? Does it have a minimum stock value set to '{val1}'?
3. Do you see the row '{item2}'? Does it have a minimum stock value set to '{val2}'?

Respond with a JSON object containing:
{{
    "column_created": true/false,
    "item1_value_set": true/false,
    "item2_value_set": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what is visible"
}}"""


def verify_configure_inventory_alerts(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    item1_name = metadata.get('item1_name', 'Taq DNA Polymerase')
    item1_min_val = str(metadata.get('item1_min_value', 200))
    item2_name = metadata.get('item2_name', 'dNTP Mix 10mM')
    item2_min_val = str(metadata.get('item2_min_value', 400))

    # Read exported JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/configure_inventory_alerts_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    repo_found = result.get('repo_found', False)
    if not repo_found:
        return {"passed": False, "score": 0, "feedback": "Repository 'PCR Reagents' not found or script errored."}

    task_start = float(result.get('task_start', 0))
    has_column = result.get('has_minimum_stock_column', False)
    taq_updated = float(result.get('taq_updated_at', 0)) > task_start
    dntp_updated = float(result.get('dntp_updated_at', 0)) > task_start
    
    db_taq_val = result.get('taq_value', '').strip()
    db_dntp_val = result.get('dntp_value', '').strip()

    # --- CRITERION 1: Column Creation (20 pts) ---
    if has_column:
        score += 20
        feedback_parts.append("Column 'Minimum Stock' created successfully")
    else:
        feedback_parts.append("Column 'Minimum Stock' missing")

    # --- CRITERION 2: Rows Modified Anti-gaming (20 pts) ---
    if taq_updated and dntp_updated:
        score += 20
        feedback_parts.append("Both items modified during task execution")
    elif taq_updated or dntp_updated:
        score += 10
        feedback_parts.append("Only one item modified during task execution")
    else:
        feedback_parts.append("Neither item was modified during task execution (potential 'do nothing')")

    # --- CRITERION 3 & 4: Exact Database Values (30 pts) ---
    exact_db_match = False
    taq_exact = False
    dntp_exact = False
    
    if db_taq_val == item1_min_val:
        taq_exact = True
    elif item1_min_val in db_taq_val:  # Account for '200.0'
        taq_exact = True

    if db_dntp_val == item2_min_val:
        dntp_exact = True
    elif item2_min_val in db_dntp_val:
        dntp_exact = True

    if taq_exact and dntp_exact:
        score += 60  # Full DB verification logic complete!
        exact_db_match = True
        feedback_parts.append(f"DB perfectly matches configured values ({item1_min_val}, {item2_min_val})")
    
    # --- CRITERION 5: VLM Fallback/Validation (Up to 60 pts if DB schema missed value parsing) ---
    if not exact_db_match and VLM_AVAILABLE:
        logger.info("Database values not exactly matching, falling back to VLM trajectory visual check...")
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final_frame = get_final_screenshot(traj)
            
            # De-duplicate if trajectory is short
            all_frames = frames + [final_frame] if final_frame else frames
            
            prompt = build_inventory_vlm_prompt(item1_name, item1_min_val, item2_name, item2_min_val)
            vlm_response = query_vlm(images=all_frames, prompt=prompt)
            
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                vlm_taq = parsed.get("item1_value_set", False)
                vlm_dntp = parsed.get("item2_value_set", False)
                
                if vlm_taq:
                    score += 30
                    feedback_parts.append("VLM visually confirmed Taq value set")
                if vlm_dntp:
                    score += 30
                    feedback_parts.append("VLM visually confirmed dNTP value set")
                    
        except Exception as e:
            logger.error(f"VLM fallback failed: {e}")
            feedback_parts.append("VLM fallback unavailable/failed")

    # Safety Cap
    score = min(100, score)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "has_column": has_column,
            "items_modified": taq_updated and dntp_updated,
            "values_verified": exact_db_match or score >= 80
        }
    }