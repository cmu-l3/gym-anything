#!/usr/bin/env python3
"""
Verifier for Physics Free Body Diagrams task.

Hybrid Verification:
1. Programmatic: Checks file structure, text labels, and shape primitives.
2. VLM: visually checks the "Object on Ramp" page for correct physics representation 
   (tilted box, vector directions).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def build_fbd_prompt():
    return """Examine this screenshot of a physics lesson in ActivInspire.
    
Task: Verify the "Object on Ramp" Free Body Diagram.

Look for a page showing a TRIANGLE (ramp) and a RECTANGLE (box/object) on the slanted side.

Check these specific details:
1. ROTATION: Is the rectangle ROTATED so its bottom is flush/parallel with the ramp surface? (It should NOT be horizontal balancing on a corner).
2. GRAVITY VECTOR (Fg): Is there an arrow pointing STRAIGHT DOWN (vertical on screen), regardless of the ramp angle?
3. NORMAL VECTOR (Fn): Is there an arrow pointing PERPENDICULAR to the ramp surface (tilted relative to screen)?
4. LABELS: Are the vectors labeled (Fg, Fn, Ff)?

Respond in JSON format:
{
    "ramp_page_visible": true/false,
    "box_is_rotated_to_match_ramp": true/false,
    "gravity_vector_is_vertical": true/false,
    "normal_vector_is_perpendicular": true/false,
    "labels_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "what you see"
}
"""

def verify_with_vlm(traj, query_vlm):
    from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames
    
    # Use final screenshot and last few frames to find the ramp page
    # The agent might end on a different page, so we check trajectory too if needed
    images = [get_final_screenshot(traj)]
    
    # Also add a few late trajectory frames in case they navigated away
    frames = sample_trajectory_frames(traj, n=3)
    if frames:
        images.extend(frames)
        
    prompt = build_fbd_prompt()
    
    # Query VLM on the final screenshot first
    best_result = None
    
    for img in images:
        if not img or not os.path.exists(img):
            continue
            
        result = query_vlm(prompt=prompt, image=img)
        if result.get("success"):
            parsed = result.get("parsed", {})
            if parsed.get("ramp_page_visible"):
                best_result = parsed
                break
    
    if best_result:
        return best_result
    
    # If no success, return the result from final screenshot even if false
    return {"ramp_page_visible": False, "reasoning": "Could not identify ramp page in screenshots"}

def verify_physics_fbd(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load programmatic result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        copy_from_env('/tmp/task_result.json', tmp_path)
        with open(tmp_path, 'r') as f:
            res = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []

    # 1. File & Structure (30 pts)
    if res.get("file_found") and res.get("file_valid"):
        score += 15
        feedback.append("File created successfully.")
        
        if res.get("created_during_task"):
            score += 5
            feedback.append("File created during task.")
            
        pc = res.get("page_count", 0)
        if pc >= 3:
            score += 10
            feedback.append(f"Page count correct ({pc}).")
        else:
            feedback.append(f"Page count insufficient ({pc}/3).")
    else:
        return {"passed": False, "score": 0, "feedback": "No valid flipchart file found."}

    # 2. Text Content (30 pts)
    # 8 keywords: Title, Newton, Rest, Ramp, Fg, Fn, Ff, Fnet
    txt = res.get("text_content", {})
    required_keys = ["title", "newton", "rest", "ramp", "fg", "fn", "ff", "fnet"]
    found_keys = [k for k in required_keys if txt.get(k)]
    
    text_score = (len(found_keys) / len(required_keys)) * 30
    score += text_score
    feedback.append(f"Text content: {len(found_keys)}/8 terms found.")
    
    if not txt.get("fg") or not txt.get("fn"):
        feedback.append("Missing critical force labels (Fg/Fn).")

    # 3. Shape Primitives (10 pts)
    shapes = res.get("shapes", {})
    if shapes.get("triangle"):
        score += 5
        feedback.append("Ramp (Triangle) detected.")
    else:
        feedback.append("Missing Triangle for ramp.")
        
    if shapes.get("rectangle"):
        score += 5
        feedback.append("Box (Rectangle) detected.")

    # 4. Visual/Physics Verification (30 pts)
    if query_vlm:
        vlm_res = verify_with_vlm(traj, query_vlm)
        
        if vlm_res.get("ramp_page_visible"):
            score += 5
            feedback.append("Ramp page visually confirmed.")
            
            if vlm_res.get("box_is_rotated_to_match_ramp"):
                score += 10
                feedback.append("Box correctly rotated.")
            else:
                feedback.append("Box not rotated correctly.")
                
            if vlm_res.get("gravity_vector_is_vertical"):
                score += 10
                feedback.append("Gravity vector correct.")
            else:
                feedback.append("Gravity vector direction incorrect.")
                
            if vlm_res.get("labels_visible"):
                score += 5
                feedback.append("Visual labels confirmed.")
        else:
            feedback.append("Could not visually verify ramp page.")
    else:
        feedback.append("Skipping VLM check (not available).")
        # Fallback: check rotation heuristic from XML
        if shapes.get("rotation_detected"):
            score += 15
            feedback.append("Rotation detected in XML (Fallback).")

    return {
        "passed": score >= 70,
        "score": min(100, int(score)),
        "feedback": " ".join(feedback)
    }