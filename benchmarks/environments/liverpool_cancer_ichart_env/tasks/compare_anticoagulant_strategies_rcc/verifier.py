#!/usr/bin/env python3
"""
Verifier for compare_anticoagulant_strategies_rcc@1
"""

import json
import logging
import os
import tempfile
import re
from typing import Dict, Any

# Import VLM utils from framework
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Mock for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(prompt, images): return {"success": False}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_anticoagulant_matrix(traj, env_info, task_info):
    """
    Verifies the 2x2 anticoagulant interaction matrix task.
    
    Criteria:
    1. Output file exists (10 pts)
    2. File contains all 4 required pairs (Sunitinib/Pazopanib x Warfarin/Apixaban) (40 pts)
    3. File contains valid traffic light colors for each pair (30 pts)
    4. VLM: Trajectory shows navigation to both Sunitinib and Pazopanib pages (20 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    valid_colors = set(metadata.get('valid_colors', ["red", "orange", "yellow", "green", "grey", "gray"]))

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence
    if not result_data.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file /sdcard/rcc_anticoagulant_matrix.txt not found."}
    
    score += 10
    feedback_parts.append("File created")
    
    content = result_data.get("file_content", "")
    content_lower = content.lower()
    
    # 3. Check Content Completeness (40 pts)
    # We look for the drugs. Note: Order doesn't matter, but pairs matter.
    # We'll use regex to find lines like "Drug1 + Drug2: Color"
    
    pairs_found = 0
    pairs_to_find = [
        ("sunitinib", "warfarin"),
        ("sunitinib", "apixaban"),
        ("pazopanib", "warfarin"),
        ("pazopanib", "apixaban")
    ]
    
    found_colors = {}
    
    for d1, d2 in pairs_to_find:
        # Regex to find: "sunitinib" ... "warfarin" ... [color]
        # or "warfarin" ... "sunitinib" (though instructions gave specific format)
        # We'll be slightly lenient on format, but strict on presence.
        
        # Look for line containing both drugs
        pattern = re.compile(f".*{d1}.*{d2}.*", re.IGNORECASE)
        match = pattern.search(content)
        
        if match:
            pairs_found += 1
            # Extract color
            line = match.group(0).lower()
            color_found = None
            for color in valid_colors:
                if color in line:
                    color_found = color
                    break
            
            if color_found:
                found_colors[f"{d1}+{d2}"] = color_found
        else:
            feedback_parts.append(f"Missing pair: {d1} + {d2}")

    # Score for pairs found (10 pts each)
    score += (pairs_found * 10)
    
    # 4. Check Valid Colors (30 pts)
    # We expect 4 valid colors found.
    # 7.5 pts per valid color entry
    valid_color_count = len(found_colors)
    score += (valid_color_count * 7.5)
    
    if valid_color_count < 4:
        feedback_parts.append(f"Only {valid_color_count}/4 pairs had valid traffic light colors.")
    else:
        feedback_parts.append("All pairs have valid colors.")

    # 5. VLM Verification (20 pts)
    # Did the agent actually look up the drugs?
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_prompt = """
    You are verifying an agent's workflow in the Liverpool Cancer iChart app.
    The task required looking up 'Sunitinib' and 'Pazopanib' and checking 'Anticoagulants'.
    
    Look at these screenshots.
    1. Do you see the text 'Sunitinib' as a selected cancer drug header?
    2. Do you see the text 'Pazopanib' as a selected cancer drug header?
    3. Do you see a list of 'Anticoagulants' or specific drugs like 'Warfarin' or 'Apixaban'?
    
    Return JSON:
    {
        "saw_sunitinib": true/false,
        "saw_pazopanib": true/false,
        "saw_anticoagulants": true/false
    }
    """
    
    vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
    parsed = vlm_result.get("parsed", {})
    
    vlm_score = 0
    if parsed.get("saw_sunitinib"): vlm_score += 7
    if parsed.get("saw_pazopanib"): vlm_score += 7
    if parsed.get("saw_anticoagulants"): vlm_score += 6
    
    score += vlm_score
    
    if vlm_score < 20:
        feedback_parts.append(f"VLM missing steps: Suni={parsed.get('saw_sunitinib')}, Pazo={parsed.get('saw_pazopanib')}")
    else:
        feedback_parts.append("VLM verified navigation.")

    # Final Calculation
    passed = score >= 70 and pairs_found == 4
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }