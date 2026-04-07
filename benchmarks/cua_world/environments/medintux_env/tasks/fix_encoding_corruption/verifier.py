#!/usr/bin/env python3
"""
Verifier for fix_encoding_corruption task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_encoding(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Metadata expectations
    expected = task_info.get('metadata', {}).get('expected_fixes', {})
    
    # 1. Check if corrupted patterns remain (30 pts)
    rem_index = result.get('remaining_corrupted_index', 999)
    rem_fchpat = result.get('remaining_corrupted_fchpat', 999)
    
    if rem_index == 0 and rem_fchpat == 0:
        score += 30
        feedback.append("Success: No corrupted characters found in database.")
    else:
        feedback.append(f"Fail: Found {rem_index} corrupted records in Index and {rem_fchpat} in Details.")
        
    # 2. Check individual patients (30 pts - 5 pts each for 6 patients)
    patients = result.get('patients', [])
    correct_patients = 0
    
    # We look for specific correct combinations in the patient list
    # Expected:
    # BERENGER / Léa / Châteauroux
    # LEFEVRE / Hélène / 14 rue des Pêcheurs
    # GONÇALVES / Maria
    # PREVOST / Renée
    # FORTIER / Françoise / Orléans
    # BEAUPRÉ / Thérèse / 3 rue François Rabelais

    def find_patient(nom, prenom):
        for p in patients:
            if p['nom'] == nom and p['prenom'] == prenom:
                return p
        return None

    # Check 1: BERENGER
    p = find_patient("BERENGER", "Léa")
    if p and "Châteauroux" in p['ville']:
        correct_patients += 1
    elif p:
        feedback.append("BERENGER: Found but City wrong/corrupt")
    else:
        feedback.append("BERENGER: Not found with correct name")

    # Check 2: LEFEVRE
    p = find_patient("LEFEVRE", "Hélène")
    if p and "Pêcheurs" in p['adresse']:
        correct_patients += 1
    
    # Check 3: GONÇALVES
    p = find_patient("GONÇALVES", "Maria")
    if p:
        correct_patients += 1
        
    # Check 4: PREVOST
    p = find_patient("PREVOST", "Renée")
    if p:
        correct_patients += 1
        
    # Check 5: FORTIER
    p = find_patient("FORTIER", "Françoise")
    if p and "Orléans" in p['ville']:
        correct_patients += 1
        
    # Check 6: BEAUPRÉ
    p = find_patient("BEAUPRÉ", "Thérèse")
    if p and "François" in p['adresse']:
        correct_patients += 1
        
    score += (correct_patients * 5)
    feedback.append(f"Correctly fixed patients: {correct_patients}/6")

    # 3. Check for deletions (10 pts)
    initial = result.get('initial_count', 0)
    final = result.get('final_count', 0)
    # Final should be equal to initial (we only updated, didn't delete or add)
    if initial > 0 and final >= initial:
        score += 10
        feedback.append("Database integrity maintained (no records deleted).")
    else:
        feedback.append(f"Warning: Record count changed (Initial: {initial}, Final: {final})")

    # 4. Check Report (30 pts)
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', "").lower()
    
    if report_exists:
        score += 10
        feedback.append("Report file created.")
        
        # Check content for keywords
        keywords = ["berenger", "lefevre", "gonçalves", "prevost", "fortier", "beaupré"]
        found_kw = sum(1 for kw in keywords if kw.lower() in report_content)
        
        if found_kw >= 3:
            score += 20
            feedback.append(f"Report content valid (referenced {found_kw} patients).")
        else:
            score += 5
            feedback.append("Report content sparse/missing patient names.")
    else:
        feedback.append("No report file found.")

    passed = (score >= 60) and (rem_index == 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }