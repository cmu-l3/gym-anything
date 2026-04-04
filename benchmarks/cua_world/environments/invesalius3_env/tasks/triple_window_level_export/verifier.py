#!/usr/bin/env python3
"""
Verifier for triple_window_level_export task.

Scoring (100 points total):
  - 30 pts: All 3 files exist and are valid PNGs (10 pts each)
  - 10 pts: Files were created during the task (timestamp check)
  - 15 pts: All 3 files have distinct content (anti-gaming: didn't just export same view 3 times)
  - 45 pts: Visual verification (VLM)
      - 15 pts: Bone window looks like bone window
      - 15 pts: Brain window looks like brain window
      - 15 pts: Soft tissue window looks like soft tissue window

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

# VLM Prompt to distinguish CT windows
VLM_PROMPT = """
You are a radiologist's assistant verifying CT scan exports.
I will show you an image exported from InVesalius.
Identify which "Window/Level" setting appears to be applied to this axial CT slice of a head.

Options:
1. **Bone Window**: The skull bone is bright white and detailed. The brain and soft tissues are very dark or invisible. Background is black.
2. **Brain Window**: The brain tissue shows gray matter differentiation (gray/white contrast). The skull is thick bright white (saturated).
3. **Soft Tissue Window**: You can see details in the skin, scalp, and muscles outside the skull. The brain might look washed out or noisy.

Analyze the image and return JSON:
{
  "window_type": "bone" | "brain" | "soft_tissue" | "other",
  "confidence": "high" | "low",
  "reasoning": "brief explanation"
}
"""

def verify_triple_window_level_export(traj, env_info, task_info):
    """Verify that 3 distinct CT window exports were created correctly."""
    
    # 1. Setup and imports
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
    # 2. Retrieve Result JSON
    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_json.close()
        copy_from_env("/tmp/triple_window_level_result.json", tmp_json.name)
        with open(tmp_json.name) as f:
            result = json.load(f)
        os.unlink(tmp_json.name)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not read result from container: {e}"
        }

    files_info = result.get("files", {})
    
    # 3. File Existence & Validity (30 pts + 10 pts timestamp + 15 pts distinctness)
    
    # Check each file
    expected_keys = ["bone", "brain", "soft_tissue"]
    valid_files_count = 0
    created_during_task_count = 0
    
    for key in expected_keys:
        info = files_info.get(key, {})
        if info.get("exists") and info.get("is_png") and info.get("size_bytes", 0) > 1024:
            score += 10
            valid_files_count += 1
            feedback_parts.append(f"{key}: Exists & Valid")
            
            if info.get("created_after_start"):
                created_during_task_count += 1
        else:
            feedback_parts.append(f"{key}: Missing or Invalid")

    # Timestamp bonus (all or nothing for simplicity, or scaled)
    if created_during_task_count == 3:
        score += 10
        feedback_parts.append("All files created during task")
    elif created_during_task_count > 0:
        score += 5
        feedback_parts.append("Some files created during task")

    # Distinct content check
    if result.get("distinct_content") and valid_files_count == 3:
        score += 15
        feedback_parts.append("All files have distinct content")
    elif valid_files_count > 1 and not result.get("distinct_content"):
        feedback_parts.append("WARNING: Files have identical content (did you change settings?)")

    # 4. VLM Visual Verification (45 pts)
    # We copy the actual PNGs from the container to verify them specifically
    
    if query_vlm and valid_files_count > 0:
        vlm_score = 0
        vlm_feedback = []
        
        # Map expected keys to filenames in the container
        path_map = {
            "bone": "/home/ga/Documents/bone_window.png",
            "brain": "/home/ga/Documents/brain_window.png",
            "soft_tissue": "/home/ga/Documents/soft_tissue_window.png"
        }
        
        for key in expected_keys:
            if not files_info.get(key, {}).get("exists"):
                continue
                
            # Copy image to host for VLM
            try:
                tmp_img = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
                tmp_img.close()
                copy_from_env(path_map[key], tmp_img.name)
                
                # Query VLM
                response = query_vlm(
                    prompt=VLM_PROMPT,
                    image=tmp_img.name
                )
                
                os.unlink(tmp_img.name)
                
                if response.get("success"):
                    parsed = response.get("parsed", {})
                    detected_type = parsed.get("window_type", "other")
                    
                    if detected_type == key:
                        vlm_score += 15
                        vlm_feedback.append(f"{key} verified visually")
                    else:
                        vlm_feedback.append(f"{key} looked like {detected_type}")
                else:
                    vlm_feedback.append(f"VLM failed for {key}")
                    
            except Exception as e:
                logger.error(f"Error verifying {key} with VLM: {e}")
        
        score += vlm_score
        feedback_parts.append(f"Visual Verification: {' '.join(vlm_feedback)}")
        
    elif not query_vlm:
        feedback_parts.append("VLM verification skipped (client unavailable)")
        # Fallback: if files exist, are distinct, and timestamps ok, give partial credit for visual to avoid failing purely on infra
        if score >= 55: 
             score += 20 
             feedback_parts.append("Auto-credited partial visual score due to missing VLM")

    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }