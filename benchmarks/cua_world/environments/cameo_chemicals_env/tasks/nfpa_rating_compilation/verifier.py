#!/usr/bin/env python3
"""
Verifier for nfpa_rating_compilation task.
Checks if the agent correctly looked up NFPA ratings and calculated area maximums.
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any, Tuple

# Import VLM utilities if available in the environment
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback/Mock for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(images, prompt): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report(content: str) -> Dict[str, Dict[str, Any]]:
    """
    Parses the generated text report into a structured dictionary.
    Returns a dict mapping 'Chemical Name' -> {'Health': val, ...}
    """
    parsed_data = {}
    
    # Split by chemical sections
    # Normalize newlines
    content = content.replace('\r\n', '\n')
    
    # Regex to capture blocks. 
    # Looking for "Chemical: Name" or "Area Maximum Ratings"
    # This is a simple state machine parser
    current_section = None
    
    lines = content.split('\n')
    for line in lines:
        line = line.strip()
        if not line:
            continue
            
        if line.startswith("Chemical:"):
            current_section = line.split(":", 1)[1].strip()
            parsed_data[current_section] = {}
        elif line.startswith("Area Maximum Ratings"):
            current_section = "Area Max"
            parsed_data[current_section] = {}
        elif current_section and ":" in line:
            key, val = line.split(":", 1)
            key = key.strip()
            val = val.strip()
            
            # Convert numeric values
            if val.isdigit():
                parsed_data[current_section][key] = int(val)
            else:
                parsed_data[current_section][key] = val
                
    return parsed_data

def verify_nfpa_rating_compilation(traj, env_info, task_info):
    """
    Verifies the NFPA report task.
    
    Criteria:
    1. File exists and was created during task.
    2. Parsable content for all 3 chemicals + Area Max.
    3. Correct values for each chemical (matches ground truth).
    4. Correct calculation of Area Max.
    5. VLM verification of CAMEO usage.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Get metadata/ground truth
    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    area_max_gt = metadata.get('area_max', {})
    expected_path = metadata.get('output_file', '/home/ga/Desktop/nfpa_report.txt')

    # Load result JSON
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result metadata: {str(e)}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # Check basic file requirements
    if not result_meta.get('file_exists', False):
        return {"passed": False, "score": 0, "feedback": "Report file not found on Desktop."}
    
    if not result_meta.get('created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Report file was not created/modified during the task window."}

    # Load report content
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(expected_path, temp_report.name)
        with open(temp_report.name, 'r') as f:
            report_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read report file: {str(e)}"}
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    # Parse content
    try:
        parsed_data = parse_report(report_content)
    except Exception as e:
        return {"passed": False, "score": 20, "feedback": f"File exists but could not be parsed: {str(e)}"}

    score = 10 # Base score for file existence
    feedback = []
    
    # Verify individual chemicals
    chemicals_correct = 0
    total_chemicals = 3
    
    for chem_name, gt_values in ground_truth.items():
        # Allow fuzzy matching for chemical name (e.g. "Acrolein" vs "acrolein")
        found_section = None
        for key in parsed_data.keys():
            if chem_name.lower() in key.lower():
                found_section = parsed_data[key]
                break
        
        if not found_section:
            feedback.append(f"❌ Missing section for {chem_name}")
            continue
            
        # Check values
        chem_score = 0
        chem_mistakes = []
        
        for field in ['Health', 'Flammability', 'Instability']:
            if found_section.get(field) == gt_values[field]:
                chem_score += 1
            else:
                chem_mistakes.append(f"{field}: expected {gt_values[field]}, got {found_section.get(field)}")
        
        # Check Special
        # Handle "NONE" vs "" vs None
        special_val = found_section.get('Special', 'NONE')
        if str(special_val).strip().upper() in ['NONE', ''] and gt_values['Special'] == 'NONE':
            chem_score += 1
        elif str(special_val).strip().upper() == gt_values['Special']:
            chem_score += 1
        else:
            chem_mistakes.append(f"Special: expected {gt_values['Special']}, got {special_val}")
            
        if chem_score == 4:
            chemicals_correct += 1
            score += 20 # 20 pts per perfect chemical
            feedback.append(f"✅ {chem_name} correct")
        else:
            score += (chem_score * 4) # Partial credit (max 16 if imperfect)
            feedback.append(f"⚠️ {chem_name} partially correct: " + ", ".join(chem_mistakes))

    # Verify Area Max
    max_section = parsed_data.get('Area Max')
    if max_section:
        max_mistakes = []
        max_score_pts = 0
        for field in ['Health', 'Flammability', 'Instability']:
            if max_section.get(field) == area_max_gt[field]:
                max_score_pts += 1
            else:
                max_mistakes.append(f"{field}: expected {area_max_gt[field]}, got {max_section.get(field)}")
        
        # Special check (contains OX)
        special_max = str(max_section.get('Special', '')).upper()
        if 'OX' in special_max:
            max_score_pts += 1
        else:
            max_mistakes.append(f"Special: expected 'OX', got '{special_max}'")

        if max_score_pts == 4:
            score += 20
            feedback.append("✅ Area Max calculations correct")
        else:
            score += (max_score_pts * 4)
            feedback.append("⚠️ Area Max errors: " + ", ".join(max_mistakes))
    else:
        feedback.append("❌ Missing Area Maximum section")

    # VLM Verification
    # Check if they actually visited CAMEO Chemicals
    frames = sample_trajectory_frames(traj, n=5)
    vlm_result = query_vlm(
        images=frames,
        prompt="Do these screenshots show the user browsing the CAMEO Chemicals website? specifically looking at chemical datasheets or search results?"
    )
    
    vlm_score = 0
    if vlm_result.get("success") and vlm_result.get("parsed", {}).get("answer", False):
        vlm_score = 10
        score += 10
        feedback.append("✅ Visual verification passed (CAMEO usage detected)")
    elif vlm_result.get("success"):
        # If VLM says no, but data is perfect, we give benefit of doubt (maybe few steps?)
        # But if data is imperfect AND VLM says no, likely hallucination.
        pass
    
    # Cap score at 100
    score = min(score, 100)
    
    return {
        "passed": score >= 70 and chemicals_correct >= 2,
        "score": score,
        "feedback": "\n".join(feedback)
    }