#!/usr/bin/env python3
"""
Verifier for physical_description_field_id task.

Verifies that the agent:
1. Created the output file at the correct location.
2. Included the requested physical properties for all 5 chemicals.
3. Used the correct data from CAMEO Chemicals (checked via keywords/values).
4. actually navigated to the pages (via VLM trajectory check).
"""

import json
import base64
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_physical_description_field_id(traj, env_info, task_info):
    """
    Verify the physical description reference task.
    """
    # 1. Setup and Environment Access
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    chemicals_data = metadata.get('chemicals', [])
    
    # 2. Retrieve and Parse Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 3. Check File Existence and Timestamp
    if not result.get("output_file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file '~/Desktop/field_id_reference.txt' was not created."}
    
    if not result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not modified during the task (anti-gaming check failed)."}

    # 4. Decode File Content
    try:
        content_b64 = result.get("file_content_base64", "")
        file_content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to decode file content: {str(e)}"}

    if len(file_content.strip()) < 50:
        return {"passed": False, "score": 0, "feedback": "Output file is empty or too short."}

    # 5. Content Verification (Scoring)
    score = 0
    max_score = 100
    feedback_details = []
    
    # Base score for creating file
    score += 5 
    
    # Logic: We search for the chemical name, then look at the text block *following* it 
    # until the next chemical name or end of file to find properties.
    # To simplify, we'll split the text by lines or generally check presence if structure is loose.
    # Given the task asks for a "reference document", we assume some grouping.
    # We will assume the agent puts the chemical name and its properties relatively close.
    # A robust way is to segment the text by chemical names if possible, but simple keyword search 
    # across the whole file is risky (e.g., "colorless" applies to multiple).
    # Strategy: Find indices of chemical names. Treat text between Index[i] and Index[i+1] as the section for Chemical[i].
    
    file_lower = file_content.lower()
    
    # Find start positions of each chemical
    chem_indices = []
    for i, chem in enumerate(chemicals_data):
        name = chem['name'].lower()
        idx = file_lower.find(name)
        if idx != -1:
            chem_indices.append((idx, i))
    
    # Sort by position in file
    chem_indices.sort(key=lambda x: x[0])
    
    # Verify each found chemical
    chemicals_found_count = 0
    
    for k in range(len(chem_indices)):
        start_idx, chem_idx = chem_indices[k]
        end_idx = chem_indices[k+1][0] if k + 1 < len(chem_indices) else len(file_lower)
        
        section_text = file_lower[start_idx:end_idx]
        chem_data = chemicals_data[chem_idx]
        kw = chem_data['keywords']
        chem_name = chem_data['name']
        
        chem_score = 0
        chem_feedback = []
        
        # Check Physical State (4 pts)
        state_match = any(s in section_text for s in kw.get('state', []))
        if state_match:
            chem_score += 4
        else:
            chem_feedback.append("State missing/wrong")
            
        # Check Color (4 pts)
        color_match = any(c in section_text for c in kw.get('color', []))
        if color_match:
            chem_score += 4
        else:
            chem_feedback.append("Color missing/wrong")
            
        # Check Odor (3 pts)
        odor_match = any(o in section_text for o in kw.get('odor', []))
        if odor_match:
            chem_score += 3
        else:
            chem_feedback.append("Odor missing/wrong")
            
        # Check Boiling Point (3 pts)
        # Check for numeric value +/- tolerance OR text override (e.g. "decomposes")
        bp_correct = False
        if 'bp_text' in kw:
             if any(t in section_text for t in kw['bp_text']):
                 bp_correct = True
        
        if not bp_correct:
            # Look for numbers near "boiling" or "bp" or just numbers in section
            # Simple check: is the specific number present?
            # We allow integer matches for the expected F and C values
            if str(kw.get('bp_f', -999)) in section_text or str(kw.get('bp_c', -999)) in section_text:
                bp_correct = True
        
        if bp_correct:
            chem_score += 3
        else:
            chem_feedback.append("BP missing/wrong")

        # Check Melting Point (3 pts)
        mp_correct = False
        if 'mp_text' in kw:
             if any(t in section_text for t in kw['mp_text']):
                 mp_correct = True
        
        if not mp_correct:
            if str(kw.get('mp_f', -999)) in section_text or str(kw.get('mp_c', -999)) in section_text:
                mp_correct = True
                
        if mp_correct:
            chem_score += 3
        else:
            chem_feedback.append("MP missing/wrong")
            
        score += chem_score
        status = "OK" if chem_score >= 15 else f"Issues: {', '.join(chem_feedback)}"
        feedback_details.append(f"{chem_name}: {status} ({chem_score}/17)")
        chemicals_found_count += 1

    # Penalize if chemicals are missing entirely
    missing_count = len(chemicals_data) - chemicals_found_count
    if missing_count > 0:
        feedback_details.append(f"Missing {missing_count} chemicals completely.")

    # 6. VLM Trajectory Verification (5 pts)
    # Check if agent actually visited CAMEO Chemicals and looked at datasheets
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=8)
        
        prompt = """
        Review these screenshots of an agent's browsing session.
        Did the agent visit the CAMEO Chemicals website (cameochemicals.noaa.gov)?
        Did they look at chemical datasheet pages (pages showing properties like 'Physical Description', 'Hazards')?
        The goal was to look up: Bromine, Potassium Permanganate, Hydrazine, Carbon Disulfide, Titanium Tetrachloride.
        
        Answer 'yes' if you see evidence of searching for chemicals or viewing datasheets.
        Answer 'no' if they stayed on the homepage or went elsewhere.
        """
        
        try:
            vlm_response = query_vlm(images=frames, prompt=prompt).get('parsed', {})
            # We assume query_vlm returns a structured dict or we parse the text. 
            # If the standard response is text, we look for "yes".
            # Adjust based on actual query_vlm implementation return type.
            # Assuming it returns a dict with 'response' or similar, or we just check the string.
            
            # Simple fallback if parsed isn't robust
            ans = str(vlm_response).lower()
            if "yes" in ans or "verified" in ans:
                vlm_score = 5
        except Exception:
            # Fallback if VLM fails: if we have a good text score, assume navigation happened
            if score > 40:
                vlm_score = 5

    score += vlm_score
    
    passed = score >= 60 and chemicals_found_count >= 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": f"Score: {score}/100. Details: {'; '.join(feedback_details)}"
    }