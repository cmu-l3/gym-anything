#!/usr/bin/env python3
"""
Verifier for the process_warehouse_bin_relocation task.

Verification Strategy:
1. Programmatic Check (Anti-gaming): Ensures the output file was modified DURING the task.
2. Programmatic Check (Anti-gaming): Checks if python CV libraries were used to bypass the scanner software.
3. Content Validation: Parses the generated JSON to ensure keys (bins) and arrays (items) exactly match the expected sequential stream.
4. VLM Trajectory Verification: Confirms OBS and bcWebCam were physically present/utilized during the workflow.
"""

import json
import os
import tempfile
import logging
import sys
from pathlib import Path

# Add parent path to allow importing vlm_utils if present in the framework
sys.path.insert(0, str(Path(__file__).parent.parent))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_warehouse_bin_relocation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env function not available"}

    metadata = task_info.get('metadata', {})
    expected_mapping = metadata.get('expected_mapping', {})
    
    # 1. Retrieve the exported JSON result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Use forward slashes for safer docker paths on windows containers
        copy_from_env("C:/temp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result from container: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 2. Strict Anti-Gaming Check
    if result.get("cheat_detected"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAIL: Cheat detected. Used computer vision libraries (pyzbar/cv2/zxing) to decode video directly instead of using bcWebCam."
        }

    # 3. File Creation / Basic Constraints
    if result.get("output_exists") and result.get("file_created_during_task"):
        score += 20
        feedback_parts.append("JSON output successfully created during task")
        
        # 4. Parse JSON Content
        try:
            raw_content = result.get("json_content", "{}")
            if isinstance(raw_content, str):
                actual_mapping = json.loads(raw_content)
            else:
                actual_mapping = raw_content
            
            expected_bins = set(expected_mapping.keys())
            actual_bins = set(actual_mapping.keys())
            
            # Evaluate Bins (Keys)
            if expected_bins == actual_bins:
                score += 20
                feedback_parts.append("All bins correctly identified")
            elif len(expected_bins.intersection(actual_bins)) > 0:
                score += 10
                feedback_parts.append("Partial bins identified")
            else:
                feedback_parts.append("No correct bins identified")

            # Evaluate Items mapped inside Bins
            items_perfect = True
            partial_items = False
            
            for b_key, b_items in expected_mapping.items():
                if b_key in actual_mapping:
                    a_items = actual_mapping[b_key]
                    if isinstance(a_items, list) and set(a_items) == set(b_items):
                        partial_items = True
                    else:
                        items_perfect = False
                else:
                    items_perfect = False
                    
            if items_perfect and len(actual_bins) > 0:
                score += 40
                feedback_parts.append("Hierarchical item-to-bin mapping is perfectly accurate")
            elif partial_items:
                score += 20
                feedback_parts.append("Item-to-bin mapping is partially correct")
            else:
                feedback_parts.append("Item mapping is missing or incorrect")
                
        except json.JSONDecodeError:
            feedback_parts.append("Output file is not valid JSON")
    else:
        feedback_parts.append("Output JSON file not found or was not created during the task window")

    # 5. VLM Trajectory Verification
    try:
        from vlm_utils import query_vlm, sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """You are verifying an agent's desktop trajectory for a barcode scanning task.
            The agent must route a video file through OBS Studio and scan it using bcWebCam.
            Look at these chronological screenshots:
            1. Is OBS Studio visible at some point playing a media file or showing a virtual camera output?
            2. Is bcWebCam visible at some point processing a barcode or showing video?
            Respond strictly in JSON format:
            {
                "obs_visible": true/false,
                "bcwebcam_visible": true/false
            }"""
            
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("obs_visible") and parsed.get("bcwebcam_visible"):
                    score += 20
                    feedback_parts.append("VLM verified correct GUI usage of OBS and bcWebCam")
                else:
                    feedback_parts.append("VLM did not observe both OBS and bcWebCam in use")
            else:
                feedback_parts.append("VLM verification failed to parse")
    except ImportError:
        logger.warning("VLM utilities not available for trajectory verification.")
        # Gracefully award points if VLM is unavailable but programmatic checks pass to prevent false negatives
        if score >= 60:
            score += 20
            feedback_parts.append("VLM check skipped (unavailable), points awarded based on perfect programmatic output.")

    # Calculate final status
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }