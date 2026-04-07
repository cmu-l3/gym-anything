#!/usr/bin/env python3
"""
Verifier for Visual Echo (Timing Offset) Task.

This verifier checks:
1. Did the agent create new PNG files? (Basic execution)
2. Does the output look like a visual echo? (VLM Verification)
   - We use VLM because detecting "transparent overlapping characters" reliably 
     via raw pixel CV without a perfect ground truth mask is error-prone.
     The VLM is excellent at understanding "ghost trail" semantics.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_visual_echo(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifies that the user created a visual echo effect.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    # Define score components
    score = 0
    feedback_parts = []
    
    # Create temp dir for files
    with tempfile.TemporaryDirectory() as tmp_dir:
        result_json_path = os.path.join(tmp_dir, "task_result.json")
        sample_img_path = os.path.join(tmp_dir, "sample_frame.png")
        
        # Retrieve JSON
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load result JSON: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from environment."}

        # Retrieve Sample Image
        has_sample = result_data.get('sample_frame_exists', False)
        if has_sample:
            try:
                copy_from_env("/tmp/sample_frame.png", sample_img_path)
            except Exception as e:
                logger.error(f"Failed to load sample image: {e}")
                has_sample = False

        # --- CRITERION 1: File Output (30 pts) ---
        new_files = result_data.get('new_files_count', 0)
        min_files = task_info.get('metadata', {}).get('min_files', 10)
        
        if new_files >= min_files:
            score += 30
            feedback_parts.append(f"✓ Rendered sequence found ({new_files} frames)")
        elif new_files > 0:
            score += 15
            feedback_parts.append(f"⚠ Rendered partial sequence ({new_files} frames, expected {min_files}+)")
        else:
            feedback_parts.append("✗ No new rendered files found")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

        # --- CRITERION 2: VLM Visual Check (70 pts) ---
        # We rely on VLM to confirm the visual effect (ghost/echo)
        if has_sample and os.path.exists(sample_img_path):
            from gym_anything.vlm import query_vlm  # Import provided by framework
            
            prompt = (
                "Analyze this animation frame. The task was to create a 'visual echo' or 'ghost trail' effect. "
                "Look for the following:\n"
                "1. Are there TWO visible versions of the character (or a main character and a trail)?\n"
                "2. Is one version semi-transparent (ghost-like) or fainter than the other?\n"
                "3. Does it look like a timing offset (the ghost follows the main character)?\n\n"
                "Respond with JSON:\n"
                "{\n"
                "  \"has_two_characters\": boolean,\n"
                "  \"has_transparency\": boolean,\n"
                "  \"looks_like_echo\": boolean,\n"
                "  \"explanation\": string\n"
                "}"
            )
            
            try:
                vlm_response = query_vlm(prompt=prompt, image=sample_img_path)
                
                if vlm_response and vlm_response.get("success"):
                    parsed = vlm_response.get("parsed", {})
                    
                    # Logic: 
                    # - has_two_characters (overlap): 30 pts
                    # - has_transparency: 20 pts
                    # - looks_like_echo: 20 pts
                    
                    if parsed.get("has_two_characters", False):
                        score += 30
                        feedback_parts.append("✓ VLM detected overlapping character/trail")
                    else:
                        feedback_parts.append("✗ VLM did not see a double/echo character")
                        
                    if parsed.get("has_transparency", False):
                        score += 20
                        feedback_parts.append("✓ VLM detected transparency/ghosting")
                    else:
                        feedback_parts.append("✗ VLM did not detect transparency")
                        
                    if parsed.get("looks_like_echo", False):
                        score += 20
                        feedback_parts.append("✓ VLM confirms timing offset/echo effect")
                else:
                    feedback_parts.append("⚠ VLM verification failed to run")
                    # Fallback partial credit if file exists but VLM fails
                    score += 10 
            except Exception as e:
                logger.error(f"VLM error: {e}")
                feedback_parts.append("⚠ VLM error during verification")
        else:
            feedback_parts.append("✗ No sample frame available for visual verification")

    # Final Pass Logic
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }