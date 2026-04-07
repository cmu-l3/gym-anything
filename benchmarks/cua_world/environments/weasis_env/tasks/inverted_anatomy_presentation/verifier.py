#!/usr/bin/env python3
"""Verifier for inverted_anatomy_presentation task"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inverted_anatomy_presentation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # 1. Exported JPEG Exists (10 pts)
    image_exists = result.get('image_exists', False)
    image_created = result.get('image_created_during_task', False)
    image_size = result.get('image_size_bytes', 0)
    
    # Must exist, be created after start, and have non-trivial size
    if image_exists and image_created and image_size > 5000:
        score += 10
        feedback_parts.append("Exported JPEG exists and is valid")
    elif image_exists:
        feedback_parts.append("Exported JPEG exists but is invalid size or pre-existing")
    else:
        feedback_parts.append("Exported JPEG not found")

    # 2. Measurement Report Valid (20 pts)
    text_exists = result.get('text_exists', False)
    text_created = result.get('text_created_during_task', False)
    text_content = result.get('text_content', '')
    
    text_valid = False
    if text_exists and text_created:
        # Check for format: 'Measured Length: <value> <unit>'
        match = re.search(r'Measured Length:\s*\d+(\.\d+)?\s+[a-zA-Z]+', text_content, re.IGNORECASE)
        if match:
            text_valid = True
            score += 20
            feedback_parts.append("Measurement text file correctly formatted")
        else:
            feedback_parts.append(f"Measurement text format incorrect: {text_content[:30]}...")
    else:
        feedback_parts.append("Measurement text file not found or pre-existing")

    # 3. VLM Verification (70 pts) - Uses trajectory frames to verify UI progression & final visual state
    try:
        from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
        
        frames = sample_trajectory_frames(traj, n=3)
        final_screenshot = get_final_screenshot(traj)
        
        prompt = """You are verifying an agent's completion of a medical imaging UI task in Weasis.
        
        The agent was instructed to:
        1. Open a DICOM image.
        2. Invert the image contrast (so the background is white/light and dense structures are dark).
        3. Draw a line measurement across a structure.
        
        Look at the provided trajectory frames and the final screenshot.
        
        1. "image_inverted": In the final stages, is the medical image displayed with a predominantly white or very light background indicating an inverted/negative contrast LUT? 
        2. "measurement_visible": Is there a line measurement annotation visible on the medical image?
        3. "workflow_observed": Do the trajectory frames show the agent interacting with the Weasis interface to perform these actions?
        
        Respond ONLY with a valid JSON object matching this schema:
        {
            "image_inverted": true/false,
            "measurement_visible": true/false,
            "workflow_observed": true/false,
            "reasoning": "brief explanation"
        }
        """
        
        # Call VLM with our sampled trajectory images
        vlm_response = query_vlm(images=frames + [final_screenshot], prompt=prompt)
        
        parsed = {}
        if isinstance(vlm_response, dict):
            parsed = vlm_response.get("parsed", vlm_response)
        elif isinstance(vlm_response, str):
            try:
                # Handle possible markdown backticks from VLM
                clean_resp = vlm_response.strip()
                if clean_resp.startswith("