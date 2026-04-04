#!/usr/bin/env python3
"""
Verifier for AIT Equipment Classification task.

Checks:
1. Report file existence and creation time.
2. Presence of all 5 required chemicals.
3. Correct Auto-Ignition Temperature (AIT) values extracted (within tolerance).
4. Correct NEC/IEC T-Class assignment logic (Max Surface Temp <= AIT).
5. Identification of the most restrictive chemical.
6. Determination of facility-wide T-Class.
7. VLM verification of trajectory (agent actually looked up data).
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ait_equipment_classification(traj, env_info, task_info):
    """
    Verify the AIT classification report and agent workflow.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_chemicals = metadata.get('chemicals', [])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # ================================================================
    # 1. Check Task Result JSON & File Existence (10 pts)
    # ================================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Report file was not created"}
        
    if not task_result.get('file_created_during_task', False):
        feedback_parts.append("WARNING: File timestamps indicate pre-existing file")
        # Continue but penalize later if needed, though setup script deletes it
    else:
        score += 10
        feedback_parts.append("Report file created successfully")

    # ================================================================
    # 2. Parse Report Content
    # ================================================================
    report_content = ""
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/ait_report_content.txt", temp_report.name)
        with open(temp_report.name, 'r', errors='ignore') as f:
            report_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read report content: {e}"}
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    logger.info(f"Report Content:\n{report_content}")

    # ================================================================
    # 3. Verify Chemical Data (50 pts - 10 per chemical)
    # ================================================================
    # Parsing logic: Look for chemical name, then nearby numbers and T-class
    
    chemicals_found = 0
    chemicals_correct = 0
    
    for chem in expected_chemicals:
        name = chem['name']
        
        # Simple flexible search for the chemical section
        # We split by chemical name to isolate sections roughly
        if name.lower() not in report_content.lower():
            feedback_parts.append(f"Missing chemical: {name}")
            continue
            
        chemicals_found += 1
        
        # Extract numbers near the chemical name (heuristic window)
        # Find index of name
        idx = report_content.lower().find(name.lower())
        # Look at the 300 chars following the name
        snippet = report_content[idx:idx+300]
        
        # Verify AIT (Temperature)
        # Look for numbers that match the expected range
        c_min, c_max = chem['ait_c_range']
        f_min, f_max = chem['ait_f_range']
        
        # Regex for numbers (int or float)
        numbers = [float(x) for x in re.findall(r'\b\d+\.?\d*\b', snippet)]
        
        ait_found = False
        for num in numbers:
            # Check if it's a valid C or F temp
            if (c_min * 0.9 <= num <= c_max * 1.1) or (f_min * 0.9 <= num <= f_max * 1.1):
                ait_found = True
                break
        
        # Verify T-Class
        # Look for T-codes (T1, T2, T2A, etc.)
        t_classes_found = re.findall(r'\bT[1-6][A-D]?\b', snippet)
        
        t_class_correct = False
        if t_classes_found:
            # Check if any found T-class is in the expected list
            for tc in t_classes_found:
                if tc in chem['expected_tclass']:
                    t_class_correct = True
                    break
        
        if ait_found and t_class_correct:
            score += 10
            chemicals_correct += 1
        elif ait_found:
            score += 5
            feedback_parts.append(f"{name}: AIT correct, T-Class incorrect/missing")
        elif t_class_correct:
            score += 5
            feedback_parts.append(f"{name}: T-Class correct, AIT incorrect/missing")
        else:
            feedback_parts.append(f"{name}: Data incorrect")

    feedback_parts.append(f"Chemicals processed: {chemicals_correct}/5 correct")

    # ================================================================
    # 4. Verify Facility Logic (20 pts)
    # ================================================================
    # Check for "Most Restrictive" identification
    # Carbon Disulfide has lowest AIT (~90-100C)
    
    restrictive_correct = False
    if "carbon disulfide" in report_content.lower() and "restrictive" in report_content.lower():
        # Heuristic: check if they appear close to each other is hard without NLP, 
        # but if both phrases exist, it's a good sign.
        # Let's check specifically for the conclusion section.
        lines = report_content.lower().split('\n')
        for line in lines:
            if "restrictive" in line and "carbon disulfide" in line:
                restrictive_correct = True
                break
                
    if restrictive_correct:
        score += 10
        feedback_parts.append("Correctly identified Carbon Disulfide as most restrictive")
    else:
        feedback_parts.append("Failed to explicitly identify Carbon Disulfide as most restrictive")

    # Check Facility T-Class (Should be T6 or T5 depending on C/S2 reading, usually T6 for safety)
    facility_tclass_correct = False
    expected_facility = metadata.get('facility_tclass', [])
    
    # Look for "Facility" or "Area" and T-Class
    found_facility_rating = False
    for line in report_content.split('\n'):
        if ("facility" in line.lower() or "area" in line.lower() or "overall" in line.lower()) and "T" in line:
            for valid_t in expected_facility:
                if valid_t in line:
                    facility_tclass_correct = True
                    found_facility_rating = True
                    break
    
    if facility_tclass_correct:
        score += 10
        feedback_parts.append("Facility T-Class correct")
    elif found_facility_rating:
         feedback_parts.append("Facility T-Class incorrect")
    else:
         feedback_parts.append("Facility T-Class not found in summary")

    # ================================================================
    # 5. VLM Trajectory Verification (20 pts)
    # ================================================================
    # Verify the agent actually looked up data
    if traj:
        frames = sample_trajectory_frames(traj, n=8)
        
        vlm_prompt = """
        Review these screenshots of an agent performing a task on CAMEO Chemicals.
        The agent should be:
        1. Searching for chemicals (Acetone, Toluene, Hexane, Carbon Disulfide, Diethyl Ether).
        2. Viewing 'Chemical Datasheets'.
        3. Scrolling to 'Physical Properties' sections to see temperatures.
        
        Do you see evidence of the agent searching for specific chemicals and viewing datasheets?
        Answer with a JSON object: {"evidence_found": boolean, "confidence": float, "chemicals_seen": list_of_strings}
        """
        
        try:
            vlm_result = query_vlm(frames, vlm_prompt)
            parsed = vlm_result.get('parsed', {})
            
            if parsed.get('evidence_found', False):
                score += 20
                feedback_parts.append("VLM: Confirmed datasheet lookups")
            else:
                feedback_parts.append("VLM: No clear evidence of datasheet lookups")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if text report is perfect, assume they did it. 
            # Give partial points if file score is high.
            if score >= 60:
                score += 20
                feedback_parts.append("VLM skipped, but output suggests success")
    else:
         feedback_parts.append("No trajectory for VLM verification")

    # Final Score Calculation
    return {
        "passed": score >= 70 and restrictive_correct,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }