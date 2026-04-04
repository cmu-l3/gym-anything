#!/usr/bin/env python3
"""
Verifier for add_document_category task in LibreHealth EHR.

Verification Criteria:
1. Database Verification (Primary):
   - Check if category "Telehealth Consent" exists.
   - Verify it is a child of "Categories" (correct parent).
   - Check nested set values (lft/rght) to ensure application logic was used.
2. Anti-Gaming:
   - Verify total category count increased.
3. VLM Verification (Secondary):
   - Check trajectory to ensure user navigated to Document Categories UI.
"""

import json
import tempfile
import os
import logging
import sys

# Add parent directory to path to import vlm_utils if needed
# (Assuming gym_anything structure)
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames
except ImportError:
    # Fallback/Mock for standalone testing
    def query_vlm(prompt, images): return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n): return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_document_category(traj, env_info, task_info):
    """
    Verifies that the document category was correctly created.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('category_name', 'Telehealth Consent')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Evaluate Database State
    cat_details = result.get('category_details', {})
    found = result.get('category_found', False)
    
    # CRITERION 1: Category exists (50 points)
    if found and cat_details.get('name') == expected_name:
        score += 50
        feedback_parts.append(f"Category '{expected_name}' created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": f"Category '{expected_name}' not found in database."}

    # CRITERION 2: Correct Parent (20 points)
    # Parent should be 'Categories' (root) or have a valid ID > 0
    parent_id = int(cat_details.get('parent_id', 0))
    parent_name = cat_details.get('parent_name', '')
    
    if parent_id > 0 and ('Categories' in parent_name or parent_id == 1):
        score += 20
        feedback_parts.append("Category placed correctly under 'Categories'.")
    elif parent_id > 0:
        score += 10 # Partial credit for being somewhere in the tree
        feedback_parts.append(f"Category created but under wrong parent: '{parent_name}'.")
    else:
        feedback_parts.append("Category is an orphan (invalid parent).")

    # CRITERION 3: Database Integrity / UI Logic Check (15 points)
    # LibreHealth uses nested set model. lft and rght must be > 0 and valid.
    # Raw SQL inserts usually fail to set these complex values.
    lft = int(cat_details.get('lft', 0))
    rght = int(cat_details.get('rght', 0))
    
    if lft > 0 and rght > lft:
        score += 15
        feedback_parts.append("Database integrity check passed (valid nested set values).")
    else:
        feedback_parts.append("Database integrity check failed (invalid tree structure).")

    # CRITERION 4: Anti-Gaming / Count Check (15 points)
    # Ensure the count actually increased
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    
    if current_count > initial_count:
        score += 15
        feedback_parts.append("New record confirmed by count increase.")
    else:
        feedback_parts.append("Warning: Category count did not increase (did you overwrite an existing one?).")

    # Optional: VLM Verification for workflow robustness (Bonus/Tie-breaker logic)
    # If we are borderline passing, check VLM
    if score >= 50:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                vlm_prompt = "Does this screenshot show a document category management interface or a tree view of categories?"
                vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
                if vlm_res.get('success') and vlm_res.get('parsed', {}).get('is_category_interface', False):
                    feedback_parts.append("Visual confirmation of category interface.")
        except Exception:
            pass # VLM failure shouldn't fail the task if DB is correct

    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }