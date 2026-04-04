#!/usr/bin/env python3
"""
Verifier for shipping_manifest_weight_calculation task.

Logic:
1. Verify output file exists and was created during the task.
2. Parse the text file to extract data for each chemical.
3. Verify specific gravity values against CAMEO Chemicals ground truth.
4. Verify mathematical consistency (Weight = Volume * SG).
5. Verify total weight and heaviest item identification.
6. Use VLM to confirm the agent actually used the CAMEO website.
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_manifest(content):
    """
    Parses the shipping manifest text into a structured dictionary.
    Expected format blocks:
    Chemical: [Name]
    Specific Gravity: [Value]
    Volume (L): [Value]
    Weight (kg): [Value]
    """
    data = {}
    current_chem = None
    
    # Normalize content
    lines = [line.strip() for line in content.split('\n') if line.strip()]
    
    # Regex patterns
    chem_pat = re.compile(r"Chemical:\s*(.+)", re.IGNORECASE)
    sg_pat = re.compile(r"Specific Gravity:\s*([\d\.]+)", re.IGNORECASE)
    vol_pat = re.compile(r"Volume\s*\(?L\)?:\s*([\d\.]+)", re.IGNORECASE)
    weight_pat = re.compile(r"Weight\s*\(?kg\)?:\s*([\d\.]+)", re.IGNORECASE)
    
    total_pat = re.compile(r"TOTAL SHIPMENT WEIGHT.*:\s*([\d\.]+)", re.IGNORECASE)
    heaviest_pat = re.compile(r"HEAVIEST SINGLE ITEM.*:\s*(.+)", re.IGNORECASE)

    extracted_total = None
    extracted_heaviest = None

    for line in lines:
        # Check for global stats
        m_total = total_pat.search(line)
        if m_total:
            extracted_total = float(m_total.group(1))
            continue
            
        m_heavy = heaviest_pat.search(line)
        if m_heavy:
            extracted_heaviest = m_heavy.group(1).strip()
            continue

        # Check for chemical block start
        m_chem = chem_pat.search(line)
        if m_chem:
            current_chem = m_chem.group(1).strip()
            # Normalize chemical names for easier matching
            if "sulfuric" in current_chem.lower(): current_chem = "Sulfuric Acid"
            elif "ethylene" in current_chem.lower(): current_chem = "Ethylene Glycol"
            elif "carbon" in current_chem.lower(): current_chem = "Carbon Tetrachloride"
            elif "acetone" in current_chem.lower(): current_chem = "Acetone"
            elif "toluene" in current_chem.lower(): current_chem = "Toluene"
            
            if current_chem not in data:
                data[current_chem] = {}
            continue
        
        # Extract properties if inside a block
        if current_chem:
            m_sg = sg_pat.search(line)
            if m_sg:
                data[current_chem]['sg'] = float(m_sg.group(1))
            
            m_vol = vol_pat.search(line)
            if m_vol:
                data[current_chem]['vol'] = float(m_vol.group(1))
                
            m_weight = weight_pat.search(line)
            if m_weight:
                data[current_chem]['weight'] = float(m_weight.group(1))

    return data, extracted_total, extracted_heaviest

def verify_shipping_manifest(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_chemicals = metadata.get('chemicals', {})
    expected_heaviest_name = metadata.get('expected_heaviest', "Acetone")
    
    score = 0
    max_score = 100
    feedback = []
    
    # 1. Check Output File Existence & Timestamp
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_json = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name): os.unlink(temp_result.name)

    if not result_json.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Manifest file not found."}
    
    if not result_json.get('file_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Manifest file was not created during the task (stale data)."}

    score += 5
    feedback.append("File created successfully.")

    # 2. Retrieve and Parse File Content
    temp_manifest = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/home/ga/Documents/shipping_manifest.txt", temp_manifest.name)
        with open(temp_manifest.name, 'r') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve manifest content: {e}"}
    finally:
        if os.path.exists(temp_manifest.name): os.unlink(temp_manifest.name)

    if len(content.strip()) == 0:
        return {"passed": False, "score": score, "feedback": "Manifest file is empty."}

    parsed_data, total_weight_reported, heaviest_reported = parse_manifest(content)
    
    # 3. Verify Chemical Data (SG and Weights)
    chemicals_found = 0
    calculated_total_weight = 0.0
    
    # Points allocation: 5 chemicals * (8 pts SG + 7 pts Weight) = 75 pts
    for chem_name, props in expected_chemicals.items():
        if chem_name in parsed_data:
            chemicals_found += 1
            agent_data = parsed_data[chem_name]
            
            # Verify Specific Gravity
            agent_sg = agent_data.get('sg')
            if agent_sg is not None:
                # Range check
                target = props['sg_target']
                tol = props['sg_tolerance']
                if abs(agent_sg - target) <= (target * tol):
                    score += 8
                    feedback.append(f"{chem_name} SG correct ({agent_sg}).")
                else:
                    feedback.append(f"{chem_name} SG out of range (Got {agent_sg}, Expected ~{target}).")
            else:
                feedback.append(f"{chem_name} SG missing.")

            # Verify Weight Calculation (Internal Consistency)
            # We check if Agent_Weight == Agent_SG * Task_Volume
            # This awards points for DOING the math, even if the SG was slightly off
            agent_weight = agent_data.get('weight')
            task_vol = props['volume']
            
            if agent_weight is not None and agent_sg is not None:
                expected_calc = agent_sg * task_vol
                if abs(agent_weight - expected_calc) < 2.0: # 2kg tolerance for rounding
                    score += 7
                    feedback.append(f"{chem_name} weight calc consistent.")
                else:
                    feedback.append(f"{chem_name} weight calc incorrect (Got {agent_weight}, Expected {expected_calc:.2f}).")
                
                calculated_total_weight += agent_weight
            else:
                feedback.append(f"{chem_name} weight missing.")
        else:
            feedback.append(f"Missing chemical: {chem_name}")

    # 4. Verify Totals and Heaviest (20 pts)
    # Total Weight
    if total_weight_reported is not None:
        # Check against the sum of the AGENT'S calculated weights (consistency)
        if abs(total_weight_reported - calculated_total_weight) < 5.0:
            score += 10
            feedback.append(f"Total weight correct ({total_weight_reported}).")
        else:
            feedback.append(f"Total weight inconsistent (Reported {total_weight_reported}, Sum {calculated_total_weight}).")
    else:
        feedback.append("Total weight not reported.")

    # Heaviest Item
    if heaviest_reported:
        if expected_heaviest_name.lower() in heaviest_reported.lower():
            score += 10
            feedback.append(f"Heaviest item correctly identified as {expected_heaviest_name}.")
        else:
            feedback.append(f"Heaviest item identification incorrect (Got {heaviest_reported}).")
    else:
        feedback.append("Heaviest item not identified.")

    # 5. VLM Verification (Bonus/Anti-Gaming Check)
    # Ensure they actually visited the website and didn't just guess numbers
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    # We won't hard-fail on VLM, but it's good context
    # If score is very high (>90), we expect VLM to show CAMEO Chemicals
    
    vlm_prompt = (
        "Does the user appear to be using the CAMEO Chemicals website? "
        "Look for blue header bars, chemical datasheets, or search results. "
        "Respond 'YES' or 'NO'."
    )
    
    # Only run VLM if we have frames (to save cost/time if empty)
    if frames and score > 20:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_res and vlm_res.get("parsed", "").upper() == "YES":
            feedback.append("VLM confirms CAMEO Chemicals usage.")
        else:
            feedback.append("VLM could not definitively confirm CAMEO Chemicals usage.")

    # Final Pass/Fail
    passed = (score >= 60) and (chemicals_found >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }