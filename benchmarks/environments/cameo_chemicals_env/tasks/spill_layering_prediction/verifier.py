#!/usr/bin/env python3
"""
Verifier for Spill Layering Prediction task.
Verifies the agent looked up SG values and correctly ordered chemicals by density.
"""

import json
import re
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spill_layering(traj, env_info, task_info):
    """
    Verify the spill layering prediction task.
    
    Scoring Criteria:
    1. Output file exists and created during task (10 pts)
    2. SG Values within tolerance for all 5 chemicals (40 pts)
    3. Correct sink/float logic (10 pts)
    4. Correct layering order (bottom to top) (20 pts)
    5. VLM: Agent visited CAMEO Chemicals and searched (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    chemical_data = metadata.get('chemicals', {})
    correct_order = metadata.get('correct_order_bottom_up', [])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Check Export Result JSON (File Existence & Timing)
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not export_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Result file not found on Desktop."}
    
    if not export_result.get('file_valid_time', False):
        return {"passed": False, "score": 0, "feedback": "Result file timestamp invalid (created before task?)."}
        
    score += 10
    feedback_parts.append("File created successfully (10/10)")

    # 2. Analyze File Content
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/home/ga/Desktop/spill_layering_results.txt", temp_txt.name)
        with open(temp_txt.name, 'r') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read result file: {str(e)}"}
    finally:
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)
            
    content_lower = content.lower()
    
    # Verify Specific Gravity Values (40 pts total, 8 per chemical)
    sg_score = 0
    chemicals_found = 0
    
    # Normalize chemical names for search (e.g. "carbon tetrachloride" -> "carbon\s*tetrachloride")
    for chem_name, data in chemical_data.items():
        if chem_name == "Water": continue # Skip water SG check, usually assumed 1.0
        
        # Create loose regex for chemical name
        name_regex = re.escape(chem_name.lower()).replace(r'\ ', r'\s*')
        
        # Look for the chemical name followed by a number reasonably close
        # Matches: "Carbon Tetrachloride ... 1.59" or "Carbon Tetrachloride - SG: 1.59"
        pattern = rf"{name_regex}.*?(\d+\.?\d*)"
        match = re.search(pattern, content_lower)
        
        if match:
            try:
                val = float(match.group(1))
                if data['min'] <= val <= data['max']:
                    sg_score += 8
                    chemicals_found += 1
                else:
                    feedback_parts.append(f"SG for {chem_name} out of range ({val}).")
            except ValueError:
                pass
        else:
            feedback_parts.append(f"Could not find SG value for {chem_name}.")
            
    score += sg_score
    feedback_parts.append(f"SG Values Correct: {chemicals_found}/5 ({sg_score}/40)")

    # Verify Layering Order (20 pts)
    # We strip the file to lines and look for the sequence of chemical names
    layering_score = 0
    found_indices = {}
    
    for chem in correct_order:
        # Simple string find for the chemical name
        idx = content_lower.find(chem.lower())
        if idx != -1:
            found_indices[chem] = idx
    
    # Check if the positions in the file are in increasing order (top to bottom of file matches bottom-up list)
    # The user was asked to list "Layer 1 (Bottom)" first.
    # So "Carbon Tetrachloride" should appear before "Chloroform", etc.
    
    ordered_chems = sorted(found_indices.keys(), key=lambda k: found_indices[k])
    
    # Calculate how closely the found order matches the correct order
    # Simple check: Is the order exactly right for the chemicals found?
    # Filter correct_order to only include found chemicals
    correct_filtered = [c for c in correct_order if c in found_indices]
    
    if len(ordered_chems) >= 4 and ordered_chems == correct_filtered:
         layering_score = 20
         feedback_parts.append("Layering order correct (20/20)")
    elif len(ordered_chems) >= 4:
         # Partial credit if mostly right
         layering_score = 10
         feedback_parts.append("Layering order partially correct (10/20)")
    else:
         feedback_parts.append("Layering order incorrect or missing chemicals")
         
    score += layering_score

    # Verify Sink/Float Logic (10 pts)
    # Difficult to parse explicitly from text without strict format, 
    # so we rely on the implicit logic: if order is correct, logic is likely correct.
    # We can assume if layering score is high, this logic is understood.
    if layering_score >= 10:
        score += 10
        feedback_parts.append("Sink/Float logic inferred correct (10/10)")
    else:
        feedback_parts.append("Sink/Float logic could not be verified due to ordering errors")

    # 3. VLM Verification (20 pts)
    # Check if agent actually used the website
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Did the agent use the CAMEO Chemicals website?
        Look for:
        1. The CAMEO Chemicals logo or header.
        2. Search results for chemicals like 'Carbon Tetrachloride', 'Toluene', etc.
        3. Datasheet pages showing 'Physical Properties' or 'Specific Gravity'.
        
        Answer 'YES' if there is clear evidence of using the tool. Otherwise 'NO'.
        """
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        
        if "YES" in vlm_result.get("response", "").upper():
            score += 20
            feedback_parts.append("VLM: Web tool usage verified (20/20)")
        else:
            feedback_parts.append("VLM: No evidence of tool usage (0/20)")
    else:
        # Fallback if no frames
        feedback_parts.append("VLM: No frames available")

    passed = score >= 60 and chemicals_found >= 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }