#!/usr/bin/env python3
"""
Verifier for compliance_traceability_matrix task.

Requirements:
1. File /home/ga/Documents/NeuroStim_SRS_v2.odt must exist.
2. Must contain a new section "Verification Traceability Matrix".
3. Must contain a table with specific data.
4. CRITICAL: The Requirement column must use Active Cross-References (XML tags <text:reference-ref> or <text:bookmark-ref>), NOT plain text.

Scoring:
- File Exists & Modified: 10 pts
- Matrix Section Created: 10 pts
- Table Exists: 10 pts
- Data Content Accuracy (VP IDs present): 20 pts
- Active Cross-References: 50 pts (10 pts per correct link, max 5)
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compliance_traceability_matrix(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Check (10 pts)
    if result.get("file_exists") and result.get("file_modified"):
        score += 10
        feedback.append("File created and modified successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "Target file not found or not modified."}

    analysis = result.get("analysis", {})
    
    # 2. Section Check (10 pts)
    if analysis.get("has_matrix_section"):
        score += 10
        feedback.append("Matrix section header found.")
    else:
        feedback.append("Matrix section header missing.")

    # 3. Table Check (10 pts)
    if analysis.get("table_found"):
        score += 10
        feedback.append("Traceability table found.")
    else:
        feedback.append("Traceability table missing.")

    # 4. Data Content Check (20 pts)
    # We expected 5 rows of data. 
    data_matches = analysis.get("data_matches", 0)
    # We give 4 points per data row match, max 20
    data_score = min(20, data_matches * 4)
    score += data_score
    feedback.append(f"Data content verification: {data_matches}/5 rows matched (+{data_score} pts).")

    # 5. Active Cross-References (50 pts)
    # This is the core difficulty. 10 pts per valid reference.
    refs_found = analysis.get("valid_cross_refs", 0)
    ref_score = min(50, refs_found * 10)
    score += ref_score
    
    if refs_found == 0:
        feedback.append("NO ACTIVE CROSS-REFERENCES FOUND. Did you just type the text? You must use Insert > Cross-reference.")
    else:
        feedback.append(f"Active cross-references found: {refs_found}/5 (+{ref_score} pts).")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }