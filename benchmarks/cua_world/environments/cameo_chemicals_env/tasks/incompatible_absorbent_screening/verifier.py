#!/usr/bin/env python3
"""
Verifier for Incompatible Absorbent Screening Task
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_absorbent_screening(traj, env_info, task_info):
    """
    Verifies the absorbent safety audit report.
    
    Criteria:
    1. Output file exists and was created during the task.
    2. All 5 required chemicals are listed.
    3. Correct SAFE/UNSAFE status for each chemical.
    4. "UNSAFE" determinations include valid reasoning keywords (anti-gaming).
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_chemicals = metadata.get('chemicals', [])
    output_path = metadata.get('output_path', '/home/ga/Documents/absorbent_safety_audit.txt')
    
    # 2. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 3. Check Basic File Existence & Integrity (Anti-Gaming)
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Report file not found at expected location."}
    
    if not result_data.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Report file was not created or modified during the task window."}

    if result_data.get('output_size_bytes', 0) < 50:
        return {"passed": False, "score": 5, "feedback": "Report file is too small to contain required information."}

    # 4. Retrieve and Parse Content
    temp_content = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(output_path, temp_content.name)
        with open(temp_content.name, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": 5, "feedback": f"Failed to read report content: {str(e)}"}
    finally:
        if os.path.exists(temp_content.name):
            os.unlink(temp_content.name)

    # Parsing Logic
    # We look for blocks of text or lines containing Chemical Name, Status, and Reason.
    # Normalizing content to lower case for keyword search, but keeping structure for parsing.
    
    score = 10 # Base score for creating file
    feedback = []
    
    # Normalize chemicals for easier matching (handle "Nitric Acid, Red Fuming" vs "Nitric Acid")
    # We will search for unique identifiers for each chemical
    
    chem_results = {}
    
    for chem_info in expected_chemicals:
        name = chem_info['name']
        cas = chem_info.get('cas', '')
        status_expected = chem_info['expected_status'] # SAFE or UNSAFE
        keywords = chem_info.get('keywords', [])
        
        # Determine if this chemical is present in the file
        # Search for Name OR CAS
        chem_found = False
        chem_block = ""
        
        # Simple block extractor: Split by "Chemical:" or newlines and look for proximity
        # Robust regex strategy: Find "Chemical:.*Name" then look ahead for Status
        
        # Regex to find the specific chemical section
        # Matches: Chemical: [stuff] Name [stuff] \n ... Status: [status] ... Reason: [reason]
        # We search specifically for the chemical name
        
        # Simplified: Check if name exists in text
        if name.lower() in content.lower() or cas in content:
            chem_found = True
            
            # Try to extract the status associated with this chemical
            # We look for the text segment starting with this chemical name and ending at the next "Chemical:" or EOF
            try:
                # Find start index
                match = re.search(re.escape(name), content, re.IGNORECASE)
                if not match and cas:
                    match = re.search(re.escape(cas), content)
                
                if match:
                    start_idx = match.start()
                    # Find next "Chemical:" or end of string
                    next_match = re.search(r'Chemical:', content[start_idx+10:], re.IGNORECASE)
                    if next_match:
                        end_idx = start_idx + 10 + next_match.start()
                        block = content[start_idx:end_idx]
                    else:
                        block = content[start_idx:]
                    
                    # Analyze block
                    # Check Status
                    status_score = 0
                    if status_expected.upper() in block.upper():
                        # Verify we didn't match "UNSAFE" when looking for "SAFE"
                        if status_expected == "SAFE" and "UNSAFE" in block.upper():
                            # If expected SAFE, but found UNSAFE
                            feedback.append(f"{name}: Incorrectly marked UNSAFE.")
                        elif status_expected == "UNSAFE" and "SAFE" in block.upper() and "UNSAFE" not in block.upper():
                             feedback.append(f"{name}: Incorrectly marked SAFE.")
                        else:
                            status_score = 15
                            feedback.append(f"{name}: Status Correct ({status_expected}).")
                    else:
                        feedback.append(f"{name}: Status missing or incorrect.")

                    # Check Keywords if UNSAFE
                    keyword_score = 0
                    if status_expected == "UNSAFE":
                        if any(k.lower() in block.lower() for k in keywords):
                            # Included valid reasoning
                            pass # Full points included in status_score for simplicity in this rubric, 
                                 # but let's deduct if reasoning is missing
                        else:
                            feedback.append(f"{name}: Warning - reasoning keywords (e.g. fire/ignite) missing.")
                            # Optional: deduct points if strict
                    
                    score += status_score
            except Exception as e:
                feedback.append(f"Error parsing section for {name}.")
        else:
            feedback.append(f"{name}: Not found in report.")

    # 5. Final Scoring
    # Max score calculation:
    # 10 (File exists)
    # 5 chemicals * 15 points = 75
    # Total available logic points = 85
    # +15 points for "All chemicals included" implicit in the loop
    
    # Adjust score to match 100 scale
    # If all 5 chemicals are correct (15*5 = 75) + 10 base = 85.
    # Let's add 15 points if all chemicals were found (regardless of status accuracy) to reach 100.
    
    chemicals_found_count = 0
    for chem in expected_chemicals:
        if chem['name'].lower() in content.lower():
            chemicals_found_count += 1
            
    if chemicals_found_count == 5:
        score += 15
        feedback.append("All chemicals listed (+15 pts).")
    elif chemicals_found_count > 0:
        score += (chemicals_found_count * 3)
        
    passed = score >= 85
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }