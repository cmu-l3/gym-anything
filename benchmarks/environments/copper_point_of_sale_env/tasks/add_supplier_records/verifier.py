#!/usr/bin/env python3
"""
Verifier for add_supplier_records task.

Checks:
1. Data Verification: Checks if supplier names and details exist in Copper's data files.
2. Anti-Gaming: Verifies files were actually modified during the task window.
3. VLM Verification: Uses trajectory to verify UI navigation and data entry steps.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_supplier_records(traj, env_info, task_info):
    """
    Verify that two specific supplier records were added to Copper POS.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Fetch JSON result from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Evaluate Data Persistence (50 points max)
    
    # Supplier 1: Pacific Coast Distributors
    s1_found = result.get('supplier1_found', False)
    s1_details = result.get('supplier1_details_score', 0) # Max 4
    
    if s1_found:
        score += 15
        feedback_parts.append("Pacific Coast Distributors record found (+15)")
        # Scale detail score: 4 details -> 10 points
        detail_points = min(10, int((s1_details / 4) * 10))
        score += detail_points
        if detail_points > 0:
            feedback_parts.append(f"Supplier 1 details verified (+{detail_points})")
    else:
        feedback_parts.append("Pacific Coast Distributors record NOT found")

    # Supplier 2: Heartland Wholesale Supply
    s2_found = result.get('supplier2_found', False)
    s2_details = result.get('supplier2_details_score', 0) # Max 4
    
    if s2_found:
        score += 15
        feedback_parts.append("Heartland Wholesale Supply record found (+15)")
        detail_points = min(10, int((s2_details / 4) * 10))
        score += detail_points
        if detail_points > 0:
            feedback_parts.append(f"Supplier 2 details verified (+{detail_points})")
    else:
        feedback_parts.append("Heartland Wholesale Supply record NOT found")

    # Anti-gaming: Files modified check
    files_modified = result.get('files_modified', False)
    if files_modified:
        # This is a prerequisite for a high score but doesn't add points directly 
        # (prevents reading old stale data)
        pass 
    elif (s1_found or s2_found):
        score = 0 # ZERO SCORE if data found but files weren't modified (implies pre-existing data/gaming)
        feedback_parts.append("FAIL: Data found but no files modified during task (Anti-Gaming Trigger)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. VLM Verification (50 points max)
    # Using trajectory frames to prove workflow
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    prompt = """
    Analyze these screenshots of a user using Copper Point of Sale software on Windows.
    
    I am looking for evidence that the user added new suppliers/vendors.
    
    Check for:
    1. Navigation to a 'Suppliers', 'Vendors', or 'Address Book' list.
    2. A data entry form showing 'Pacific Coast Distributors' or 'Heartland Wholesale Supply'.
    3. The final state showing these names in a list.
    
    Return JSON:
    {
        "supplier_list_visible": boolean,
        "data_entry_seen": boolean,
        "correct_names_seen": boolean,
        "confidence": 0-10
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=prompt)
    
    vlm_score = 0
    if vlm_result and isinstance(vlm_result, dict):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('supplier_list_visible', False):
            vlm_score += 15
            feedback_parts.append("VLM: Supplier list navigation verified (+15)")
        if parsed.get('data_entry_seen', False):
            vlm_score += 15
            feedback_parts.append("VLM: Data entry workflow verified (+15)")
        if parsed.get('correct_names_seen', False):
            vlm_score += 20
            feedback_parts.append("VLM: Supplier names visible in UI (+20)")
    
    score += vlm_score

    # Final tally
    passed = score >= 60 and s1_found and s2_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }