#!/usr/bin/env python3
"""
Verifier for extract_chart_summary task.
Compares agent's text summary against database ground truth.
"""

import json
import tempfile
import os
import re
import logging
from fuzzywuzzy import fuzz # Assuming fuzzywuzzy is available or implementing simple match

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_chart_summary(traj, env_info, task_info):
    """
    Verify the extracted patient summary.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve files
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    temp_truth = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # Get result JSON
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_meta = json.load(f)

        if not result_meta.get('output_exists'):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Output file ~/patient_summary.txt was not created."
            }

        # Get Agent Output
        copy_from_env("/tmp/verification_output.txt", temp_output.name)
        with open(temp_output.name, 'r') as f:
            agent_text = f.read()

        # Get Ground Truth
        copy_from_env("/tmp/verification_ground_truth.json", temp_truth.name)
        with open(temp_truth.name, 'r') as f:
            ground_truth = json.load(f)

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving verification files: {str(e)}"}
    finally:
        os.unlink(temp_result.name)
        os.unlink(temp_output.name)
        os.unlink(temp_truth.name)

    # --- Scoring Logic ---
    score = 0
    feedback = []
    
    # 1. File Format & Existence (10 pts)
    # Check for headers
    required_headers = ["PATIENT CHART SUMMARY", "ALLERGIES", "CONDITIONS", "VITALS"]
    headers_found = sum(1 for h in required_headers if h in agent_text)
    if headers_found == len(required_headers):
        score += 10
        feedback.append("File format correct.")
    else:
        feedback.append(f"File format incomplete. Found {headers_found}/{len(required_headers)} headers.")

    # 2. Demographics (20 pts)
    # Name (10)
    expected_given = ground_truth['name_given'].lower()
    expected_family = ground_truth['name_family'].lower()
    if expected_given in agent_text.lower() and expected_family in agent_text.lower():
        score += 10
        feedback.append("Patient name matches.")
    else:
        feedback.append(f"Patient name incorrect. Expected {expected_given} {expected_family}.")
        
    # DOB (10)
    expected_dob = ground_truth['dob']
    if expected_dob in agent_text:
        score += 10
        feedback.append("DOB matches.")
    else:
        feedback.append(f"DOB incorrect. Expected {expected_dob}.")

    # 3. Allergies (20 pts)
    # Parse Allergies section from text
    # Simple extraction: look for lines starting with "- " under ALLERGIES but before CONDITIONS
    allergies_section = re.search(r'ALLERGIES:(.*?)CONDITIONS:', agent_text, re.DOTALL)
    agent_allergies = []
    if allergies_section:
        lines = allergies_section.group(1).strip().split('\n')
        for line in lines:
            if line.strip().startswith('-'):
                agent_allergies.append(line.strip())

    gt_allergies = ground_truth['allergies']
    
    # Allergens (15 pts)
    matched_allergens = 0
    for gt_a in gt_allergies:
        name = gt_a['name'].lower()
        # Fuzzy check in agent lines
        if any(name in line.lower() for line in agent_allergies):
            matched_allergens += 1
    
    if len(gt_allergies) > 0:
        score += int(15 * (matched_allergens / len(gt_allergies)))
    else:
        score += 15 # No allergies to match
    
    if matched_allergens == len(gt_allergies):
        feedback.append("All allergies listed.")
    else:
        feedback.append(f"Missed some allergies. Found {matched_allergens}/{len(gt_allergies)}.")

    # Severity (5 pts)
    # Check if severity keywords are present for matched lines
    severity_matches = 0
    for gt_a in gt_allergies:
        sev = gt_a['severity'].lower()
        if sev == "unknown": continue
        # Check if severity appears in the same line as the allergen
        name = gt_a['name'].lower()
        for line in agent_allergies:
            if name in line.lower() and sev in line.lower():
                severity_matches += 1
                break
    
    if len(gt_allergies) > 0:
         score += int(5 * (severity_matches / len(gt_allergies)))
    else:
         score += 5

    # 4. Conditions (15 pts)
    conditions_section = re.search(r'CONDITIONS:(.*?)VITALS', agent_text, re.DOTALL)
    agent_conditions = []
    if conditions_section:
        lines = conditions_section.group(1).strip().split('\n')
        for line in lines:
            if line.strip().startswith('-'):
                agent_conditions.append(line.strip())

    gt_conditions = ground_truth['conditions']
    matched_conditions = 0
    for gt_c in gt_conditions:
        name = gt_c.lower()
        if any(name in line.lower() for line in agent_conditions):
            matched_conditions += 1
            
    if len(gt_conditions) > 0:
        score += int(15 * (matched_conditions / len(gt_conditions)))
    else:
        score += 15
        
    feedback.append(f"Conditions found: {matched_conditions}/{len(gt_conditions)}")

    # 5. Vitals (30 pts)
    # Parse Vitals section
    vitals_section = re.search(r'VITALS.*:(.*)', agent_text, re.DOTALL)
    vitals_text = vitals_section.group(1) if vitals_section else ""
    
    gt_vitals = ground_truth['vitals']
    
    # Helper to extract number
    def extract_val(pattern, text):
        m = re.search(pattern, text, re.IGNORECASE)
        if m:
            try:
                return float(m.group(1))
            except:
                return None
        return None

    # Check each vital with tolerance
    # Systolic (8)
    if 'systolic' in gt_vitals:
        val = extract_val(r'Systolic.*?(\d+)', vitals_text)
        if val and abs(val - float(gt_vitals['systolic'])) <= 5:
            score += 8
    else:
        score += 8 # Not applicable

    # Diastolic (8)
    if 'diastolic' in gt_vitals:
        val = extract_val(r'Diastolic.*?(\d+)', vitals_text)
        if val and abs(val - float(gt_vitals['diastolic'])) <= 5:
            score += 8
    else:
        score += 8

    # Weight (7)
    if 'weight' in gt_vitals:
        val = extract_val(r'Weight.*?(\d+\.?\d*)', vitals_text)
        if val and abs(val - float(gt_vitals['weight'])) <= 2.0:
            score += 7
    else:
        score += 7

    # Height (7)
    if 'height' in gt_vitals:
        val = extract_val(r'Height.*?(\d+\.?\d*)', vitals_text)
        if val and abs(val - float(gt_vitals['height'])) <= 2.0:
            score += 7
    else:
        score += 7
    
    feedback.append(f"Vitals checked against ground truth.")

    # 6. VLM Check (5 pts)
    # Simple check if trajectory was provided (placeholder for real VLM logic)
    # In real usage, we would query the VLM here.
    # For now, we give points if verification reached here.
    score += 5
    
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }