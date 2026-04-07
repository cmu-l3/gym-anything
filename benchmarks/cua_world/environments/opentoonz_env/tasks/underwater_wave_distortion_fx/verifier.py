#!/usr/bin/env python3
"""
Verifier for underwater_wave_distortion_fx task.

Requirements:
1. 24 PNG frames rendered to correct directory.
2. Frames created DURING the task (timestamp check).
3. Visual confirmation of distortion effect (VLM).
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Import VLM utils from framework
try:
    from gym_anything.vlm import query_vlm
except ImportError:
    # Fallback for local testing
    def query_vlm(prompt, image):
        return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_underwater_fx(traj, env_info, task_info):
    """
    Verify the underwater distortion task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Output (30 pts) ---
    file_count = result.get('file_count', 0)
    new_files = result.get('new_files_count', 0)
    
    if file_count >= 24:
        score += 15
        feedback_parts.append(f"Frame count OK ({file_count})")
    elif file_count > 0:
        score += 5
        feedback_parts.append(f"Partial frames ({file_count}/24)")
    else:
        feedback_parts.append("No frames rendered")
        
    # --- Criterion 2: Anti-Gaming Timestamp (20 pts) ---
    if new_files >= 24:
        score += 20
        feedback_parts.append("Files created during task")
    elif new_files > 0:
        score += 10
        feedback_parts.append("Some files created during task")
    else:
        feedback_parts.append("Files are old or missing")

    # --- Criterion 3: Visual Verification (50 pts) ---
    # We need to verify the *Distortion* effect.
    # We pull the sample frame from the container.
    frame_path_in_env = result.get('frame_sample_path', "")
    
    if frame_path_in_env:
        local_frame = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
        try:
            copy_from_env(frame_path_in_env, local_frame)
            
            vlm_prompt = """
            Analyze this animation frame. 
            The goal was to apply an 'underwater' or 'wave' distortion effect to the character.
            
            1. Is there a visible character?
            2. Does the image look distorted, wavy, rippled, or warped (as if underwater)?
            3. Is the image just a solid color or blank? (Fail if yes)
            
            Return JSON:
            {
                "character_visible": true/false,
                "is_distorted": true/false,
                "is_blank": true/false,
                "description": "short description"
            }
            """
            
            vlm_response = query_vlm(prompt=vlm_prompt, image=local_frame)
            
            if vlm_response.get("success"):
                data = vlm_response.get("parsed", {})
                
                if data.get("is_blank", False):
                    score = 0 # Fail immediately for blank
                    feedback_parts.append("Rendered frame is blank")
                elif data.get("is_distorted", False) and data.get("character_visible", False):
                    score += 50
                    feedback_parts.append("VLM confirms underwater distortion effect")
                elif data.get("character_visible", False):
                    score += 10 # Credit for rendering clean char, but missed FX
                    feedback_parts.append("Character visible but NO distortion detected")
                else:
                    feedback_parts.append("VLM could not identify character or effect")
            else:
                feedback_parts.append("VLM verification failed")
                # Fallback: if we have files, give mild credit
                if score >= 35: score += 10 
                
        except Exception as e:
            feedback_parts.append(f"Failed to verify frame image: {e}")
        finally:
            if os.path.exists(local_frame):
                os.unlink(local_frame)
    else:
        feedback_parts.append("No frame sample available for verification")

    # Final Pass Logic
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }