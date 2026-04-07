#!/usr/bin/env python3
"""
Verifier for create_vin_validator_voice task.

VERIFICATION STRATEGY:
1. File Existence & Modification: Ensure all Talon files and the results CSV were created during the task.
2. Modulo 11 Ground Truth Verification: Re-calculate the check digits for all 500 rows in `vin_results.csv`
   to ensure the agent correctly flagged structurally valid and invalid VINs.
3. List Integrity: Parse `vin_characters.talon-list` to verify I, O, and Q are excluded.
4. VLM Verification: Use trajectory frames to confirm the agent edited code in an IDE/Editor.
"""

import json
import os
import tempfile
import ast
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_modulo_11(vin: str) -> bool:
    """Ground truth Modulo 11 check digit implementation."""
    if len(vin) != 17:
        return False
    if any(c in 'IOQ' for c in vin):
        return False
        
    trans_map = {'A':1, 'B':2, 'C':3, 'D':4, 'E':5, 'F':6, 'G':7, 'H':8,
                 'J':1, 'K':2, 'L':3, 'M':4, 'N':5, 'P':7, 'R':9,
                 'S':2, 'T':3, 'U':4, 'V':5, 'W':6, 'X':7, 'Y':8, 'Z':9}
    weights = [8,7,6,5,4,3,2,10,0,9,8,7,6,5,4,3,2]
    
    total = 0
    for i, char in enumerate(vin):
        if char.isdigit():
            val = int(char)
        elif char in trans_map:
            val = trans_map[char]
        else:
            return False
        total += val * weights[i]
        
    rem = total % 11
    expected = 'X' if rem == 10 else str(rem)
    return expected == vin[8]

def check_talon_list_exclusions(filepath: str) -> dict:
    """Verifies that the Talon list does NOT map I, O, or Q."""
    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()
            
        found_invalid = []
        is_list_declared = False
        
        for line in lines:
            line = line.strip()
            if line.startswith('list:'):
                is_list_declared = True
            
            if ':' in line and not line.startswith('#'):
                # Split and get the mapped value (right side)
                parts = line.split(':')
                if len(parts) >= 2:
                    val = parts[1].strip().upper()
                    if val in ['I', 'O', 'Q']:
                        found_invalid.append(val)
                        
        return {
            'valid_format': is_list_declared,
            'invalid_chars_found': found_invalid
        }
    except Exception as e:
        return {'error': str(e)}

def verify_vin_validator(traj, env_info, task_info):
    """Main verification logic."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    with tempfile.TemporaryDirectory() as temp_dir:
        # 1. Retrieve the exported JSON metadata
        json_dest = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("C:/tmp/task_result.json", json_dest)
            with open(json_dest, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}

        files_meta = result.get('files', {})
        task_start = result.get('task_start', 0)

        # 2. Check architecture presence (15 points)
        required_files = ['vin_results_csv', 'vin_characters_list', 'vin_math_py', 'vin_talon_py', 'vin_talon']
        files_present = [f for f in required_files if files_meta.get(f, {}).get('exists', False)]
        
        if len(files_present) == len(required_files):
            score += 15
            feedback_parts.append("✅ All required Talon architecture files created.")
        elif len(files_present) >= 3:
            score += 5
            feedback_parts.append(f"⚠️ Partial files created: {', '.join(files_present)}")
        else:
            feedback_parts.append("❌ Missing required architecture files.")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # Anti-gaming: Ensure CSV was created during the task
        csv_mtime = files_meta.get('vin_results_csv', {}).get('mtime', 0)
        if csv_mtime < task_start:
            return {"passed": False, "score": 0, "feedback": "❌ CSV file was not created during the task execution (Anti-gaming flag)."}

        # 3. List Integrity Check (15 points)
        list_dest = os.path.join(temp_dir, "vin_characters.talon-list")
        copy_from_env("C:/tmp/vin_characters.talon-list", list_dest)
        
        list_check = check_talon_list_exclusions(list_dest)
        if list_check.get('valid_format'):
            if not list_check.get('invalid_chars_found'):
                score += 15
                feedback_parts.append("✅ Talon list correctly excludes I, O, and Q.")
            else:
                score += 5
                bad_chars = ", ".join(list_check.get('invalid_chars_found'))
                feedback_parts.append(f"❌ Talon list incorrectly included invalid characters: {bad_chars}.")
        else:
            feedback_parts.append("❌ Talon list is missing header declaration.")

        # 4. Modulo 11 CSV Output Verification (40 points)
        csv_dest = os.path.join(temp_dir, "vin_results.csv")
        copy_from_env("C:/tmp/vin_results.csv", csv_dest)
        
        correct_validations = 0
        total_rows = 0
        try:
            with open(csv_dest, 'r') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    if 'vin' not in row or 'is_valid' not in row:
                        continue
                    
                    total_rows += 1
                    gt_valid = verify_modulo_11(row['vin'])
                    # Agent's output might be string 'True'/'False' or bool
                    agent_valid = str(row['is_valid']).strip().lower() in ['true', '1', 't', 'yes']
                    
                    if gt_valid == agent_valid:
                        correct_validations += 1
                        
            if total_rows == 0:
                feedback_parts.append("❌ CSV output is empty or missing columns.")
            else:
                accuracy = correct_validations / total_rows
                if accuracy == 1.0:
                    score += 40
                    feedback_parts.append(f"✅ Modulo 11 check perfect ({correct_validations}/{total_rows} match ground truth).")
                elif accuracy > 0.8:
                    score += 20
                    feedback_parts.append(f"⚠️ Modulo 11 check partial ({correct_validations}/{total_rows} match ground truth).")
                else:
                    feedback_parts.append(f"❌ Modulo 11 check failed (accuracy: {accuracy:.2f}).")
        except Exception as e:
            feedback_parts.append(f"❌ Error verifying CSV output: {e}")

        # 5. VLM Verification of coding activity (30 points)
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            
            prompt = """Look at these screenshots from a Windows session.
            The user is tasked with writing Python code and Talon configuration files for a VIN validator.
            1. Can you see a code editor (like VS Code, Notepad++, or Notepad)?
            2. Can you see Python or Talon code being written/edited?
            
            Respond with JSON:
            {"editor_visible": true/false, "code_edited": true/false}
            """
            
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('editor_visible') and parsed.get('code_edited'):
                    score += 30
                    feedback_parts.append("✅ VLM confirmed code editing workflow.")
                else:
                    feedback_parts.append("❌ VLM could not confirm code editing workflow.")
            else:
                feedback_parts.append("⚠️ VLM verification skipped due to error.")

        # Determine pass/fail
        key_criteria_met = (total_rows > 0) and (accuracy > 0.9)
        passed = score >= 70 and key_criteria_met

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }