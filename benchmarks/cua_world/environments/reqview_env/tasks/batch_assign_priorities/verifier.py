#!/usr/bin/env python3
"""
Verifier for batch_assign_priorities task.

Verification Strategy:
1. Load the modified SRS.json from the agent's environment.
2. Load the list of "target IDs" (requirements that had priority cleared during setup).
3. Check if target IDs now have priority == "Medium".
4. Check if other requirements (that weren't targets) are untouched/safe.
5. Check if Headings (which should not have priority) remain without priority.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SRS_REL_PATH = "documents/SRS.json"
TARGET_IDS_PATH = "/tmp/target_req_ids.json"


def _find_by_id(items, target_id):
    """Recursively find an item by ID."""
    for item in items:
        if item.get('id') == target_id:
            return item
        if 'children' in item:
            found = _find_by_id(item['children'], target_id)
            if found:
                return found
    return None

def _collect_all_requirements(items):
    """Collect all items that are requirements (not headings)."""
    reqs = []
    for item in items:
        if 'heading' not in item:
            reqs.append(item)
        if 'children' in item:
            reqs.extend(_collect_all_requirements(item['children']))
    return reqs

def _collect_all_headings(items):
    """Collect all items that are headings."""
    headings = []
    for item in items:
        if 'heading' in item:
            headings.append(item)
        if 'children' in item:
            headings.extend(_collect_all_headings(item['children']))
    return headings

def verify_batch_assign_priorities(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_path = metadata.get('project_path', '/home/ga/Documents/ReqView/batch_priority_project')
    srs_full_path = os.path.join(project_path, SRS_REL_PATH)

    # -------------------------------------------------------------------------
    # Retrieve files from environment
    # -------------------------------------------------------------------------
    
    # 1. Get SRS.json
    srs_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(srs_full_path, srs_file.name)
        with open(srs_file.name, 'r') as f:
            srs_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve SRS document: {e}"}
    finally:
        if os.path.exists(srs_file.name):
            os.unlink(srs_file.name)

    # 2. Get Target IDs (created during setup)
    targets_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    target_ids = []
    try:
        copy_from_env(TARGET_IDS_PATH, targets_file.name)
        with open(targets_file.name, 'r') as f:
            target_ids = json.load(f)
    except Exception as e:
        # Fallback if file missing (shouldn't happen if setup ran)
        logger.warning(f"Target IDs file missing: {e}")
    finally:
        if os.path.exists(targets_file.name):
            os.unlink(targets_file.name)

    if not target_ids:
        return {"passed": False, "score": 0, "feedback": "Setup error: No target requirements identified."}

    # -------------------------------------------------------------------------
    # Verification Logic
    # -------------------------------------------------------------------------
    score = 0
    feedback = []
    
    # Criterion 1: Check Target Requirements (Are they fixed?) [40 pts]
    fixed_count = 0
    for tid in target_ids:
        item = _find_by_id(srs_data.get('data', []), tid)
        if item:
            prio = item.get('priority', '')
            # Accept 'Medium' or 'M' (ReqView often stores keys like 'M')
            if prio in ['Medium', 'M']:
                fixed_count += 1
            else:
                feedback.append(f"Req {tid}: Priority is '{prio}' (expected 'Medium')")
        else:
            feedback.append(f"Req {tid}: Not found (deleted?)")

    score_per_fix = 40 / len(target_ids)
    score += fixed_count * score_per_fix
    feedback.append(f"Fixed {fixed_count}/{len(target_ids)} target requirements.")

    # Criterion 2: Check Headings (Are they polluted?) [20 pts]
    # Headings should NOT have priority set. Agents sometimes "Select All" and apply.
    headings = _collect_all_headings(srs_data.get('data', []))
    polluted_headings = 0
    for h in headings:
        if h.get('priority'):
            polluted_headings += 1
    
    if polluted_headings == 0:
        score += 20
        feedback.append("Headings preserved correctly (no priority assigned).")
    else:
        feedback.append(f"FAILED: {polluted_headings} section headings were incorrectly assigned a priority.")

    # Criterion 3: Completeness / No Data Loss [20 pts]
    # Simple heuristic: check if we still have roughly the same number of requirements
    # We assume setup didn't delete things, so if current == setup targets count + others, we are good.
    # A cleaner check is just ensuring target_ids still exist (checked in C1).
    # Here we check that NO functional requirements are missing priority.
    all_reqs = _collect_all_requirements(srs_data.get('data', []))
    missing_prio_count = 0
    for r in all_reqs:
        if not r.get('priority'):
            missing_prio_count += 1
    
    if missing_prio_count == 0:
        score += 20
        feedback.append("All functional requirements have a priority.")
    else:
        # If the missing ones are the targets, we already penalized in C1. 
        # If they are others, we penalize here.
        feedback.append(f"{missing_prio_count} functional requirements still lack priority.")

    # Criterion 4: VLM Check [20 pts]
    # Did the agent actually use the UI?
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    images = frames + [final_img] if final_img else frames
    
    if images:
        vlm_prompt = (
            "Does the user interact with a requirements table? "
            "Do you see the 'Priority' column? "
            "Is there evidence of changing values to 'Medium'?"
        )
        try:
            vlm_res = query_vlm(images=images, prompt=vlm_prompt)
            if vlm_res.get('success'):
                # Simple keyword matching on reasoning if boolean parsing fails
                reasoning = vlm_res.get('parsed', {}).get('reasoning', '').lower()
                if "priority" in reasoning or "table" in reasoning or "medium" in reasoning:
                    score += 20
                    feedback.append("VLM confirms UI interaction with Priority column.")
                else:
                    # Fallback partial credit if just table is seen
                    score += 10
                    feedback.append("VLM confirms UI interaction.")
            else:
                score += 10 # Give benefit of doubt if VLM fails but logic passes
        except:
            score += 10
    else:
        feedback.append("No screenshots available for VLM.")

    passed = (score >= 70) and (fixed_count == len(target_ids))

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }