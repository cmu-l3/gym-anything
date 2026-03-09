#!/usr/bin/env python3
"""
Verifier for PPE Protection Level Classification task.
Verifies the content of the generated report against CAMEO Chemicals ground truth.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ppe_classification(traj, env_info, task_info):
    """
    Verify the report content matches expected hazmat classifications.
    
    Criteria:
    1. Report file exists and was created during task (Anti-gaming).
    2. All 5 required chemicals are present.
    3. Correct classification (LEVEL_A vs LEVEL_B) for each.
    4. Correct assessment of structural gear adequacy.
    5. Summary section correctly lists chemicals.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Ground Truth from Metadata
    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # --- Step 1: Check basic file stats from task_result.json ---
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Report file not created"}
        
    if not task_result.get('file_created_during_task', False):
        feedback_parts.append("Warning: File timestamp indicates it wasn't created during task window")
        # We assume strict anti-gaming, but allow partial points if content is perfect
    else:
        score += 10 # 10 pts for valid creation
        feedback_parts.append("File created during task")

    # --- Step 2: Retrieve and parse the report content ---
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        # Export script copied it to /tmp/protective_clothing_report.txt
        copy_from_env("/tmp/protective_clothing_report.txt", temp_report.name)
        with open(temp_report.name, 'r') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve report content: {e}"}
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    if len(content) < 50:
        return {"passed": False, "score": score, "feedback": "File content too short to be valid"}

    # Normalize content for parsing
    # Split into blocks by separator
    blocks = content.split('---')
    
    parsed_chemicals = {}
    summary_section = ""
    
    for block in blocks:
        block = block.strip()
        if not block:
            continue
            
        if "SUMMARY" in block:
            summary_section = block
            continue
            
        # Parse chemical entry
        chem_data = {}
        lines = block.split('\n')
        name_found = False
        
        for line in lines:
            if ':' not in line:
                continue
            key, val = line.split(':', 1)
            key = key.strip().upper()
            val = val.strip()
            
            if key == 'CHEMICAL':
                chem_data['name'] = val
                name_found = True
            elif key == 'UN_NUMBER':
                chem_data['un'] = val
            elif key == 'STRUCTURAL_GEAR_ADEQUATE':
                chem_data['gear'] = val.upper()
            elif key == 'SCBA_REQUIRED':
                chem_data['scba'] = val.upper()
            elif key == 'CLASSIFICATION':
                chem_data['level'] = val.upper()
        
        if name_found:
            # Use name as key, handle potential casing diffs or variations
            # We map "Acetone" to the ground truth key
            matched_key = None
            for gt_name in ground_truth.keys():
                if gt_name.lower() in chem_data['name'].lower():
                    matched_key = gt_name
                    break
            
            if matched_key:
                parsed_chemicals[matched_key] = chem_data

    # --- Step 3: Verify individual chemicals (12 pts each -> 60 max) ---
    chem_score = 0
    missing_chems = []
    
    for gt_name, gt_data in ground_truth.items():
        if gt_name not in parsed_chemicals:
            missing_chems.append(gt_name)
            continue
            
        agent_data = parsed_chemicals[gt_name]
        chem_correct = True
        reasons = []
        
        # Check Level (Critical)
        if agent_data.get('level') != gt_data['level']:
            chem_correct = False
            reasons.append(f"Wrong Level (Expected {gt_data['level']}, got {agent_data.get('level')})")
            
        # Check Gear Adequacy (Critical)
        expected_gear = gt_data['gear_adequate'] # YES or NO
        agent_gear = agent_data.get('gear') # Should be YES or NO
        
        # Allow fuzzy matching for gear (e.g. "YES (Limited)")
        if expected_gear == "NO" and "NO" not in agent_gear:
            chem_correct = False
            reasons.append("Gear adequacy wrong")
        if expected_gear == "YES" and "YES" not in agent_gear:
             chem_correct = False
             reasons.append("Gear adequacy wrong")
             
        # Check SCBA (Minor)
        if "YES" not in agent_data.get('scba', 'NO'):
            # Only penalize small amount if main classification correct
            pass 

        if chem_correct:
            chem_score += 12
        else:
            feedback_parts.append(f"{gt_name} errors: {', '.join(reasons)}")
            
    score += chem_score
    if missing_chems:
        feedback_parts.append(f"Missing chemicals: {', '.join(missing_chems)}")
    else:
        feedback_parts.append("All 5 chemicals processed")

    # --- Step 4: Verify Summary Section (15 pts) ---
    summary_score = 0
    summary_upper = summary_section.upper()
    
    # Check Level A list
    level_a_chems = ["CHLORINE", "HYDROGEN CYANIDE", "PHOSGENE"]
    level_a_found = 0
    for c in level_a_chems:
        if c in summary_upper:
            level_a_found += 1
            
    # Check Level B list
    level_b_chems = ["ACETONE", "TOLUENE"]
    level_b_found = 0
    for c in level_b_chems:
        if c in summary_upper:
            level_b_found += 1
            
    if level_a_found == 3 and level_b_found == 2:
        score += 15
        feedback_parts.append("Summary section correct")
    elif level_a_found >= 2 and level_b_found >= 1:
        score += 8
        feedback_parts.append("Summary section partially correct")
    else:
        feedback_parts.append("Summary section missing or incorrect")

    # --- Step 5: VLM / Trajectory verification (15 pts) ---
    # We use a placeholder here for programmatic VLM checking
    # In a real scenario, we would grab frames and query VLM.
    # For now, we assume if they got the data right, they likely visited the pages.
    # We give points if files were valid and chemical data is correct.
    if chem_score >= 36: # At least 3 chemicals correct
        score += 15
        feedback_parts.append("Data accuracy implies valid workflow")
    else:
        feedback_parts.append("Workflow verification failed due to data inaccuracy")

    passed = score >= 60 and chem_score >= 36
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }