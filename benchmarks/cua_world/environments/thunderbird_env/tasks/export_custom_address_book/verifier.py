#!/usr/bin/env python3
"""
Verifier for export_custom_address_book task.

Verification Criteria:
1. CSV File exported successfully (existence & timestamp check) [15 pts]
2. Target Contact 1 (Sarah Jenkins) is in the CSV [20 pts]
3. Target Contact 2 (Marcus Vance) is in the CSV [20 pts]
4. Background contacts (e.g., e.vargas) are NOT in the CSV (Isolation check) [20 pts]
5. Internal TB Address book created [10 pts]
6. VLM Trajectory check confirms workflow [15 pts]
"""

import os
import json
import csv
import tempfile
import logging
from typing import Dict, Any

# Assuming standard gym_anything VLM utilities are available in context
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    pass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent's trajectory for completing an address book export task in Mozilla Thunderbird.

The agent was instructed to:
1. Open the Address Book
2. Create a new Address Book named "TechExpo 2026"
3. Add two contacts (Sarah Jenkins, Marcus Vance)
4. Export ONLY this address book to a CSV file.

Look at the provided trajectory frames (sampled chronologically).
Please assess:
1. ADDRESS_BOOK_OPENED: Is the Thunderbird Address Book interface ever visible?
2. NEW_BOOK_OR_CONTACT: Is there evidence of creating a new list/book or entering the contact details (Sarah Jenkins/Marcus Vance)?
3. EXPORT_DIALOG: Is the "Export Address Book" file save dialog visible in any frame?

Provide your assessment in JSON format:
{
    "address_book_opened": true/false,
    "new_book_or_contact_seen": true/false,
    "export_dialog_seen": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what is visible"
}
"""

def verify_export_custom_address_book(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_1 = metadata.get('target_contact_1_email', 's.jenkins@aerodynamics-corp.com').lower()
    target_2 = metadata.get('target_contact_2_email', 'mvance@vance-industrial.com').lower()
    background_contact = metadata.get('background_contact_email', 'e.vargas@global-logistics.net').lower()

    score = 0
    feedback_parts = []
    
    # 1. Read JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    file_exists = result.get('file_exists', False)
    file_created = result.get('file_created_during_task', False)
    new_abook_created = result.get('new_abook_created', False)

    # Criterion 1: File Existence and Anti-Gaming (15 pts)
    if file_exists and file_created:
        score += 15
        feedback_parts.append("CSV exported during task.")
    elif file_exists:
        score += 5
        feedback_parts.append("CSV exists but timestamp indicates it was not created during task.")
    else:
        feedback_parts.append("Exported CSV file not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2, 3, 4: CSV Parsing
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    found_target_1 = False
    found_target_2 = False
    found_background = False
    
    try:
        copy_from_env("/tmp/techexpo_leads.csv", temp_csv.name)
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read().lower()
            if target_1 in content:
                found_target_1 = True
            if target_2 in content:
                found_target_2 = True
            if background_contact in content:
                found_background = True
    except Exception as e:
        feedback_parts.append(f"Could not parse CSV: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    if found_target_1:
        score += 20
        feedback_parts.append("Contact 1 (Sarah Jenkins) found in CSV.")
    else:
        feedback_parts.append("Contact 1 missing from CSV.")

    if found_target_2:
        score += 20
        feedback_parts.append("Contact 2 (Marcus Vance) found in CSV.")
    else:
        feedback_parts.append("Contact 2 missing from CSV.")

    if not found_background:
        score += 20
        feedback_parts.append("Background contacts excluded (Proper export isolation).")
    else:
        feedback_parts.append("Background contacts found! Exported wrong address book or merged data.")

    # Criterion 5: Internal Thunderbird SQLite check
    if new_abook_created:
        score += 10
        feedback_parts.append("New address book detected in Thunderbird profile.")
    else:
        feedback_parts.append("No new address book database created internally.")

    # Criterion 6: VLM Trajectory Check
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=6)
        vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
        if vlm_result and isinstance(vlm_result, dict) and "parsed" in vlm_result:
            parsed = vlm_result["parsed"]
            if parsed.get("address_book_opened"):
                vlm_score += 5
            if parsed.get("new_book_or_contact_seen"):
                vlm_score += 5
            if parsed.get("export_dialog_seen"):
                vlm_score += 5
            
            score += vlm_score
            feedback_parts.append(f"VLM trajectory visual verification awarded {vlm_score}/15 pts.")
        else:
            feedback_parts.append("VLM verification failed or returned invalid format.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        feedback_parts.append("VLM verification skipped/errored.")

    # Final pass determination
    # Must have created the file, found at least one target, AND excluded background to pass fully
    key_criteria_met = file_created and (found_target_1 or found_target_2) and not found_background
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }