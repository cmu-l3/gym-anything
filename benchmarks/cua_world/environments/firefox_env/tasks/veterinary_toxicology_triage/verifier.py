#!/usr/bin/env python3
"""
Verifier for Veterinary Toxicology Triage Task
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_veterinary_toxicology_triage(traj, env_info, task_info):
    """
    Verifies the veterinary triage task based on:
    1. Firefox History (ASPCA visits)
    2. Bookmarks (Folder + Count)
    3. JSON Report (Existence + Content Accuracy)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: History Evidence (20 pts) ---
    history_count = result.get('aspca_history_count', 0)
    if history_count >= 4:
        score += 20
        feedback.append(f"History Check: Excellent research detected ({history_count} ASPCA pages visited).")
    elif history_count >= 1:
        score += 10
        feedback.append(f"History Check: Basic research detected ({history_count} ASPCA pages visited).")
    else:
        feedback.append("History Check: No visits to aspca.org detected.")

    # --- Criterion 2: Bookmarks (15 pts) ---
    folder_exists = result.get('vet_folder_exists', False)
    bookmark_count = result.get('vet_bookmark_count', 0)
    
    if folder_exists:
        if bookmark_count >= 3:
            score += 15
            feedback.append(f"Bookmark Check: 'Vet Tox Resources' folder found with {bookmark_count} items.")
        else:
            score += 10
            feedback.append(f"Bookmark Check: Folder exists but contains only {bookmark_count}/3 items.")
    else:
        feedback.append("Bookmark Check: 'Vet Tox Resources' folder not found.")

    # --- Criterion 3: Report Structure (15 pts) ---
    report_exists = result.get('report_exists', False)
    report_fresh = result.get('report_fresh', False)
    valid_json = result.get('report_valid_json', False)
    data = result.get('report_data', {})

    if report_exists and report_fresh and valid_json:
        score += 15
        feedback.append("Report Check: File exists, is fresh, and is valid JSON.")
    elif report_exists:
        feedback.append("Report Check: File exists but is either stale or invalid JSON.")
    else:
        feedback.append("Report Check: Output file not found.")

    # --- Criterion 4: Content Accuracy (50 pts total) ---
    # We normalize keys to lower case to be lenient
    data_normalized = {k.lower(): v for k, v in data.items()}
    
    # 4a. Easter Lily (15 pts) - MUST be Severe/Kidney
    # Keys might be 'easter lily', 'easter_lily', 'lily', etc.
    lily_key = next((k for k in data_normalized if 'lily' in k), None)
    if lily_key:
        entry = data_normalized[lily_key]
        tox = str(entry.get('toxicity_level', '')).lower()
        organ = str(entry.get('target_organ', '')).lower() + str(entry.get('pathology', '')).lower() + str(entry.get('clinical_signs', '')).lower()
        
        if 'severe' in tox or 'fatal' in tox or 'high' in tox:
            if 'kidney' in organ or 'renal' in organ:
                score += 15
                feedback.append("Accuracy: Easter Lily correctly identified as Severe/Renal.")
            else:
                score += 7
                feedback.append("Accuracy: Easter Lily identified as Severe, but missed 'Kidney/Renal' specificity.")
        else:
            feedback.append(f"Accuracy FAIL: Easter Lily marked as '{tox}' (Expected: Severe).")
    else:
        feedback.append("Accuracy: Easter Lily entry missing.")

    # 4b. Poinsettia (15 pts) - MUST be Mild/Irritant (Anti-Hallucination)
    poin_key = next((k for k in data_normalized if 'poinsettia' in k), None)
    if poin_key:
        entry = data_normalized[poin_key]
        tox = str(entry.get('toxicity_level', '')).lower()
        
        # Accept 'mild', 'low', 'irritant', 'non-toxic'
        if any(x in tox for x in ['mild', 'low', 'irritant', 'non-toxic', 'none']):
            score += 15
            feedback.append("Accuracy: Poinsettia correctly identified as Mild/Irritant.")
        elif 'severe' in tox or 'fatal' in tox or 'high' in tox:
            feedback.append("Accuracy FAIL: Poinsettia incorrectly marked as Severe (Common myth/Hallucination).")
        else:
            score += 5 # Partial for presence
            feedback.append(f"Accuracy: Poinsettia marked as '{tox}' (Expected: Mild).")
    else:
        feedback.append("Accuracy: Poinsettia entry missing.")

    # 4c. Onion (10 pts) - Blood/Anemia
    onion_key = next((k for k in data_normalized if 'onion' in k), None)
    if onion_key:
        entry = data_normalized[onion_key]
        text = str(entry).lower()
        if 'blood' in text or 'anemia' in text or 'hemolytic' in text or 'heinz' in text:
            score += 10
            feedback.append("Accuracy: Onion correctly identified with blood/anemia risks.")
        else:
            score += 5
            feedback.append("Accuracy: Onion entry found but missed specific blood/anemia pathology.")
    else:
        feedback.append("Accuracy: Onion entry missing.")

    # 4d. Dieffenbachia (10 pts) - Oral/Irritation
    dief_key = next((k for k in data_normalized if 'dieffenbachia' in k or 'dumb' in k), None)
    if dief_key:
        entry = data_normalized[dief_key]
        text = str(entry).lower()
        if 'oral' in text or 'mouth' in text or 'tongue' in text or 'irritat' in text or 'burn' in text:
            score += 10
            feedback.append("Accuracy: Dieffenbachia correctly identified with oral irritation.")
        else:
            score += 5
            feedback.append("Accuracy: Dieffenbachia entry found but missed oral irritation specifics.")
    else:
        feedback.append("Accuracy: Dieffenbachia entry missing.")

    # Final Check
    passed = (score >= 65)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }