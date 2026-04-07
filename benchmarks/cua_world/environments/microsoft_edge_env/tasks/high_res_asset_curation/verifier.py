#!/usr/bin/env python3
"""
Verifier for high_res_asset_curation task.

Scoring Criteria:
1. Asset Directory Created (10 pts)
2. Asset 01 Valid (exists, unique, width >= 2500px) (25 pts)
3. Asset 02 Valid (exists, unique, width >= 2500px) (25 pts)
4. Asset 03 Valid (exists, unique, width >= 2500px) (25 pts)
5. Credits Log Created and Populated (15 pts)

Total: 100 points
Pass Threshold: 85 points (Must get at least 3 valid high-res images and create the folder)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_high_res_asset_curation(traj, env_info, task_info):
    """
    Verify that the agent downloaded 3 unique high-resolution images and created a credits log.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check Directory (10 pts)
    if result.get("directory_exists"):
        score += 10
        feedback.append("Directory created.")
    else:
        feedback.append("Failed: Target directory '/home/ga/Documents/LectureAssets' not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Check Credits (15 pts)
    if result.get("credits_exists") and result.get("credits_content_length", 0) > 10:
        score += 15
        feedback.append("Credits file found and populated.")
    else:
        feedback.append("Credits file missing or empty.")

    # 3. Check Assets (25 pts each)
    assets = result.get("assets", {})
    required_assets = ["asset_01", "asset_02", "asset_03"]
    unique_images = result.get("unique_images", True)
    
    if not unique_images:
        feedback.append("Warning: Duplicate images detected. Each asset must be unique.")
    
    valid_assets_count = 0

    for name in required_assets:
        data = assets.get(name, {})
        asset_score = 0
        
        if data.get("exists"):
            # Base points for file existing
            if data.get("valid_resolution"):
                # Full points for high res
                asset_score = 25
                valid_assets_count += 1
                feedback.append(f"{name}: Valid ({data.get('width')}x{data.get('height')}).")
            else:
                # Penalty for low resolution (thumbnail)
                feedback.append(f"{name}: Resolution too low ({data.get('width')}x{data.get('height')}). Min width 2500px required.")
        else:
            feedback.append(f"{name}: Missing.")
            
        score += asset_score

    # Penalize for duplicates if they passed the individual checks (should be rare if they are exact duplicates, but possible if they renamed copies)
    if not unique_images and valid_assets_count > 1:
        score -= 10
        feedback.append("Penalty applied for duplicate images.")

    # Anti-gaming check
    if not result.get("timestamp_valid", True):
        score = 0
        feedback.append("Failed: Files appear to exist prior to task start (timestamp check failed).")

    return {
        "passed": score >= 85,
        "score": score,
        "feedback": " ".join(feedback)
    }