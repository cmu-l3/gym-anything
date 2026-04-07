#!/usr/bin/env python3
"""
Verifier for edit_requirement_description task.

Verifies:
1. SRS.json was modified after task start.
2. Target requirement (SRS-5) description contains the 3 required acceptance criteria strings.
3. Original description content is preserved (append, not replace).
4. VLM verifies UI interaction workflow.
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _strip_html(text):
    """Remove HTML tags from text."""
    if not text: return ""
    return re.sub(r'<[^>]+>', '', str(text)).strip()

def _find_req_by_id(items, target_id):
    """Recursively find requirement by ID."""
    for item in items:
        if str(item.get('id', '')) == str(target_id):
            return item
        if 'children' in item:
            found = _find_req_by_id(item['children'], target_id)
            if found: return found
    return None

def verify_edit_requirement_description(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Metadata & Result
    metadata = task_info.get('metadata', {})
    required_strings = metadata.get('required_strings', [])
    
    # Load task result
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception:
            pass
        finally:
            os.unlink(f.name)

    # Load task metadata (target ID)
    task_meta = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_metadata.json", f.name)
            f.seek(0)
            task_meta = json.load(f)
        except Exception:
            pass
        finally:
            os.unlink(f.name)

    target_id = task_meta.get("target_id", "5")
    srs_path = task_result.get("file_path", "")

    score = 0
    feedback_parts = []
    
    # =========================================================
    # CRITERION 1: File Modification (10 pts)
    # =========================================================
    if task_result.get("file_modified_during_task"):
        score += 10
        feedback_parts.append("Document saved")
    else:
        feedback_parts.append("Document NOT saved/modified")

    # =========================================================
    # CRITERION 2: Content Verification (60 pts)
    # =========================================================
    content_valid = False
    
    # Fetch current SRS.json
    srs_data = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        try:
            copy_from_env(srs_path, f.name)
            f.seek(0)
            srs_data = json.load(f)
        except Exception as e:
            feedback_parts.append(f"Failed to read SRS.json: {e}")
        finally:
            os.unlink(f.name)

    # Fetch initial SRS.json (for diff checking)
    srs_initial = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        try:
            copy_from_env("/tmp/srs_initial.json", f.name)
            f.seek(0)
            srs_initial = json.load(f)
        except Exception:
            pass
        finally:
            os.unlink(f.name)

    target_req = _find_req_by_id(srs_data.get('data', []), target_id)
    initial_req = _find_req_by_id(srs_initial.get('data', []), target_id)

    if target_req:
        desc = _strip_html(target_req.get('description', '') or target_req.get('text', ''))
        
        # Check for required strings (15 pts each = 45 pts)
        matches = 0
        for s in required_strings:
            if s.lower() in desc.lower():
                matches += 1
        
        score += (matches * 15)
        feedback_parts.append(f"Content matches: {matches}/{len(required_strings)}")

        # Check preservation of original text (15 pts)
        if initial_req:
            initial_desc = _strip_html(initial_req.get('description', '') or initial_req.get('text', ''))
            # Simple check: is the initial text roughly a substring of the new text?
            # We take a significant chunk to be safe against minor formatting changes
            check_chunk = initial_desc[:50] if len(initial_desc) > 50 else initial_desc
            if check_chunk in desc:
                score += 15
                feedback_parts.append("Original text preserved")
            else:
                feedback_parts.append("Original text seemingly replaced")
    else:
        feedback_parts.append(f"Requirement SRS-{target_id} not found in file")

    # =========================================================
    # CRITERION 3: VLM Verification (30 pts)
    # =========================================================
    frames = sample_trajectory_frames(traj, n=5)
    final = get_final_screenshot(traj)
    images = frames + ([final] if final else [])
    
    vlm_prompt = f"Does the user interact with the requirement table in ReqView? Do they edit requirement SRS-{target_id} and add text about acceptance criteria? Is the final result saved?"
    
    vlm_result = query_vlm(
        images=images,
        prompt=vlm_prompt
    )
    
    vlm_score = 0
    if vlm_result.get("success"):
        # Simple heuristic based on positive sentiment in analysis
        analysis = vlm_result.get("analysis", "").lower()
        if "yes" in analysis or "edit" in analysis:
            vlm_score = 30
    
    score += vlm_score
    feedback_parts.append(f"VLM Score: {vlm_score}")

    # Pass logic
    passed = score >= 60 and matches >= 2
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }