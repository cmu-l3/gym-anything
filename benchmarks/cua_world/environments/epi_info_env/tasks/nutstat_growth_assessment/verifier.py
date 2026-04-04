#!/usr/bin/env python3
"""
Verifier for NutStat Growth Assessment task.

Verification Strategy:
1. File Verification (40 pts): Checks if nutstat_results.txt exists and was created during the task.
2. Data Accuracy (40 pts): Parses the text file to verify Z-scores and classifications against expected values.
   - Child A: Normal
   - Child B: Stunted
   - Child C: Overweight
   - Child D: Underweight
3. VLM Verification (20 pts): Uses trajectory to confirm NutStat module was actually used (not just typing into Notepad).
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nutstat_growth_assessment(traj, env_info, task_info):
    """
    Verify the NutStat task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_children = metadata.get('expected_children', {})
    tolerance = metadata.get('tolerance_z', 0.5)

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. Fetch Result JSON and Output File
    # ================================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        # Get result metadata
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_meta = json.load(f)
            
        # Get actual output content
        output_exists = result_meta.get('output_exists', False)
        if output_exists:
            try:
                copy_from_env("C:\\Users\\Docker\\Documents\\nutstat_results.txt", temp_output.name)
                with open(temp_output.name, 'r', encoding='utf-8', errors='ignore') as f:
                    output_content = f.read()
            except Exception as e:
                output_content = ""
                feedback_parts.append(f"Could not read output file: {e}")
        else:
            output_content = ""
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"System error reading results: {e}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_output.name): os.unlink(temp_output.name)

    # ================================================================
    # 2. Score File Existence & Anti-Gaming (20 pts)
    # ================================================================
    if output_exists:
        score += 10
        if result_meta.get('file_created_during_task', False):
            score += 10
            feedback_parts.append("Result file created during task.")
        else:
            feedback_parts.append("Result file exists but timestamp indicates it wasn't created during this session.")
    else:
        feedback_parts.append("Result file not found.")

    # ================================================================
    # 3. Score Content Accuracy (50 pts)
    # ================================================================
    if output_content:
        # Regex to extract data blocks for each child
        # Look for patterns like "Child A", "Z-score: 1.2", "Status: Normal"
        
        children_found = 0
        z_score_matches = 0
        status_matches = 0
        
        for child_id, expected in expected_children.items():
            # Create a flexible regex block for this child
            # Expecting "Child A" then some text then Z-scores
            if child_id not in output_content:
                continue
                
            children_found += 1
            
            # Extract block for this child (until next Child or end)
            block_start = output_content.find(child_id)
            next_child = output_content.find("Child", block_start + len(child_id))
            if next_child == -1:
                block = output_content[block_start:]
            else:
                block = output_content[block_start:next_child]
            
            # Check Status
            if expected['status'].lower() in block.lower():
                status_matches += 1
            
            # Extract Z-scores using regex
            # Looking for numbers after "Z-score:" or just Z-score labels
            # Matches: "Height-for-Age Z-score: -2.1" or similar
            haz_match = re.search(r'Height.*?Z.*?[:=]\s*(-?[\d\.]+)', block, re.IGNORECASE)
            waz_match = re.search(r'Weight.*?Z.*?[:=]\s*(-?[\d\.]+)', block, re.IGNORECASE)
            bmiz_match = re.search(r'BMI.*?Z.*?[:=]\s*(-?[\d\.]+)', block, re.IGNORECASE)
            
            child_z_ok = True
            
            # Check HAZ
            if haz_match:
                try:
                    val = float(haz_match.group(1))
                    if abs(val - expected['haz_target']) > tolerance: child_z_ok = False
                except: child_z_ok = False
            else: child_z_ok = False
            
            # Check WAZ
            if waz_match:
                try:
                    val = float(waz_match.group(1))
                    if abs(val - expected['waz_target']) > tolerance: child_z_ok = False
                except: child_z_ok = False
            else: child_z_ok = False
            
            # Check BMIZ
            if bmiz_match:
                try:
                    val = float(bmiz_match.group(1))
                    if abs(val - expected['bmiz_target']) > tolerance: child_z_ok = False
                except: child_z_ok = False
            else: child_z_ok = False
            
            if child_z_ok:
                z_score_matches += 1
        
        # Scoring logic for content
        # 10 pts for finding all 4 children
        if children_found == 4: score += 10
        elif children_found > 0: score += 5
        
        # 20 pts for correct Z-scores (5 pts per child)
        score += (z_score_matches * 5)
        
        # 20 pts for correct Classifications (5 pts per child)
        score += (status_matches * 5)
        
        feedback_parts.append(f"Found {children_found}/4 children. Correct Z-scores: {z_score_matches}/4. Correct Status: {status_matches}/4.")

    # ================================================================
    # 4. VLM Trajectory Verification (30 pts)
    # ================================================================
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        You are verifying an agent using Epi Info 7's NutStat module.
        Look at these screenshots of the agent's activity.
        
        Check for:
        1. Is the NutStat module open? (It looks different from the main menu, has 'Nutritional Anthropometry' title or growth charts).
        2. Are data fields (Date of Birth, Height, Weight) being filled?
        3. Is there a growth chart or grid of calculations visible?
        
        Return JSON:
        {
            "nutstat_visible": true/false,
            "data_entry_seen": true/false,
            "growth_chart_seen": true/false,
            "confidence": "high/medium/low"
        }
        """
        
        vlm_result = query_vlm(images=frames, prompt=prompt)
        parsed = vlm_result.get('parsed', {})
        
        vlm_score = 0
        if parsed.get('nutstat_visible'): vlm_score += 15
        if parsed.get('data_entry_seen'): vlm_score += 10
        if parsed.get('growth_chart_seen'): vlm_score += 5
        
        score += vlm_score
        feedback_parts.append(f"VLM verification score: {vlm_score}/30")
    else:
        feedback_parts.append("No trajectory frames available for VLM check.")

    return {
        "passed": score >= metadata.get('pass_threshold', 60),
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }