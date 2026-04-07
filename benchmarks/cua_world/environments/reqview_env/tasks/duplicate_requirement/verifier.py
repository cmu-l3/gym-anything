#!/usr/bin/env python3
"""
Verifier for duplicate_requirement task.

Criteria:
1. SRS document JSON was modified after task start (10 pts)
2. Requirement count increased by exactly 1 (20 pts)
3. New requirement with exact target description exists (40 pts)
   (Partial credit for fuzzy match)
4. VLM: Visual confirmation of work (30 pts)
   - Checks if ReqView is visible and valid
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_duplicate_requirement(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_desc = metadata.get('target_description', '')
    
    score = 0
    feedback_parts = []
    
    # 1. Load task result from export_result.sh
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            task_result = json.load(open(f.name))
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
        finally:
            if os.path.exists(f.name): os.unlink(f.name)
            
    # 2. Check File Modification (Anti-gaming)
    if task_result.get("srs_modified_during_task", False):
        score += 10
        feedback_parts.append("Project saved successfully")
    else:
        feedback_parts.append("Project NOT saved (file timestamp unchanged)")
        
    # 3. Load SRS JSON to check content
    project_path = task_result.get("project_path", "")
    srs_path = f"{project_path}/documents/SRS.json"
    
    srs_data = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        try:
            copy_from_env(srs_path, f.name)
            srs_data = json.load(open(f.name))
        except Exception as e:
            feedback_parts.append(f"Failed to read SRS.json: {e}")
        finally:
            if os.path.exists(f.name): os.unlink(f.name)
            
    # Helper to count items and find text
    def analyze_srs(items, target_text):
        count = 0
        found_exact = False
        found_fuzzy = False
        
        for item in items:
            count += 1
            # Check description (ReqView stores rich text in 'text' or 'description')
            # Usually 'text' holds the HTML content for requirements
            text = item.get("text", "") or item.get("description", "")
            
            # Simple strip of HTML tags for comparison
            clean_text = text.replace("<p>", "").replace("</p>", "").strip()
            
            if target_text in clean_text:
                found_exact = True
            elif target_text.lower() in clean_text.lower():
                found_fuzzy = True
            elif "role-based access control" in clean_text.lower() and "administrative" in clean_text.lower():
                found_fuzzy = True
                
            if "children" in item:
                c, fe, ff = analyze_srs(item["children"], target_text)
                count += c
                found_exact = found_exact or fe
                found_fuzzy = found_fuzzy or ff
                
        return count, found_exact, found_fuzzy

    final_count, found_exact, found_fuzzy = analyze_srs(srs_data.get("data", []), target_desc)
    initial_count = int(task_result.get("initial_req_count", 0))
    
    # 4. Check Requirement Count
    diff = final_count - initial_count
    if diff == 1:
        score += 20
        feedback_parts.append("Requirement count increased by 1")
    elif diff > 0:
        score += 10
        feedback_parts.append(f"Requirement count increased by {diff} (expected 1)")
    else:
        feedback_parts.append(f"Requirement count did not increase (Initial: {initial_count}, Final: {final_count})")
        
    # 5. Check Content
    if found_exact:
        score += 40
        feedback_parts.append("New requirement has exact description")
    elif found_fuzzy:
        score += 20
        feedback_parts.append("New requirement has partial/fuzzy matching description")
    else:
        feedback_parts.append("Target description text not found in document")
        
    # 6. VLM Verification
    # Check if they actually used the UI correctly
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        images = frames + [final_screen]
        prompt = """
        Review this sequence of interactions with ReqView (Requirements Management Tool).
        The user should have:
        1. Selected a requirement row
        2. Copied and pasted it (duplicate appearing)
        3. Edited the text
        
        Do you see the ReqView interface with a requirements table? 
        Does the final state look like a valid requirements document?
        Are there any error dialogs visible?
        
        Respond JSON: {"valid_interface": bool, "work_visible": bool, "errors": bool}
        """
        
        try:
            vlm_res = query_vlm(images=images, prompt=prompt).get("parsed", {})
            
            if vlm_res.get("valid_interface", False):
                score += 10
            if vlm_res.get("work_visible", False):
                score += 20
            if vlm_res.get("errors", False):
                score -= 10
                feedback_parts.append("Error dialogs detected")
                
            feedback_parts.append("VLM verification complete")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            # Fallback points if VLM fails but programmatic passed
            if score >= 60: score += 10
            
    passed = score >= 60 and found_exact and (diff >= 1)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "initial_count": initial_count,
            "final_count": final_count,
            "text_found": found_exact
        }
    }