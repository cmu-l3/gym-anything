#!/usr/bin/env python3
"""Verifier for inner_solar_system_diagram task.

Hybrid Verification:
1. Programmatic: Checks flipchart file content for labels, shapes, and properties.
2. VLM: Visual check for spatial arrangement and color.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def build_solar_system_prompt():
    return """Examine this screenshot of a solar system diagram in ActivInspire.
    
    Task: Verify the scientific diagram of the inner solar system.
    
    Check for:
    1. **The Sun**: Is there a large yellow circle on the left?
    2. **Planets**: Are there 4 smaller circles to the right of the Sun?
    3. **Order**: Do they appear in a linear sequence (Sun -> Mercury -> Venus -> Earth -> Mars)?
    4. **AU Marker**: Is there a line indicating distance between Sun and Earth?
    
    Respond in JSON:
    {
        "sun_visible": true/false,
        "sun_is_yellow": true/false,
        "planets_visible": true/false,
        "au_marker_visible": true/false,
        "layout_correct": true/false,
        "confidence": "low"/"medium"/"high"
    }
    """

def verify_solar_system_diagram(traj, env_info, task_info):
    """
    Verify the Inner Solar System Diagram task.
    
    Scoring Breakdown (100 pts):
    - File Valid & Created: 10 pts
    - Content (Programmatic): 60 pts
      - Sun Label: 10
      - Planet Labels: 20
      - AU Label: 10
      - Shape Count >= 5: 10
      - Fill Detected: 5
      - Line Detected: 5
    - Visual (VLM): 30 pts
      - Sun is Yellow: 10
      - Layout Correct: 20
    """
    
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy unavailable"}

    # 1. Programmatic Verification
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # File Checks
    if result.get("file_found") and result.get("file_valid"):
        score += 10
        feedback.append("Valid flipchart file created.")
    else:
        return {"passed": False, "score": 0, "feedback": "No valid flipchart file found."}
        
    if not result.get("created_during_task"):
        feedback.append("Warning: File timestamp indicates it wasn't created during this task.")
        # We penalize but don't fail immediately in case of clock skew, relying on other metrics.
    
    # Content Checks
    if result.get("has_sun_label"):
        score += 10
    else:
        feedback.append("Missing 'Sun' label.")
        
    if result.get("has_planet_labels"):
        score += 20
    else:
        feedback.append("Missing one or more planet labels (Mercury, Venus, Earth, Mars).")
        
    if result.get("has_au_label"):
        score += 10
    else:
        feedback.append("Missing '1 AU' label.")
        
    if result.get("shape_count", 0) >= 5:
        score += 10
    else:
        feedback.append(f"Not enough shapes found (Found {result.get('shape_count')}, expected 5+).")
        
    if result.get("has_fill"):
        score += 5
    else:
        feedback.append("No filled shapes detected (Sun should be filled).")
        
    if result.get("has_line"):
        score += 5
    else:
        feedback.append("No line/connector detected for AU marker.")

    # 2. VLM Verification
    vlm_score = 0
    if query_vlm:
        # Get final screenshot
        from gym_anything.vlm import get_final_screenshot
        final_img = get_final_screenshot(traj)
        
        if final_img:
            vlm_res = query_vlm(prompt=build_solar_system_prompt(), image=final_img)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                
                if parsed.get("sun_is_yellow"):
                    vlm_score += 10
                    feedback.append("Visual: Sun is yellow.")
                else:
                    feedback.append("Visual: Sun does not appear yellow.")
                    
                if parsed.get("layout_correct"):
                    vlm_score += 20
                    feedback.append("Visual: Layout looks correct.")
                elif parsed.get("planets_visible"):
                    vlm_score += 10 # Partial credit
                    feedback.append("Visual: Planets visible but layout imperfect.")
            else:
                feedback.append("VLM verification failed to run.")
        else:
            feedback.append("No screenshot available for visual verification.")
    
    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }