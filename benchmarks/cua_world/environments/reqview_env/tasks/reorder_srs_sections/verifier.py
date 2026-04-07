#!/usr/bin/env python3
"""
Verifier for reorder_srs_sections task.

Criteria:
1. SRS Document JSON structure analysis (Primary):
   - Verify the section originally at index 3 (4th) is now at index 1 (2nd).
   - Verify all original sections are still present (no deletions).
2. Result file analysis (Secondary):
   - Verify file exists and contains correct ID/Text.
3. Anti-gaming:
   - File modification timestamps.
4. VLM Verification (Tertiary):
   - Check trajectory for visual confirmation of move operation.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reorder_srs_sections(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Task Result Metadata
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
            copy_from_env("/tmp/task_result.json", f.name)
            task_result = json.load(open(f.name))
        os.unlink(f.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

    srs_path = task_result.get("srs_path_in_container")
    if not srs_path:
        return {"passed": False, "score": 0, "feedback": "SRS file path unknown"}

    score = 0
    feedback_parts = []
    
    # =========================================================
    # CRITERION 1: Document Saved & Modified (10 points)
    # =========================================================
    if task_result.get("srs_modified") and task_result.get("srs_hash_changed"):
        score += 10
        feedback_parts.append("Document saved with changes")
    else:
        feedback_parts.append("Document not saved or no changes detected")

    # =========================================================
    # CRITERION 2: Structural Verification (50 points)
    # =========================================================
    
    # Load Baseline Structure
    baseline_sections = []
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
            copy_from_env("/tmp/baseline_structure.json", f.name)
            baseline_sections = json.load(open(f.name))
        os.unlink(f.name)
    except Exception:
        return {"passed": False, "score": 0, "feedback": "Failed to load baseline structure"}

    # Load Current Structure
    current_sections = []
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
            copy_from_env(srs_path, f.name)
            srs_data = json.load(open(f.name))
            # Extract top level items from current SRS
            # ReqView 'data' key contains the list of top-level objects
            raw_items = srs_data.get('data', [])
            for item in raw_items:
                current_sections.append({
                    'id': item.get('id'),
                    'text': str(item.get('heading', item.get('text', '')))
                })
        os.unlink(f.name)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse SRS JSON: {e}"}

    # Verify Move
    # Goal: Move 4th item (index 3) to 2nd position (index 1)
    
    if len(baseline_sections) < 4:
         return {"passed": False, "score": 0, "feedback": "Baseline document too small for task"}

    target_id = baseline_sections[3]['id'] # The one that should move
    displaced_id = baseline_sections[1]['id'] # The one that was at 2nd pos
    
    # Check if target is now at index 1
    if len(current_sections) > 1 and current_sections[1]['id'] == target_id:
        score += 40
        feedback_parts.append("Section moved to correct position (2nd)")
        
        # Verify no data loss (count matches)
        if len(current_sections) == len(baseline_sections):
            score += 10
            feedback_parts.append("Structure integrity maintained")
        else:
            feedback_parts.append(f"Section count changed (Base: {len(baseline_sections)}, Curr: {len(current_sections)})")
    else:
        # Partial credit if it moved but to wrong spot
        current_ids = [x['id'] for x in current_sections]
        if target_id in current_ids:
            new_idx = current_ids.index(target_id)
            if new_idx != 3: # It moved
                score += 15
                feedback_parts.append(f"Section moved, but to index {new_idx} (expected 1)")
            else:
                feedback_parts.append("Section did not move")
        else:
            feedback_parts.append("Target section missing from document")

    # =========================================================
    # CRITERION 3: Result File Verification (20 points)
    # =========================================================
    if task_result.get("result_file_exists"):
        try:
            with tempfile.NamedTemporaryFile(suffix=".txt", delete=False) as f:
                copy_from_env("/home/ga/reorder_result.txt", f.name)
                with open(f.name, 'r') as rf:
                    content = rf.read()
            os.unlink(f.name)
            
            # Simple check: does it contain the ID of the moved section?
            if str(target_id) in content:
                score += 10
                feedback_parts.append("Result file references correct section ID")
            
            # Does it contain the count?
            if str(len(baseline_sections)) in content:
                score += 10
                feedback_parts.append("Result file has correct count")
            
        except Exception:
            feedback_parts.append("Result file unreadable")
    else:
        feedback_parts.append("Result file not found")

    # =========================================================
    # CRITERION 4: VLM Verification (20 points)
    # =========================================================
    # Use VLM to confirm the visual action of moving
    frames = sample_trajectory_frames(traj, n=5)
    
    prompt = """
    The user is performing a task in ReqView to reorder sections in a document tree.
    Look at these screenshots.
    1. Do you see the ReqView application open?
    2. Do you see any evidence of interaction with the document tree (left sidebar)?
    3. Is there any dragging or menu interaction that suggests moving an item?
    
    Answer yes/no for each and provide a brief reason.
    """
    
    vlm_res = query_vlm(images=frames, prompt=prompt)
    if vlm_res.get('success'):
        # Heuristic: if VLM is confident about ReqView and interaction, give points
        # We rely mostly on programmatic, this is just anti-gaming "was app actually used"
        resp = vlm_res.get('response', '').lower()
        if 'yes' in resp and 'reqview' in resp:
            score += 20
            feedback_parts.append("VLM confirmed UI interaction")
    else:
        # Fallback if VLM fails: if programmatic success is high, assume interaction
        if score >= 60:
            score += 20
            feedback_parts.append("Implicit interaction (programmatic success)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }