#!/usr/bin/env python3
"""
Verifier for generate_iec_turbulence task.

Verification Strategy:
1. File Verification (60 pts):
   - Binary output file exists.
   - File was created during the task window.
   - File size is consistent with requested grid/time settings (~14MB).

2. VLM Verification (40 pts):
   - Uses trajectory frames to verify the agent used the correct module.
   - Checks if specific parameters (Velocity=18, Seed=9999) were visible.
   - Confirms the generation process occurred (visualization appeared).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_iec_turbulence(traj, env_info, task_info):
    """
    Verify that the turbulent wind field was generated with correct parameters.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_size_bytes = metadata.get('min_size_bytes', 10000000)  # ~10MB
    
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
    feedback_parts = []

    # 2. File-Based Verification (60 pts total)
    
    # Criterion 1: File Exists (20 pts)
    if result.get('output_exists'):
        score += 20
        feedback_parts.append("Binary wind field file created")
    else:
        feedback_parts.append("Output file not found")
        # Critical failure if file is missing
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Anti-Gaming Timestamp Check (20 pts)
    if result.get('file_created_during_task'):
        score += 20
        feedback_parts.append("File created during task session")
    else:
        feedback_parts.append("File timestamp indicates pre-existing file or creation failure")

    # Criterion 3: File Size Check (20 pts)
    # 32x32x1200 points * 3 components * 4 bytes approx 14.7 MB
    size = result.get('output_size_bytes', 0)
    if size > min_size_bytes:
        score += 20
        feedback_parts.append(f"File size valid ({size/1024/1024:.2f} MB)")
    elif size > 0:
        score += 5
        feedback_parts.append(f"File too small ({size} bytes) - likely incomplete")
    else:
        feedback_parts.append("File is empty")

    # 3. VLM Verification (40 pts total)
    # We use trajectory frames to verify parameters that are inside the binary file
    
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=6)
        
        prompt = """
        You are verifying a user using QBlade to generate a turbulent wind field.
        Look at the sequence of images and check for these specific steps:
        
        1. MODULE: Did the user navigate to the 'Turbulent Windfield Generator' module? (Look for grid settings, spectral model options).
        2. PARAMETERS: Can you see the 'Mean Velocity' set to 18 (or near 18) and 'Turbulence Intensity' set to 14?
        3. SEED: Can you see the 'Random Seed' set to 9999?
        4. GENERATION: Did the user click Generate? Is there a colored contour plot/wind field visualization visible in the later frames?
        
        Respond in JSON:
        {
            "correct_module_used": true/false,
            "velocity_18_visible": true/false,
            "seed_9999_visible": true/false,
            "visualization_created": true/false
        }
        """
        
        try:
            vlm_result = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_result.get('parsed', {})
            
            if parsed.get('correct_module_used'):
                score += 10
                feedback_parts.append("Correct module used")
            
            # These are critical for ensuring the *right* file was made
            if parsed.get('velocity_18_visible') and parsed.get('seed_9999_visible'):
                score += 20
                feedback_parts.append("Correct parameters (Speed=18, Seed=9999) verified visually")
            elif parsed.get('velocity_18_visible') or parsed.get('seed_9999_visible'):
                score += 10
                feedback_parts.append("Some parameters verified visually")
                
            if parsed.get('visualization_created'):
                score += 10
                feedback_parts.append("Generation process verified visually")
                
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append("Visual verification skipped due to error")
            # Grant partial credit if file is perfect to avoid unfair fail
            if score >= 60:
                score += 20 

    # 4. Final Scoring
    passed = score >= 65 and result.get('output_exists') and result.get('file_created_during_task')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }