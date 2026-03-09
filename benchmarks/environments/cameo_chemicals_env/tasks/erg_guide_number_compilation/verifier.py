#!/usr/bin/env python3
"""
Verifier for ERG Guide Number Compilation Task.
Checks if the agent created a text file with the correct ERG guide numbers for 5 chemicals.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_erg_guide_number_compilation(traj, env_info, task_info):
    """
    Verify the ERG guide number compilation task.
    
    Scoring Logic (Total 100):
    - File exists and has content: 10 pts
    - File created during task (anti-gaming): 5 pts
    - Format compliance (pipe separator): 5 pts
    - Chemical Accuracy (16 pts per chemical x 5 = 80 pts):
      - Chemical present in list: 6 pts
      - Correct ERG guide number: 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Ground Truth Data
    ground_truth = task_info.get('metadata', {}).get('ground_truth', {
        "Chlorine": "124",
        "Propane": "115",
        "Anhydrous Ammonia": "125",
        "Sulfuric Acid": "137",
        "Acetone": "127"
    })
    
    # Also support "Ammonia" without Anhydrous for flexibility
    aliases = {
        "Ammonia": "Anhydrous Ammonia",
        "Anhydrous Ammonia": "Anhydrous Ammonia",
        "Sulfuric": "Sulfuric Acid",
        "Sulfuric Acid": "Sulfuric Acid"
    }

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Load Result JSON
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # 2. Check File Existence and Anti-Gaming
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    output_path = result.get('output_file_path', '/home/ga/Desktop/erg_guide_numbers.txt')

    if not output_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}",
            "details": {"file_exists": False}
        }

    score += 5  # Exists
    feedback_parts.append("File exists")

    # Check content size
    if result.get('output_size_bytes', 0) > 20:
        score += 5
        feedback_parts.append("File has content")
    else:
        feedback_parts.append("File is empty or too small")

    if file_created_during_task:
        score += 5
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp predates task (possible gaming)")
        # We don't fail immediately but this is suspicious
    
    # 3. Read File Content
    temp_output_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    file_content = ""
    try:
        copy_from_env(output_path, temp_output_file.name)
        with open(temp_output_file.name, 'r', errors='replace') as f:
            file_content = f.read()
    except Exception as e:
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"Failed to read output file content: {e}"
        }
    finally:
        if os.path.exists(temp_output_file.name):
            os.unlink(temp_output_file.name)

    # 4. Check Format (Pipe Separator)
    lines = [line.strip() for line in file_content.split('\n') if line.strip()]
    pipe_count = sum(1 for line in lines if '|' in line)
    
    if pipe_count >= 5:
        score += 5
        feedback_parts.append("Format correct (pipes used)")
    elif pipe_count > 0:
        score += 2
        feedback_parts.append("Partial format match")
    else:
        feedback_parts.append("Format incorrect (missing pipes)")

    # 5. Check Content Accuracy
    # Normalize aliases in ground truth for lookup
    chemicals_found = 0
    chemicals_correct = 0
    
    for expected_name, expected_guide in ground_truth.items():
        # Define search pattern for this chemical
        # Allow case-insensitive search
        found = False
        correct = False
        
        # Determine valid names to search for
        search_names = [expected_name.lower()]
        if "Anhydrous Ammonia" in expected_name:
            search_names.append("ammonia")
        if "Sulfuric Acid" in expected_name:
            search_names.append("sulfuric")
            
        # Search lines
        for line in lines:
            line_lower = line.lower()
            if any(name in line_lower for name in search_names):
                found = True
                
                # Extract number
                # Look for numbers after pipe first
                parts = line.split('|')
                found_guide = ""
                
                if len(parts) > 1:
                    # Look in second part
                    matches = re.findall(r'\b\d{3}\b', parts[1])
                    if matches:
                        found_guide = matches[0]
                
                # Fallback: look anywhere in line if pipe parse failed or empty
                if not found_guide:
                    matches = re.findall(r'\b\d{3}\b', line)
                    # Filter out CAS numbers if possible (CAS usually has hyphens, but just in case)
                    # CAS for chlorine is 7782-50-5. 124 is distinct.
                    # Just take the last 3-digit number found, often safe
                    for m in matches:
                        if m == expected_guide:
                            found_guide = m
                            break
                
                if found_guide == expected_guide:
                    correct = True
                break
        
        if found:
            score += 6
            chemicals_found += 1
            if correct:
                score += 10
                chemicals_correct += 1
                feedback_parts.append(f"✓ {expected_name}")
            else:
                feedback_parts.append(f"⚠ {expected_name} found but guide wrong")
        else:
            feedback_parts.append(f"✗ {expected_name} missing")

    # 6. Final Score Calculation
    passed = (score >= 60) and (chemicals_correct >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "chemicals_found": chemicals_found,
            "chemicals_correct": chemicals_correct,
            "file_valid": output_exists and file_created_during_task
        }
    }