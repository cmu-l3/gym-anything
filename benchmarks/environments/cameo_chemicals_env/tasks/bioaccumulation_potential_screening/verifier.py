#!/usr/bin/env python3
"""
Verifier for bioaccumulation_potential_screening task.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_screening_file(content):
    """
    Parses the agent's output text file.
    Expected format is roughly:
    Chemical: Name
    Log Kow: Value
    Risk: High/Low
    """
    entries = []
    # Normalize content: remove empty lines, strip whitespace
    lines = [line.strip() for line in content.split('\n') if line.strip()]
    
    # Try to group lines into blocks or parse line by line
    # Simple state machine to grab chunks
    current_entry = {}
    
    for line in lines:
        # Check for Chemical Name
        chem_match = re.search(r'Chemical:?\s*(.+)', line, re.IGNORECASE)
        if chem_match:
            # If we were building an entry and found a new chemical header, save the previous one
            if current_entry and 'name' in current_entry:
                entries.append(current_entry)
                current_entry = {}
            current_entry['name'] = chem_match.group(1).strip()
            continue
            
        # Check for Log Kow
        kow_match = re.search(r'(?:Log\s*Kow|Partition\s*Coefficient|Log\s*P):?\s*([-0-9.]+)', line, re.IGNORECASE)
        if kow_match:
            try:
                current_entry['value'] = float(kow_match.group(1))
            except ValueError:
                pass # parsing failed
            continue
            
        # Check for Risk
        risk_match = re.search(r'Risk:?\s*(High|Low)', line, re.IGNORECASE)
        if risk_match:
            current_entry['risk'] = risk_match.group(1).title() # Title case: High or Low
            continue

    # Append the last entry
    if current_entry and 'name' in current_entry:
        entries.append(current_entry)
        
    return entries

def verify_bioaccumulation_screening(traj, env_info, task_info):
    """
    Verifies the bioaccumulation screening task.
    
    Scoring:
    - 10 pts: File exists and is valid.
    - 10 pts: All 5 chemicals identified.
    - 40 pts: Correct Log Kow values (within tolerance).
    - 40 pts: Correct Risk Classification.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_chemicals = metadata.get('chemicals', [])
    tolerance = metadata.get('tolerance', 0.5)
    
    score = 0
    feedback = []
    
    # 2. Check Result JSON (Basic file metadata)
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result metadata: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    if not result_meta.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
        
    if not result_meta.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created during the task execution (timestamp check failed)."}
    
    score += 10 # File exists and is new
    feedback.append("Output file created.")

    # 3. Read and Parse Content
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/home/ga/Documents/bioaccumulation_screening.txt", temp_txt.name)
        with open(temp_txt.name, 'r') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read output file content: {str(e)}"}
    finally:
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)

    agent_entries = parse_screening_file(content)
    
    if not agent_entries:
        return {"passed": False, "score": score, "feedback": "File exists but could not parse any valid entries (Chemical/Log Kow/Risk)."}

    # 4. Score Chemicals
    chemicals_found = 0
    kow_points = 0
    risk_points = 0
    
    # Points per item
    pts_per_chemical = 10.0 / len(expected_chemicals) # 2 pts each
    pts_per_kow = 40.0 / len(expected_chemicals)      # 8 pts each
    pts_per_risk = 40.0 / len(expected_chemicals)     # 8 pts each
    
    for expected in expected_chemicals:
        # Find matching entry in agent output
        match = None
        for entry in agent_entries:
            name = entry.get('name', '')
            # Check if any variant is in the agent's provided name
            if any(var.lower() in name.lower() for var in expected['variants']):
                match = entry
                break
        
        if match:
            chemicals_found += 1
            feedback.append(f"Found {expected['name']}:")
            
            # Check Log Kow
            agent_val = match.get('value')
            if agent_val is not None:
                # Handle range vs single value ground truth
                is_correct = False
                if 'range_min' in expected and 'range_max' in expected:
                    if expected['range_min'] <= agent_val <= expected['range_max']:
                        is_correct = True
                else:
                    if abs(agent_val - expected['expected_log_kow']) <= tolerance:
                        is_correct = True
                
                if is_correct:
                    kow_points += pts_per_kow
                    feedback.append(f"  - Log Kow correct ({agent_val})")
                else:
                    feedback.append(f"  - Log Kow incorrect (Got {agent_val}, Expected ~{expected.get('expected_log_kow')})")
            else:
                feedback.append("  - Log Kow missing")

            # Check Risk
            agent_risk = match.get('risk')
            if agent_risk and agent_risk.lower() == expected['expected_risk'].lower():
                risk_points += pts_per_risk
                feedback.append(f"  - Risk correct ({agent_risk})")
            else:
                feedback.append(f"  - Risk incorrect (Got {agent_risk}, Expected {expected['expected_risk']})")
                
        else:
            feedback.append(f"Missing {expected['name']}")

    # Apply chemical finding score
    if chemicals_found == len(expected_chemicals):
        score += 10
    else:
        score += (chemicals_found * pts_per_chemical)

    score += kow_points
    score += risk_points
    
    total_score = min(100, int(score))
    
    passed = total_score >= 80
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": "\n".join(feedback)
    }