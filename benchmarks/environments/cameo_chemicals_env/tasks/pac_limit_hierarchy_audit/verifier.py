#!/usr/bin/env python3
"""
Verifier for PAC Limit Hierarchy Audit task.
Verifies that the agent correctly identified PAC-2 values and, crucially,
the source authority (AEGL/ERPG/TEEL) based on hierarchy rules.
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_audit_file(content):
    """
    Parses the agent's text file output.
    Expected format blocks:
    Chemical: [Name]
    PAC-2 Value: [Value] [Units]
    Source Basis: [Source]
    """
    entries = {}
    # Split by chemical blocks generally separated by newlines
    # Using regex to find blocks
    
    # Normalize content
    content = content.replace('\r\n', '\n')
    
    # Regex to capture blocks. 
    # Example: Chemical: Chlorine\nPAC-2 Value: 2.0 ppm\nSource Basis: AEGL
    pattern = re.compile(
        r"Chemical:\s*(?P<name>.+?)\n"
        r"PAC-2 Value:\s*(?P<value>.+?)\n"
        r"Source Basis:\s*(?P<source>.+?)(?:\n|$)",
        re.IGNORECASE | re.MULTILINE
    )
    
    for match in pattern.finditer(content):
        name = match.group("name").strip().lower()
        value_str = match.group("value").strip().lower()
        source = match.group("source").strip().upper()
        
        # Extract number from value string
        try:
            # Find the first floating point number
            number = float(re.search(r"[-+]?\d*\.\d+|\d+", value_str).group())
        except (AttributeError, ValueError):
            number = 0.0
            
        # Check units
        is_mg_m3 = "mg/m3" in value_str or "mg/m^3" in value_str
        is_ppm = "ppm" in value_str
        
        entries[name] = {
            "number": number,
            "source": source,
            "unit_mg_m3": is_mg_m3,
            "unit_ppm": is_ppm,
            "raw_value": value_str
        }
        
    return entries

def verify_pac_limit_hierarchy_audit(traj, env_info, task_info):
    """
    Verifies the PAC audit task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_chemicals = metadata.get('chemicals', [])
    output_path = metadata.get('output_file', '/home/ga/Desktop/pac_audit_results.txt')

    # 1. Check basic file existence and timestamps from export result
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
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    if not task_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created during the task (stale data)."}

    # 2. Read and parse content
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(output_path, temp_txt.name)
        with open(temp_txt.name, 'r') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read output file: {e}"}
    finally:
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)

    parsed_entries = parse_audit_file(content)
    
    score = 0
    max_score = 100
    feedback = []
    
    # 3. Score each chemical
    # Weights: File exists (10), 5 chemicals x 18 pts each (90 total)
    # Per chemical: Value (8), Source (8), Units (2)
    
    score += 10 # Base points for valid file
    
    passed_chemicals = 0
    
    for exp in expected_chemicals:
        name_key = exp['name'].lower()
        found = False
        
        # Fuzzy match chemical name in parsed entries
        for parsed_name, data in parsed_entries.items():
            if name_key in parsed_name or parsed_name in name_key:
                found = True
                item_score = 0
                item_feedback = []
                
                # Check Source (Critical logic test)
                if exp['expected_source'] in data['source']:
                    item_score += 8
                else:
                    item_feedback.append(f"Wrong Source (Expected {exp['expected_source']}, Got {data['source']})")
                
                # Check Value
                # Allow 10% tolerance
                if abs(data['number'] - exp['expected_value']) < (exp['expected_value'] * 0.1):
                    item_score += 8
                # Check for trap value (Methyl Mercaptan)
                elif 'trap_value' in exp and abs(data['number'] - exp['trap_value']) < 1.0:
                    item_feedback.append(f"FAILED TRAP: Used ERPG value ({data['number']}) instead of AEGL ({exp['expected_value']})")
                else:
                    item_feedback.append(f"Wrong Value (Expected ~{exp['expected_value']}, Got {data['number']})")
                
                # Check Units
                expected_unit = exp['unit']
                if expected_unit == "ppm" and data['unit_ppm']:
                    item_score += 2
                elif expected_unit == "mg/m3" and data['unit_mg_m3']:
                    item_score += 2
                else:
                    item_feedback.append(f"Wrong Unit (Expected {expected_unit})")
                
                score += item_score
                if item_score == 18:
                    passed_chemicals += 1
                else:
                    feedback.append(f"{exp['name']}: {', '.join(item_feedback)}")
                break
        
        if not found:
            feedback.append(f"Missing chemical: {exp['name']}")

    # 4. VLM Verification (Workflow Check)
    # Ensure they actually visited the site and looked at datasheets
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Does the sequence of images show a user navigating the CAMEO Chemicals website? "
            "Look for: 1. Search results for chemicals like Chlorine or Acetone. "
            "2. Datasheet pages with tables (Physical Properties or Regulatory Information). "
            "3. Tables showing AEGL, ERPG, or PAC values."
        )
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res.get('success', False) and vlm_res.get('parsed', {}).get('answer', False):
                # Small bonus or just confirmation? 
                # We'll just use it to validate valid attempt if score is borderline,
                # but for now rely on hard data.
                pass
        except Exception:
            pass

    final_feedback = f"Score: {score}/100. " + " | ".join(feedback)
    if passed_chemicals == 5:
        final_feedback = "Perfect! All chemicals and sources identified correctly."

    # Pass threshold: 80 points (Allows minor unit error or one mistake, but fails if hierarchy logic is consistently wrong)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }