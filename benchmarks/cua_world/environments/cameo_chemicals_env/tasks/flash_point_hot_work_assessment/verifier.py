#!/usr/bin/env python3
"""
Verifier for flash_point_hot_work_assessment task.
Checks the generated report file for correct flash point values, ranking, and classification.
Uses VLM to verify the agent actually performed the search on CAMEO Chemicals.
"""

import json
import os
import re
import logging
import tempfile
from typing import Dict, Any, List, Optional
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report_file(content: str) -> Dict[str, Any]:
    """
    Parses the agent's output text file.
    Expected format lines: "1. Acetone | Flash Point: -4 °F | HIGH RISK"
    """
    parsed_data = {
        "chemicals": [],
        "high_risk_count": None
    }
    
    # Regex for ranking lines: "1. Chemical Name | Flash Point: 123 °F | HIGH RISK"
    # Flexible on spacing and exact separators
    rank_pattern = re.compile(
        r"(\d+)\.\s*([A-Za-z\s,]+?)\s*\|\s*Flash Point:\s*([\d.-]+)\s*°?F\s*\|\s*(HIGH RISK|LOWER RISK)", 
        re.IGNORECASE
    )
    
    # Regex for count line
    count_pattern = re.compile(r"HIGH RISK COUNT:\s*(\d+)", re.IGNORECASE)
    
    for line in content.split('\n'):
        line = line.strip()
        
        # Check for ranking line
        rank_match = rank_pattern.search(line)
        if rank_match:
            rank_num, name, fp_val, risk = rank_match.groups()
            parsed_data["chemicals"].append({
                "rank": int(rank_num),
                "name": name.strip(),
                "flash_point": float(fp_val),
                "classification": risk.upper()
            })
            continue
            
        # Check for count line
        count_match = count_pattern.search(line)
        if count_match:
            parsed_data["high_risk_count"] = int(count_match.group(1))
            
    return parsed_data

def check_chemical_match(agent_name: str, target_name: str, aliases: List[str]) -> bool:
    """Checks if agent chemical name matches target or its aliases."""
    norm_agent = agent_name.lower().replace(",", "")
    norm_target = target_name.lower().replace(",", "")
    
    if norm_target in norm_agent:
        return True
    
    for alias in aliases:
        if alias.lower().replace(",", "") in norm_agent:
            return True
            
    return False

def verify_flash_point_assessment(traj, env_info, task_info):
    """
    Verifies the flash point assessment task.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('chemicals', {})
    expected_order = metadata.get('expected_order', [])
    
    # Load task result JSON
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # 2. Check File Existence and Creation (Anti-Gaming)
    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
        
    if not task_result.get("file_created_during_task", False):
        return {"passed": False, "score": 5, "feedback": "Output file exists but was NOT created during the task (anti-gaming check failed)."}

    # 3. Load and Parse Output File
    output_path = task_result.get("output_path", "")
    temp_output_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(output_path, temp_output_txt.name)
        with open(temp_output_txt.name, 'r') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": 5, "feedback": f"Failed to read output file content: {str(e)}"}
    finally:
        if os.path.exists(temp_output_txt.name):
            os.unlink(temp_output_txt.name)
            
    parsed_data = parse_report_file(content)
    
    # 4. Scoring Logic
    score = 5 # Base score for file existing and being new
    feedback_parts = ["File created."]
    
    # Check completeness
    if len(parsed_data["chemicals"]) == 6:
        score += 10
        feedback_parts.append("All 6 chemicals listed.")
    else:
        feedback_parts.append(f"Found {len(parsed_data['chemicals'])}/6 chemicals.")
        
    # Check Values and Classifications
    correct_values = 0
    correct_classes = 0
    correct_ranks = 0
    
    agent_chem_list = parsed_data["chemicals"]
    
    # Sort agent list by rank to check ordering
    agent_chem_list.sort(key=lambda x: x["rank"])
    
    # Verify each chemical entry
    matched_chems = set()
    
    for agent_entry in agent_chem_list:
        # Identify chemical
        matched_gt_key = None
        for gt_name, gt_data in ground_truth.items():
            if check_chemical_match(agent_entry["name"], gt_name, gt_data.get("aliases", [])):
                matched_gt_key = gt_name
                break
        
        if matched_gt_key:
            matched_chems.add(matched_gt_key)
            gt_data = ground_truth[matched_gt_key]
            
            # Check Flash Point Value
            expected_fp = gt_data["expected_flash_f"]
            tolerance = gt_data["tolerance"]
            agent_fp = agent_entry["flash_point"]
            
            if abs(agent_fp - expected_fp) <= tolerance:
                score += 8
                correct_values += 1
            else:
                feedback_parts.append(f"{matched_gt_key} FP incorrect (Got {agent_fp}, Exp ~{expected_fp}).")

            # Check Classification
            if agent_entry["classification"] == gt_data["classification"]:
                score += 2
                correct_classes += 1
            else:
                feedback_parts.append(f"{matched_gt_key} class incorrect.")
        else:
            feedback_parts.append(f"Unknown chemical: {agent_entry['name']}")

    # Check Ranking Order
    # We compare the order of the identified chemicals in the agent's list
    # against the expected order in metadata
    agent_order_names = []
    for entry in agent_chem_list:
        for gt_name in expected_order:
            # Re-match to get canonical names for order comparison
            gt_data = ground_truth[gt_name]
            if check_chemical_match(entry["name"], gt_name, gt_data.get("aliases", [])):
                agent_order_names.append(gt_name)
                break
    
    # Calculate ranking score (simple exact match of sequence for full points)
    if agent_order_names == expected_order:
        score += 15
        feedback_parts.append("Ranking order perfect.")
    else:
        # Partial credit for mostly sorted?
        # Let's keep it simple: if first 3 are correct (the high risks), give 10 points
        if agent_order_names[:3] == expected_order[:3]:
            score += 10
            feedback_parts.append("Top 3 ranking correct.")
        elif agent_order_names[:1] == expected_order[:1]:
             score += 5 # At least Acetone is first
             feedback_parts.append("Most hazardous correct.")
        else:
             feedback_parts.append("Ranking incorrect.")

    # Check High Risk Count
    if parsed_data["high_risk_count"] == metadata.get("expected_high_risk_count"):
        score += 5
        feedback_parts.append("High risk count correct.")
    else:
        feedback_parts.append(f"Count incorrect (Exp {metadata.get('expected_high_risk_count')}).")

    # 5. VLM Trajectory Verification
    # Ensure they actually visited CAMEO Chemicals
    frames = sample_trajectory_frames(traj, n=5)
    vlm_prompt = "Does this screenshot show the CAMEO Chemicals website or a chemical datasheet? Answer yes or no."
    
    vlm_confirmed = False
    for frame in frames:
        try:
            res = query_vlm(image=frame, prompt=vlm_prompt)
            if res.get("success") and "yes" in res.get("parsed", "").lower() or "yes" in res.get("result", "").lower():
                vlm_confirmed = True
                break
        except:
            continue

    if vlm_confirmed:
        score += 5
        feedback_parts.append("Trajectory verified (CAMEO visited).")
    else:
        feedback_parts.append("No visual evidence of CAMEO usage found.")

    # Final Score Cap
    score = min(100, score)
    
    # Pass threshold: 65 points
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }