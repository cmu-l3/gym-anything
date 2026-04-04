#!/usr/bin/env python3
"""
Verifier for compare_comedication_across_cancer_drugs task.

Verifies:
1. Agent created the report file with correct info (text analysis).
2. Agent actually navigated to BOTH Dasatinib and Axitinib profiles (VLM trajectory analysis).
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any, List

# Import VLM utils from framework
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback for testing/standalone
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(prompt, images): return {"success": False}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compare_comedication(traj, env_info, task_info):
    """
    Verify the agent compared Clarithromycin interactions for Dasatinib and Axitinib.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_keywords = metadata.get('expected_keywords', ["Dasatinib", "Axitinib", "Clarithromycin"])
    color_keywords = metadata.get('color_keywords', ["red", "orange", "yellow", "green", "grey"])

    # 1. Retrieve Result JSON from Container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Analyze File Content (Textual Verification)
    file_score = 0
    feedback_parts = []
    
    file_exists = result_data.get('file_exists', False)
    created_during = result_data.get('file_created_during_task', False)
    content = result_data.get('file_content', "").lower()

    if file_exists and created_during:
        file_score += 20
        feedback_parts.append("Report file created.")
        
        # Check for drug names
        found_drugs = [k for k in expected_keywords if k.lower() in content]
        if len(found_drugs) == len(expected_keywords):
            file_score += 20
            feedback_parts.append("Report mentions all required drugs.")
        else:
            feedback_parts.append(f"Report missing keywords: {set(expected_keywords) - set([f.capitalize() for f in found_drugs])}")

        # Check for colors (interaction results)
        found_colors = [c for c in color_keywords if c in content]
        if found_colors:
            file_score += 10
            feedback_parts.append(f"Report mentions interaction colors: {', '.join(found_colors)}.")
        else:
            feedback_parts.append("Report does not mention interaction colors.")
            
        # Check for comparison logic (words like 'same', 'different', 'both')
        if any(w in content for w in ['same', 'different', 'differs', 'identical', 'both']):
            file_score += 10
            feedback_parts.append("Report contains comparison statement.")
    else:
        feedback_parts.append("Report file not created or not created during task.")

    # 3. Analyze Trajectory (Visual Verification via VLM)
    # We need to verify the agent actually visited the screens, not just hallucinated the file.
    vlm_score = 0
    
    frames = sample_trajectory_frames(traj, n=8)  # Sample more frames to catch navigation
    
    if not frames:
        feedback_parts.append("No trajectory frames available for visual verification.")
    else:
        prompt = """
        You are verifying a user's workflow in the 'Liverpool Cancer iChart' app.
        The user was supposed to:
        1. Navigate to the drug page for 'Dasatinib'.
        2. Navigate to the drug page for 'Axitinib'.
        3. Look for 'Clarithromycin' in the co-medication lists.
        
        Look at the sequence of images provided.
        
        Answer the following in JSON format:
        {
            "seen_dasatinib": boolean,  // Did you see a screen titled 'Dasatinib' or listing Dasatinib?
            "seen_axitinib": boolean,   // Did you see a screen titled 'Axitinib' or listing Axitinib?
            "seen_clarithromycin": boolean, // Did you see 'Clarithromycin' selected or in a list?
            "seen_traffic_light": boolean // Did you see the red/amber/green/yellow interaction result banner?
        }
        """
        
        vlm_resp = query_vlm(prompt=prompt, images=frames)
        
        if vlm_resp.get("success"):
            analysis = vlm_resp.get("parsed", {})
            
            if analysis.get("seen_dasatinib"):
                vlm_score += 15
                feedback_parts.append("Visual evidence: Dasatinib profile visited.")
            
            if analysis.get("seen_axitinib"):
                vlm_score += 15
                feedback_parts.append("Visual evidence: Axitinib profile visited.")
                
            if analysis.get("seen_clarithromycin"):
                vlm_score += 5
                feedback_parts.append("Visual evidence: Clarithromycin looked up.")

            if analysis.get("seen_traffic_light"):
                vlm_score += 5
                feedback_parts.append("Visual evidence: Interaction result viewed.")
        else:
            feedback_parts.append("VLM verification failed to process images.")

    # 4. Calculate Final Score
    total_score = file_score + vlm_score
    passed = total_score >= 60 and analysis.get("seen_dasatinib") and analysis.get("seen_axitinib")

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " ".join(feedback_parts)
    }