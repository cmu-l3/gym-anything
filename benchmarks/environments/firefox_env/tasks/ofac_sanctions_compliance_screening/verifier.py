#!/usr/bin/env python3
"""
Verifier for OFAC Sanctions Compliance Screening Task
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ofac_sanctions_compliance_screening(traj, env_info, task_info):
    """
    Verifies the OFAC sanctions screening task.
    
    Scoring Criteria (100 points total):
    1. Compliance Audit File (10 pts): Exists, is fresh, and is valid JSON.
    2. Entity: Mahan Air (15 pts): Identified as Sanctioned/SDN + Valid Program (IRAN/SDGT etc).
    3. Entity: Rosoboronexport (15 pts): Identified as Sanctioned/SSI + Valid Program (UKRAINE/RUSSIA etc).
    4. Entity: Lazarus Group (15 pts): Identified as Sanctioned/SDN + Valid Program (CYBER/DPRK etc).
    5. Entity: Mozilla Corporation (15 pts): Identified as Clear/Safe.
    6. Browser State (30 pts): 
       - Bookmark folder 'Compliance Tools' exists (15 pts)
       - History shows visit to OFAC tool (15 pts)
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    # Retrieve result JSON from the container
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp_file:
        local_result_path = tmp_file.name

    try:
        copy_from_env("/tmp/task_result.json", local_result_path)
        with open(local_result_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result data: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result data."}
    finally:
        if os.path.exists(local_result_path):
            os.remove(local_result_path)

    # 2. Initialize Scoring
    score = 0
    feedback = []
    
    # Metadata for validation
    metadata = task_info.get("metadata", {})
    expected_results = metadata.get("expected_results", {
        "Mahan Air": {"status": "Sanctioned", "program_keywords": ["IRAN", "SDGT"]},
        "Rosoboronexport": {"status": "Sanctioned", "program_keywords": ["UKRAINE", "RUSSIA", "SSI"]},
        "Mozilla Corporation": {"status": "Clear"},
        "Lazarus Group": {"status": "Sanctioned", "program_keywords": ["CYBER", "DPRK", "KOREA"]}
    })

    # 3. Check File Existence & Validity (10 pts)
    file_content = result_data.get("file_content", {})
    if result_data.get("file_exists") and result_data.get("file_fresh"):
        if "error" not in file_content:
            score += 10
            feedback.append("Report file created successfully and is valid JSON.")
        else:
            feedback.append("Report file exists but contains invalid JSON.")
            # We can't proceed with content checks if JSON is invalid
            return {"passed": False, "score": score, "feedback": "\n".join(feedback)}
    else:
        feedback.append("Report file not found or not created during this task.")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # 4. Check Content (60 pts total)
    results_json = file_content.get("results", {})
    
    # Helper for case-insensitive check
    def check_status(entity_name, expected_status):
        # Find the entity key in the user's JSON (case-insensitive match)
        user_key = next((k for k in results_json.keys() if entity_name.lower() in k.lower()), None)
        if not user_key:
            return False, f"Entity '{entity_name}' not found in report."
        
        user_entry = results_json[user_key]
        user_status = str(user_entry.get("status", "")).lower()
        
        # Check if status matches expected (Sanctioned vs Clear)
        is_sanctioned = "sanctioned" in user_status or "sdn" in user_status or "block" in user_status
        should_be_sanctioned = expected_status == "Sanctioned"
        
        if should_be_sanctioned and is_sanctioned:
            return True, user_entry
        elif not should_be_sanctioned and ("clear" in user_status or "safe" in user_status or "no" in user_status or "none" in user_status):
            return True, user_entry
        
        return False, f"Incorrect status for '{entity_name}'. Expected {expected_status}, got '{user_status}'."

    # Validate Entities
    for entity, criteria in expected_results.items():
        success, info = check_status(entity, criteria["status"])
        
        if success:
            # If it's a sanctioned entity, check the program code
            if criteria["status"] == "Sanctioned":
                user_program = str(info.get("program", "")).upper()
                keywords = criteria.get("program_keywords", [])
                
                # Loose matching: if any keyword is in the user's program string
                if any(k in user_program for k in keywords):
                    score += 15
                    feedback.append(f"Correctly identified {entity} ({user_program}).")
                else:
                    # Partial credit for getting status right but program wrong
                    score += 10
                    feedback.append(f"Correct status for {entity}, but program code '{user_program}' missing expected keywords {keywords}.")
            else:
                # For "Clear" entities, status is enough
                score += 15
                feedback.append(f"Correctly identified {entity} as Clear.")
        else:
            feedback.append(info)

    # 5. Check Browser State (30 pts)
    # Bookmarks
    if result_data.get("bookmark_folder_found", False):
        score += 15
        feedback.append("Bookmark folder 'Compliance Tools' found.")
    else:
        feedback.append("Bookmark folder 'Compliance Tools' NOT found.")

    # History
    if result_data.get("history_visits", 0) > 0:
        score += 15
        feedback.append("History shows visit to OFAC search tool.")
    else:
        feedback.append("No history of visiting OFAC search tool found.")

    # 6. Final Result
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }