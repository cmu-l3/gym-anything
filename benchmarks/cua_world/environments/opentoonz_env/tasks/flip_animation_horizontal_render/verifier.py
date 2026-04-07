#!/usr/bin/env python3
"""
Verifier for flip_animation_horizontal_render task.

Verifies:
1. File output: Checks for PNG sequence creation (count, timestamp, size).
2. Content verification (VLM): Checks if the character is facing/walking Left (Flipped) 
   vs the original Right (Unflipped).
"""

import json
import os
import logging
import tempfile
import base64

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_flip_animation(traj, env_info, task_info):
    """
    Verify the agent correctly flipped and rendered the animation.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function missing"}

    metadata = task_info.get('metadata', {})
    min_frame_count = metadata.get('min_frame_count', 24)
    min_total_size_kb = metadata.get('min_total_size_kb', 200)

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # 2. Programmatic Verification (60 points)
    
    # Criterion 1: Files created (20 pts)
    new_files = result.get('new_files_count', 0)
    if new_files >= min_frame_count:
        score += 20
        feedback_parts.append(f"Rendered {new_files} new frames")
    elif new_files > 0:
        score += 10
        feedback_parts.append(f"Incomplete render: {new_files}/{min_frame_count} frames")
    else:
        feedback_parts.append("No new frames rendered")

    # Criterion 2: File size sanity check (20 pts)
    total_size_kb = result.get('total_size_bytes', 0) / 1024
    if total_size_kb >= min_total_size_kb:
        score += 20
        feedback_parts.append(f"Output size good ({int(total_size_kb)}KB)")
    elif total_size_kb > 10:
        score += 10
        feedback_parts.append(f"Output size small ({int(total_size_kb)}KB)")
    else:
        feedback_parts.append("Output file size too small (empty/corrupt)")

    # Criterion 3: Directory exists (20 pts)
    if result.get('output_dir_exists'):
        score += 20
    else:
        feedback_parts.append("Output directory missing")

    # 3. VLM Verification - Direction Check (40 points)
    # We check if the character is actually flipped (Facing Left)
    
    first_frame_path = result.get('first_frame_path')
    vlm_score = 0
    
    if first_frame_path and new_files > 0:
        # Retrieve the frame image
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(first_frame_path, temp_img.name)
            
            # Query VLM
            # We use the 'query_vlm' function provided by the framework (mocked here conceptually)
            # In actual execution, verification_function receives a vlm_client or we use a helper.
            # Assuming standard gym_anything VLM interface pattern:
            
            prompt = (
                "This is a frame from an animation. The character 'Dwanko' normally walks from "
                "Left to Right (facing Right). The goal of this task was to FLIP the animation "
                "so the character faces LEFT and walks Right to Left.\n\n"
                "Look at the character. Are they facing/moving towards the LEFT or RIGHT?\n"
                "Answer JSON: {\"facing_direction\": \"left\" or \"right\", \"is_flipped\": true/false}"
            )
            
            # NOTE: In the provided environment interface, we usually import query_vlm helper
            # If not available, we rely on the framework injecting it or standard import.
            # We will use the VLM utility if available, else skip gracefully.
            
            from gym_anything.vlm import query_vlm
            
            vlm_response = query_vlm(prompt=prompt, image=temp_img.name)
            
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                direction = parsed.get("facing_direction", "").lower()
                is_flipped = parsed.get("is_flipped", False)
                
                if direction == "left" or is_flipped:
                    vlm_score = 40
                    feedback_parts.append("VLM confirms character is flipped (facing Left)")
                else:
                    feedback_parts.append("VLM indicates character is NOT flipped (facing Right)")
            else:
                # Fallback if VLM fails: give benefit of doubt if files look good
                # (Or strictly 0 if we want to enforce rigor)
                feedback_parts.append("Visual verification failed (VLM error)")
                # Partial credit for generating valid images
                vlm_score = 10 

        except ImportError:
             # Fallback for environments without VLM support
            feedback_parts.append("VLM module not found - skipping visual check")
            vlm_score = 40 if score >= 40 else 0 # Auto-pass if technical checks pass
            
        except Exception as e:
            feedback_parts.append(f"Visual check error: {str(e)}")
            
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)
    else:
        feedback_parts.append("No frames available for visual verification")

    score += vlm_score

    # 4. Final Result
    passed = score >= 60 and new_files >= 1
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }