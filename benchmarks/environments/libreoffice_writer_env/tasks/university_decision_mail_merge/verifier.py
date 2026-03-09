#!/usr/bin/env python3
"""
Verifier for University Decision Mail Merge task.
Checks if the agent correctly used conditional fields to generate different text
for admitted vs denied applicants.
"""

import json
import os
import csv
import logging
import tempfile
import shutil
from typing import Dict, List, Any

# Import ODF parsing (odt is a zip of XMLs, odfpy handles it)
try:
    from odf import opendocument, text as odf_text
    ODF_AVAILABLE = True
except ImportError:
    ODF_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_odt_text(file_path: str) -> str:
    """Extract all text from an ODT file."""
    if not ODF_AVAILABLE:
        return ""
    try:
        doc = opendocument.load(file_path)
        all_text = []
        for element in doc.getElementsByType(odf_text.P):
            all_text.append(str(element))
        return "\n".join(all_text)
    except Exception as e:
        logger.error(f"Failed to parse ODT: {e}")
        return ""

def verify_university_decision_mail_merge(traj, env_info, task_info):
    """
    Verify the mail merge output.
    
    Criteria:
    1. Output file exists and is valid ODT.
    2. File modification time is valid.
    3. Contains ~25 letters (checked via name occurrences).
    4. "Admit" applicants have "Congratulations" + Program Name.
    5. "Deny" applicants have "regret to inform you" + NO "Congratulations".
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    csv_path_remote = metadata.get('csv_path', '/home/ga/Documents/applicants.csv')
    output_path_remote = metadata.get('output_path', '/home/ga/Documents/decision_letters.odt')
    
    score = 0
    feedback_parts = []
    
    # 1. Setup temp directory
    temp_dir = tempfile.mkdtemp()
    local_odt = os.path.join(temp_dir, "output.odt")
    local_csv = os.path.join(temp_dir, "data.csv")
    local_result_json = os.path.join(temp_dir, "result.json")
    
    try:
        # 2. Retrieve files
        try:
            copy_from_env(output_path_remote, local_odt)
            copy_from_env(csv_path_remote, local_csv)
            copy_from_env("/tmp/task_result.json", local_result_json)
            
            with open(local_result_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to retrieve task files: {e}"
            }

        # 3. Check file existence and creation time
        if not result_data.get('output_exists', False):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Output file decision_letters.odt not found."
            }
        
        score += 10 # File exists
        
        if result_data.get('file_created_during_task', False):
            score += 10 # Created during task
            feedback_parts.append("File created during task.")
        else:
            feedback_parts.append("Warning: File timestamp indicates it wasn't modified during task.")

        # 4. Load ground truth data
        applicants = []
        try:
            with open(local_csv, 'r') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    applicants.append(row)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Error reading ground truth CSV: {e}"}

        # 5. Parse ODT content
        if not ODF_AVAILABLE:
            return {"passed": False, "score": score, "feedback": "Verification failed: odfpy library missing."}
            
        doc_text = get_odt_text(local_odt)
        if not doc_text:
            return {"passed": False, "score": score, "feedback": "Output file is empty or invalid ODT."}

        # 6. Verify Content Logic
        # We search the large text blob. Since it's a single file merge, all letters are in sequence.
        # We will split by a common anchor, e.g., "Dear", or just search for presence of patterns.
        # A more robust way is to verify that for every applicant, their specific logic exists.
        
        correct_admit = 0
        correct_deny = 0
        total_records = len(applicants)
        
        missing_names = []
        logic_errors = []
        
        for app in applicants:
            name = f"{app['FirstName']} {app['LastName']}"
            program = app['Program']
            decision = app['Decision']
            
            # Simple check: Does the document contain the Name?
            if name not in doc_text:
                missing_names.append(name)
                continue
            
            # Contextual check is hard on a flat string, but we can check if the specific combination exists
            # For Admit: "Dear [Name]... Congratulations... [Program]" should appear relatively close?
            # Or just check global counts if strict proximity is too hard to verify on flat text.
            # A strict proximity check:
            # Find the index of the name, look ahead.
            
            name_indices = [i for i in range(len(doc_text)) if doc_text.startswith(name, i)]
            
            # Check if ANY occurrence of the name is followed by the correct decision logic
            found_logic = False
            for idx in name_indices:
                # Look at the text chunk following the name (e.g., next 1000 chars)
                chunk = doc_text[idx:idx+2000]
                
                if decision == "Admit":
                    has_congrats = "Congratulations" in chunk
                    has_program = program in chunk
                    if has_congrats and has_program:
                        found_logic = True
                        break
                else: # Deny
                    has_regret = "regret to inform you" in chunk
                    has_congrats = "Congratulations" in chunk
                    if has_regret and not has_congrats:
                        found_logic = True
                        break
            
            if found_logic:
                if decision == "Admit":
                    correct_admit += 1
                else:
                    correct_deny += 1
            else:
                logic_errors.append(f"{name} ({decision})")

        # Scoring Logic
        # Max points remaining: 80
        
        # 1. Names present (Data Connection)
        names_found = total_records - len(missing_names)
        percent_names = names_found / total_records
        score += int(30 * percent_names)
        
        if percent_names < 0.8:
            feedback_parts.append(f"Only {names_found}/{total_records} applicant names found.")
        else:
            feedback_parts.append(f"Found {names_found}/{total_records} applicant names.")

        # 2. Logic correctness
        # Calculate Logic Score separately
        admit_records = [a for a in applicants if a['Decision'] == 'Admit']
        deny_records = [a for a in applicants if a['Decision'] == 'Deny']
        
        if admit_records:
            score += int(25 * (correct_admit / len(admit_records)))
        else:
            score += 25 # No admits to check
            
        if deny_records:
            score += int(25 * (correct_deny / len(deny_records)))
        else:
            score += 25 # No denies to check

        if logic_errors:
            # Show first 3 errors
            feedback_parts.append(f"Logic errors in {len(logic_errors)} records (e.g., {', '.join(logic_errors[:3])}).")
            if len(logic_errors) > 5:
                 feedback_parts.append("Check conditional text logic: Admit should show 'Congratulations' and Program; Deny should show 'regret'.")
        else:
            feedback_parts.append("Conditional logic appears correct for all found records.")

        return {
            "passed": score >= 80,
            "score": score,
            "feedback": " ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)