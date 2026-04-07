#!/usr/bin/env python3
"""
Verifier for Export Clean and Annotated Views task.
Programmatically compares the two exported JPEGs to ensure one has annotations and the other does not.
Uses VLM trajectory analysis to verify proper UI interaction.
"""

import os
import json
import tempfile
import logging
import cv2
import numpy as np

# Import VLM utilities from the framework
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from vlm_utils import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback if standard vlm_utils path differs in framework
    def sample_trajectory_frames(traj, n): return []
    def query_vlm(images, prompt): return {"success": False}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are verifying an agent's trajectory for a medical imaging task in Weasis DICOM Viewer.
Look at these chronological frames and determine:
1. Did the agent select a measurement/drawing tool (like line or arrow) and draw it on the medical image?
2. Did the agent open the 'Export Image' dialog multiple times?
3. Did the agent interact with checkboxes (e.g., 'Draw drawings') in the export dialog?

Respond strictly in JSON:
{
    "drew_measurement": true/false,
    "opened_export_dialog": true/false,
    "toggled_checkboxes": true/false
}
"""

def verify_export_clean_and_annotated_views(traj, env_info, task_info):
    """Verify that both clean and annotated views were exported correctly."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Fetch the result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    task_start = result.get("task_start", 0)
    annotated_info = result.get("annotated_file", {})
    clean_info = result.get("clean_file", {})

    # Criterion 1: Files Exist and were created during task (20 pts)
    ann_valid = annotated_info.get("exists") and annotated_info.get("mtime", 0) >= task_start and annotated_info.get("size_bytes", 0) > 1024
    clean_valid = clean_info.get("exists") and clean_info.get("mtime", 0) >= task_start and clean_info.get("size_bytes", 0) > 1024

    if ann_valid and clean_valid:
        score += 20
        feedback_parts.append("Both files created successfully")
    else:
        feedback_parts.append("Missing or invalid export files")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Image Difference Analysis (55 pts)
    temp_ann = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
    temp_clean = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
    
    try:
        copy_from_env(annotated_info["path"], temp_ann.name)
        copy_from_env(clean_info["path"], temp_clean.name)
        
        img_ann = cv2.imread(temp_ann.name)
        img_clean = cv2.imread(temp_clean.name)
        
        if img_ann is None or img_clean is None:
            feedback_parts.append("Failed to decode exported JPEGs")
        elif img_ann.shape != img_clean.shape:
            feedback_parts.append(f"Dimension mismatch: {img_ann.shape} vs {img_clean.shape} (Must export same view)")
        else:
            score += 20 # View Consistency
            feedback_parts.append("Dimensions match")
            
            # Compute Absolute Difference
            # Use small threshold to account for JPEG compression artifacts
            diff = cv2.absdiff(img_ann, img_clean)
            diff_mask = cv2.cvtColor(diff, cv2.COLOR_BGR2GRAY) > 10 
            
            diff_pixel_count = np.sum(diff_mask)
            total_pixels = diff_mask.size
            
            if diff_pixel_count > 50: # Must be > 0 (annotation exists in one but not other)
                score += 20
                feedback_parts.append("Images are distinct (toggle successful)")
                
                # Check Localized Change (Identical pixels > 90% proves it's just an annotation difference)
                identical_ratio = 1.0 - (diff_pixel_count / total_pixels)
                if identical_ratio > 0.90:
                    score += 15
                    feedback_parts.append(f"Difference is localized ({identical_ratio:.1%} identical)")
                else:
                    feedback_parts.append(f"Difference is too large ({identical_ratio:.1%} identical), backgrounds altered")
            else:
                feedback_parts.append("Images are identical (checkbox was not properly toggled)")
                
    except Exception as e:
        feedback_parts.append(f"Image analysis error: {e}")
    finally:
        if os.path.exists(temp_ann.name): os.unlink(temp_ann.name)
        if os.path.exists(temp_clean.name): os.unlink(temp_clean.name)

    # 3. VLM Verification (25 pts)
    try:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                vlm_score = 0
                if parsed.get("drew_measurement"): vlm_score += 10
                if parsed.get("opened_export_dialog"): vlm_score += 10
                if parsed.get("toggled_checkboxes"): vlm_score += 5
                
                score += vlm_score
                feedback_parts.append(f"VLM verified trajectory (+{vlm_score} pts)")
            else:
                feedback_parts.append("VLM query failed or invalid format")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append("VLM error skipped")

    # Determine Pass/Fail (Threshold: 70, requires basic file existence and distinct images)
    # The distinct images test (diff_pixel_count > 50) represents the core task success
    key_criteria_met = score >= 60 and ("Images are distinct (toggle successful)" in feedback_parts)
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }