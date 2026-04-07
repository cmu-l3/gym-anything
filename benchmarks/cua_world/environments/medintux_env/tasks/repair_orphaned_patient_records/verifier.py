#!/usr/bin/env python3
"""
Verifier for repair_orphaned_patient_records task.
Evaluates the JSON result produced by export_result.sh.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_repair_orphaned_patient_records(traj, env_info, task_info):
    """
    Verifies that the agent correctly repaired 3 orphaned patient records.
    
    Criteria:
    1. DUPONT (GUID1) indexed correctly (Name, Firstname, Type)
    2. BERNARD (GUID3) indexed correctly
    3. MOREAU (GUID5) indexed correctly
    4. No duplicates introduced
    5. Control patients (MARTIN, LEROY) remain intact
    6. Reconciliation report exists and contains correct data
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Check Anti-Gaming (Initial State) ---
    initial_count = int(result.get("initial_index_count", 0))
    if initial_count != 2:
        feedback.append(f"WARNING: Initial index count was {initial_count} (expected 2).")
        # Proceed, but note this anomaly.

    # --- Check Repaired Orphans (15 pts each) ---
    
    # DUPONT
    dupont = result.get("dupont_state", {})
    if dupont.get("exists") and dupont.get("nom") == "DUPONT" and dupont.get("prenom") == "Marie" and dupont.get("type") == "Dossier":
        score += 15
        feedback.append("DUPONT repaired correctly.")
    else:
        feedback.append(f"DUPONT repair failed: {dupont}")

    # BERNARD
    bernard = result.get("bernard_state", {})
    if bernard.get("exists") and bernard.get("nom") == "BERNARD" and bernard.get("prenom") == "Sophie" and bernard.get("type") == "Dossier":
        score += 15
        feedback.append("BERNARD repaired correctly.")
    else:
        feedback.append(f"BERNARD repair failed: {bernard}")

    # MOREAU
    moreau = result.get("moreau_state", {})
    if moreau.get("exists") and moreau.get("nom") == "MOREAU" and moreau.get("prenom") == "Isabelle" and moreau.get("type") == "Dossier":
        score += 15
        feedback.append("MOREAU repaired correctly.")
    else:
        feedback.append(f"MOREAU repair failed: {moreau}")

    # --- Check Integrity (10 pts) ---
    if not result.get("has_duplicates", True):
        score += 10
        feedback.append("No duplicates detected.")
    else:
        feedback.append("Duplicates detected in index.")

    # --- Check Controls (10 pts) ---
    martin = result.get("martin_state", {})
    leroy = result.get("leroy_state", {})
    if martin.get("exists") and leroy.get("exists"):
        score += 10
        feedback.append("Control patients intact.")
    else:
        feedback.append("Control patients damaged.")

    # --- Check Report (35 pts total) ---
    report = result.get("report", {})
    report_content = report.get("content_preview", "").upper()
    
    if report.get("exists", False) and report.get("size", 0) > 20:
        score += 10
        feedback.append("Report file exists.")
        
        # Check content (15 pts)
        names_found = 0
        if "DUPONT" in report_content: names_found += 1
        if "BERNARD" in report_content: names_found += 1
        if "MOREAU" in report_content: names_found += 1
        
        if names_found == 3:
            score += 15
            feedback.append("Report lists all 3 patients.")
        else:
            score += (names_found * 5)
            feedback.append(f"Report lists {names_found}/3 patients.")

        # Check summary count (10 pts)
        if report.get("has_summary_count"):
            score += 10
            feedback.append("Report includes summary count.")
    else:
        feedback.append("Report file missing or empty.")

    passed = score >= 60 and (names_found == 3 if 'names_found' in locals() else False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }