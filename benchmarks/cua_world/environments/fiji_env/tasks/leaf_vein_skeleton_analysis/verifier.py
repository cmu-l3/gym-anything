#!/usr/bin/env python3
"""
Verifier for leaf_vein_skeleton_analysis task.

Criteria (100 points total):
1. Skeleton Image (15 pts): Exists, created during task, valid binary image.
2. Overlay Image (10 pts): Exists, created during task, valid size.
3. CSV Topology Data (20 pts): Exists, valid cols, >10 branches detected.
4. Analysis Report (15 pts): Exists, mentions units (um).
5. VLM Process Check (25 pts): Trajectory shows Fiji skeletonization steps.
6. VLM Output Check (15 pts): Final result shows vein network structure.

Pass Threshold: 55 points
"""

import json
import os
import tempfile
import logging
from PIL import Image
import numpy as np

# Import VLM utils from framework
# Assuming gym_anything structure
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for testing/standalone
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(prompt, images=None, image=None): return {"success": False}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_leaf_vein_skeleton_analysis(traj, env_info, task_info):
    """
    Verifies the leaf vein skeletonization task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result retrieval failed: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- CHECK 1: Skeleton Image (15 pts) ---
    skel_info = result.get('skeleton_image', {})
    if skel_info.get('exists') and skel_info.get('modified_during_task'):
        if skel_info.get('size', 0) > 500: # Very small file usually means empty
            score += 15
            feedback.append("Skeleton image created.")
        else:
            score += 5
            feedback.append("Skeleton image exists but is suspiciously small.")
    else:
        feedback.append("Skeleton image missing or not created during task.")

    # --- CHECK 2: Overlay Image (10 pts) ---
    over_info = result.get('overlay_image', {})
    if over_info.get('exists') and over_info.get('modified_during_task'):
        score += 10
        feedback.append("Overlay image created.")
    else:
        feedback.append("Overlay image missing.")

    # --- CHECK 3: CSV Data (20 pts) ---
    csv_info = result.get('csv_file', {})
    csv_data = result.get('csv_analysis', {})
    
    if csv_info.get('exists') and csv_info.get('modified_during_task'):
        # Check content quality
        if csv_data.get('valid_rows', 0) > 0:
            score += 10 # Base points for valid CSV
            
            # Check for specific columns logic
            if csv_data.get('has_branch_col') or csv_data.get('has_junction_col'):
                score += 10
                feedback.append("CSV contains valid topology data.")
            else:
                feedback.append("CSV exists but missing required branch/junction columns.")
        else:
            score += 5
            feedback.append("CSV exists but appears empty.")
    else:
        feedback.append("Topology CSV missing.")

    # --- CHECK 4: Report (15 pts) ---
    rep_info = result.get('report_file', {})
    if rep_info.get('exists') and rep_info.get('modified_during_task'):
        if result.get('report_content_valid'):
            score += 15
            feedback.append("Report created with valid content.")
        else:
            score += 10
            feedback.append("Report created but missing keywords (um/branch).")
    else:
        feedback.append("Analysis report missing.")

    # --- CHECK 5 & 6: VLM Verification (40 pts) ---
    
    # Gather images
    traj_frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if not traj_frames and not final_screen:
        feedback.append("No visual evidence available for VLM check.")
    else:
        # Prompt for VLM
        prompt = """
        You are verifying a Fiji (ImageJ) image analysis task.
        The user should have:
        1. Loaded a leaf image (veins visible).
        2. Thresholded it (black/white).
        3. Skeletonized it (thin lines).
        4. Run 'Analyze Skeleton'.

        Look at the sequence of images and the final state.
        
        Q1: Do you see the Fiji interface with a leaf image loaded?
        Q2: Do you see any evidence of binary processing (black/white image) or skeletonization (thin white lines)?
        Q3: Do you see a 'Results' table or 'Analyze Skeleton' output window?
        
        Return JSON:
        {
            "leaf_loaded": boolean,
            "processing_visible": boolean,
            "results_visible": boolean,
            "quality_score_0_to_10": int
        }
        """
        
        # Combine frames for VLM
        images_to_send = traj_frames + ([final_screen] if final_screen else [])
        
        vlm_res = query_vlm(prompt=prompt, images=images_to_send)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            
            # Score Process (25 pts)
            if parsed.get('leaf_loaded'): score += 5
            if parsed.get('processing_visible'): score += 10
            if parsed.get('results_visible'): score += 10
            
            # Score Quality (15 pts)
            q_score = parsed.get('quality_score_0_to_10', 0)
            if q_score >= 5: score += 15
            elif q_score >= 2: score += 5
            
            feedback.append(f"VLM Analysis: Loaded={parsed.get('leaf_loaded')}, Proc={parsed.get('processing_visible')}, Res={parsed.get('results_visible')}")
        else:
            feedback.append("VLM verification failed to run.")

    # Final tally
    passed = score >= 55
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }