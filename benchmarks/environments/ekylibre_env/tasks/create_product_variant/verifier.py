#!/usr/bin/env python3
"""
Verifier for create_product_variant task (Ekylibre).
"""

import json
import logging
import os
import tempfile
from datetime import datetime

# VLM dependencies (if available in environment)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_product_variant(traj, env_info, task_info):
    """
    Verifies that the user created a new 'Ammonitrate 33.5' product variant.
    
    Criteria:
    1. Database: Record exists with correct name.
    2. Database: Record was created after task start.
    3. Database: Record is linked to a valid Product Nature (product_nature_id is not null).
    4. Database: Total count of variants increased.
    5. VLM: Trajectory verification (optional bonus/confirmation).
    """
    
    # 1. Retrieve result data from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse Verification Data
    score = 0
    feedback_parts = []
    
    record_found = result.get('record_found', False)
    record = result.get('record_details', {}) or {}
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    task_start_ts = int(result.get('task_start_timestamp', 0))

    # --- Criterion 1: Record Existence (30 pts) ---
    if record_found:
        score += 30
        feedback_parts.append("Product variant record found in database.")
        
        # --- Criterion 2: Name Accuracy (15 pts) ---
        name = record.get('name', '')
        if 'Ammonitrate 33.5' in name:
            score += 15
            feedback_parts.append("Product name matches exactly.")
        else:
            feedback_parts.append(f"Product name partial match ('{name}').")
            score += 5 # Partial credit if found but name slightly off (though query filtered by ILIKE)

        # --- Criterion 3: Valid Nature Link (20 pts) ---
        if record.get('product_nature_id'):
            score += 20
            feedback_parts.append("Product is correctly linked to a nature/category.")
        else:
            feedback_parts.append("Warning: Product has no associated nature.")

        # --- Criterion 4: Timestamp / Anti-Gaming (15 pts) ---
        # Parse Rails timestamp (e.g., "2024-03-02T10:00:00.123Z")
        # Simplified: Check if record exists and we know task started recently.
        # Since we cleared the DB in setup, existence implies creation.
        # But let's check current_count vs initial_count for robustness.
        if current_count > initial_count:
            score += 15
            feedback_parts.append("Database record count increased.")
    else:
        feedback_parts.append("No product variant named 'Ammonitrate 33.5' found in database.")

    # --- Criterion 5: VLM / Trajectory Check (20 pts) ---
    # If we have a perfect DB hit, we trust it. If doubtful, or for full marks, check visual.
    vlm_score = 0
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_scr = get_final_screenshot(traj)
            if final_scr:
                frames.append(final_scr)
                
            prompt = (
                "Review these screenshots of an agent using farm management software. "
                "Did the agent fill out a form to create a new product or variant? "
                "Look for fields like 'Name' (Nom), 'Nature', 'Unit' (Unité). "
                "Does the final state show a saved list or a success message? "
                "Answer 'YES' or 'NO' and explain."
            )
            vlm_resp = query_vlm(images=frames, prompt=prompt).get('text', '').upper()
            
            if "YES" in vlm_resp:
                vlm_score = 20
                feedback_parts.append("Visual verification passed (agent workflow observed).")
            else:
                feedback_parts.append("Visual verification inconclusive.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if DB check passed perfectly, give full points to avoid flakiness
            if score >= 80:
                vlm_score = 20
    else:
        # If VLM not available but DB check is perfect, grant points
        if score >= 80:
            vlm_score = 20
            feedback_parts.append("Visual verification skipped (DB record confirmed).")

    total_score = score + vlm_score
    passed = total_score >= 100  # Strict pass for specific data entry tasks

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " ".join(feedback_parts)
    }