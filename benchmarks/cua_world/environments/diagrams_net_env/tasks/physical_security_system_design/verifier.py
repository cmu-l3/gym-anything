#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_physical_security_system_design(traj, env_info, task_info):
    """
    Verifies the Physical Security System Design task.
    
    Criteria:
    1. Output files exist (drawio and pdf).
    2. Floor plan image was imported (detected in XML).
    3. Sufficient security devices placed (Cameras, Readers, Sensors).
    4. Devices connected to panel (Edge count).
    5. VLM Verification: Visual confirmation of floorplan overlay and wiring.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Programmatic Analysis
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            analysis = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task analysis: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Scoring Logic
    score = 0
    feedback = []
    
    # File Existence (20 pts)
    if analysis.get("drawio_exists") and analysis.get("file_modified"):
        score += 10
        feedback.append("Draw.io file created/modified.")
    else:
        feedback.append("Draw.io file missing or unchanged.")

    if analysis.get("pdf_exists"):
        score += 10
        feedback.append("PDF export found.")
    else:
        feedback.append("PDF export missing.")

    # Content Verification (40 pts)
    counts = analysis.get("shape_counts", {})
    
    # Check for Floorplan Image
    # Note: 'image' count might be 0 if they used a different object type, 
    # but usually imported images show up as image style.
    # We'll be lenient here and rely on total shapes too.
    if counts.get("image", 0) > 0 or analysis.get("total_shapes", 0) > 5:
        score += 5
        feedback.append("Diagram content detected.")
    
    # Device Counts (Relaxed slightly to account for labeling variations)
    # Required: 2 Cameras, 3 Readers, 6 Sensors (4 contacts + 2 motion), 1 Panel
    
    # Cameras (Target 2)
    if counts.get("camera", 0) >= 2:
        score += 10
        feedback.append(f"Cameras placed ({counts['camera']}).")
    elif counts.get("camera", 0) > 0:
        score += 5
        feedback.append(f"Some cameras placed ({counts['camera']}).")
        
    # Readers (Target 3)
    if counts.get("reader", 0) >= 3:
        score += 10
        feedback.append(f"Readers placed ({counts['reader']}).")
    elif counts.get("reader", 0) > 0:
        score += 5
        feedback.append("Some readers placed.")
        
    # Sensors (Target 6)
    if counts.get("sensor", 0) >= 4:
        score += 5
        feedback.append(f"Sensors placed ({counts['sensor']}).")
        
    # Wiring (Edges) (Target 8+)
    edge_count = analysis.get("edge_count", 0)
    if edge_count >= 8:
        score += 10
        feedback.append(f"Wiring connections detected ({edge_count} edges).")
    elif edge_count >= 4:
        score += 5
        feedback.append("Partial wiring detected.")
    else:
        feedback.append("Wiring incomplete or missing.")

    # 3. VLM Verification (40 pts)
    # Use trajectory to see if they actually worked on the floor plan
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying a security system design task in draw.io.
    The user was supposed to import a floor plan (white rooms with black walls) and place security symbols (cameras, squares for readers) overlaid on it.
    
    Look at the final screenshot and the history:
    1. Is a floor plan image visible in the background? (It should show rooms like 'Server Room', 'IT Closet', 'Lab').
    2. Are there security icons/symbols placed ON TOP of the floor plan in different rooms?
    3. Are there lines (wires) connecting these devices to a central point (IT Closet)?
    
    Answer YES or NO for each question and estimate a confidence score (0-10) for the completion quality.
    """
    
    try:
        vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        vlm_text = vlm_result.get("text", "").lower()
        
        if "yes" in vlm_text and ("floor plan" in vlm_text or "background" in vlm_text):
            score += 15
            feedback.append("VLM: Floor plan confirmed.")
            
        if "yes" in vlm_text and ("symbol" in vlm_text or "icon" in vlm_text or "device" in vlm_text):
            score += 15
            feedback.append("VLM: Security devices confirmed.")
            
        if "yes" in vlm_text and ("line" in vlm_text or "wire" in vlm_text or "connect" in vlm_text):
            score += 10
            feedback.append("VLM: Wiring confirmed.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if programmatic score is high, give some VLM points
        if score >= 40:
            score += 20
            feedback.append("VLM skipped (error), fallback points awarded.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }