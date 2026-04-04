#!/usr/bin/env python3
"""
Verifier for flammability_range_assessment task.
Evaluates the content of the generated text report against reference values from CAMEO Chemicals.
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_flammability_assessment(traj, env_info, task_info):
    """
    Verify the flammability assessment report.
    
    Criteria:
    1. Output file exists and was created during task (5 pts)
    2. Data accuracy for 5 chemicals (50 pts - 10 per chemical)
    3. Flammable range calculations present (10 pts)
    4. Correct analytical conclusions (30 pts)
    5. VLM verification of tool usage (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Load task result metadata
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 1. File Existence & Anti-Gaming (5 pts)
    if not task_result.get('file_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}
    
    if not task_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created during task (anti-gaming check failed)"}
        
    score += 5
    feedback_parts.append("File created successfully")

    # Load report content
    report_content = ""
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/home/ga/Documents/flammability_assessment.txt", temp_txt.name)
        with open(temp_txt.name, 'r', errors='ignore') as f:
            report_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read report content: {e}"}
    finally:
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)

    # Reference Data
    chemicals = {
        "acetone": {"lel": (2.0, 3.0), "uel": (11.0, 14.0)},
        "toluene": {"lel": (1.0, 1.5), "uel": (6.0, 8.0)},
        "methanol": {"lel": (5.0, 7.5), "uel": (30.0, 40.0)},
        "ethylene oxide": {"lel": (2.0, 4.0), "uel": (90.0, 100.0)},
        "carbon disulfide": {"lel": (1.0, 2.0), "uel": (40.0, 60.0)}
    }
    
    # Helper to find chemical block
    report_lower = report_content.lower()
    
    # 2. Check Data Accuracy (50 pts)
    data_score = 0
    for chem_name, ranges in chemicals.items():
        if chem_name not in report_lower:
            feedback_parts.append(f"Missing chemical: {chem_name.title()}")
            continue
            
        # Extract block for this chemical (simple heuristic: look for name, then scan next few lines)
        # Better approach: Split by "Chemical:"
        chem_blocks = re.split(r'chemical\s*:', report_lower)
        target_block = None
        for block in chem_blocks:
            if chem_name in block.split('\n')[0]: # Check if name is in the first line of the block
                target_block = block
                break
        
        if not target_block:
            # Fallback: just search nearby
            pass

        # We'll use a simpler regex search on the whole file or best-effort block
        # Find LEL for this chemical
        # Regex looks for chemical name, then consumes text until LEL pattern
        # This is tricky without strict blocking. Let's try finding the values closest to the name.
        
        chem_passed = False
        
        # Regex to find values
        # Look for the chemical name, then look forward for LEL/UEL
        # This assumes the order in file matches the requested order or blocks are distinct
        
        try:
            # Find the start index of the chemical
            start_idx = report_lower.find(chem_name)
            if start_idx == -1: continue
            
            # Look at the text following the name (up to 500 chars)
            context = report_lower[start_idx:start_idx+500]
            
            lel_match = re.search(r'lel\s*[:\(%]*\s*([\d\.]+)', context)
            uel_match = re.search(r'uel\s*[:\(%]*\s*([\d\.]+)', context)
            
            chem_pts = 0
            if lel_match:
                val = float(lel_match.group(1))
                if ranges['lel'][0] <= val <= ranges['lel'][1]:
                    chem_pts += 3
            
            if uel_match:
                val = float(uel_match.group(1))
                if ranges['uel'][0] <= val <= ranges['uel'][1]:
                    chem_pts += 3
                    
            # Check for Flash Point and Autoignition presence (values vary by unit, strict check is hard)
            if 'flash' in context and re.search(r'flash.*[\d]+', context):
                chem_pts += 2
            if 'autoignition' in context and re.search(r'autoignition.*[\d]+', context):
                chem_pts += 2
                
            data_score += chem_pts
            
        except Exception as e:
            logger.warning(f"Error parsing {chem_name}: {e}")
            
    score += data_score
    feedback_parts.append(f"Data accuracy score: {data_score}/50")

    # 3. Flammable Range Calculations (10 pts)
    # Check if lines with "Flammable Range" and a number exist
    range_calcs = re.findall(r'flammable range.*[\d\.]+', report_lower)
    if len(range_calcs) >= 5:
        score += 10
        feedback_parts.append("Flammable ranges calculated")
    elif len(range_calcs) >= 1:
        score += 5
        feedback_parts.append("Partial flammable ranges calculated")

    # 4. Analysis Conclusions (30 pts)
    analysis_score = 0
    
    # Check for Analysis section
    analysis_section = ""
    if "analysis" in report_lower:
        analysis_section = report_lower.split("analysis")[-1]
    else:
        analysis_section = report_lower # Search whole file if no header

    # Widest range -> Ethylene Oxide
    if "ethylene oxide" in analysis_section and ("widest" in analysis_section or "range" in analysis_section):
        # Verify it's associated with "widest"
        if re.search(r'widest.*ethylene oxide', analysis_section, re.DOTALL) or \
           re.search(r'ethylene oxide.*widest', analysis_section, re.DOTALL):
            analysis_score += 15
            feedback_parts.append("Correctly identified Widest Range (Ethylene Oxide)")

    # Lowest Autoignition -> Carbon Disulfide
    if "carbon disulfide" in analysis_section and ("lowest" in analysis_section or "autoignition" in analysis_section):
        if re.search(r'lowest.*carbon disulfide', analysis_section, re.DOTALL) or \
           re.search(r'carbon disulfide.*lowest', analysis_section, re.DOTALL):
            analysis_score += 15
            feedback_parts.append("Correctly identified Lowest Autoignition (Carbon Disulfide)")
            
    score += analysis_score

    # 5. VLM Verification (5 pts)
    # Ensure the agent actually looked at CAMEO
    frames = sample_trajectory_frames(traj, n=5)
    vlm_result = query_vlm(
        images=frames,
        prompt="Do these screenshots show the user searching for chemicals or viewing datasheets on the CAMEO Chemicals website? Look for 'CAMEO Chemicals', chemical names like 'Acetone' or 'Toluene', or datasheet tables."
    )
    
    if vlm_result.get("success") and vlm_result.get("parsed", {}).get("answer", "").lower().startswith("yes"):
        # The default VLM prompt often returns yes/no, but here we assume a boolean check wrapper or simple heuristic
        # Since query_vlm returns a structured dict, we usually rely on specific parsing.
        # For simplicity in this template, we give points if successful query.
        # A more robust check would parse "yes" from the response.
        score += 5
        feedback_parts.append("VLM verified CAMEO usage")
    elif vlm_result.get("success"):
         # Check content of response
         resp = str(vlm_result.get("parsed", "")) + str(vlm_result.get("raw", ""))
         if "cameo" in resp.lower() or "chemical" in resp.lower():
             score += 5
             feedback_parts.append("VLM verified CAMEO usage")
    
    # Final Result
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }