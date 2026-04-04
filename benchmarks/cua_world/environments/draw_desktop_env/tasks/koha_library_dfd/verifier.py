#!/usr/bin/env python3
"""
Verifier for koha_library_dfd task.
"""

import json
import os
import tempfile

def verify_koha_library_dfd(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # 1. File checks (15 pts)
    if result.get("file_exists") and result.get("file_modified"):
        score += 5
        feedback.append("Draw.io file saved.")
    else:
        feedback.append("Draw.io file missing or not saved.")
        
    if result.get("png_exists") and result.get("png_size", 0) > 5000:
        score += 10
        feedback.append("PNG export successful.")
    else:
        feedback.append("PNG export missing or too small.")

    analysis = result.get("analysis", {})
    pages = analysis.get("pages", [])
    
    # 2. Page Structure (10 pts)
    if len(pages) >= 2:
        score += 10
        feedback.append(f"Created {len(pages)} pages.")
    elif len(pages) == 1:
        score += 5
        feedback.append("Only 1 page created (expected 2).")
    else:
        feedback.append("No diagram pages found.")

    # 3. Content Analysis (75 pts)
    # Entities (10 pts)
    entities_found = len(set(analysis.get("entities_found", [])))
    # We look for ~8 keywords, but some are multi-word splits. 
    # Mapped groups: Patron, Librarian, Pub/Vendor, OCLC/WorldCat, SIP2/Kiosk
    # Simple count check
    if entities_found >= 4:
        score += 10
        feedback.append(f"Entities found: {entities_found} keywords.")
    elif entities_found > 0:
        score += 5
        feedback.append(f"Few entities found: {entities_found}.")

    # Processes (15 pts)
    procs_found = len(set(analysis.get("processes_found", [])))
    if procs_found >= 6:
        score += 15
        feedback.append(f"Processes found: {procs_found} (Excellent).")
    elif procs_found >= 4:
        score += 8
        feedback.append(f"Processes found: {procs_found} (Good).")
    else:
        feedback.append(f"Processes missing: only {procs_found} found.")

    # Data Stores (15 pts)
    stores_found = len(set(analysis.get("stores_found", [])))
    if stores_found >= 4:
        score += 15
        feedback.append(f"Data stores found: {stores_found}.")
    elif stores_found >= 2:
        score += 8
        feedback.append(f"Few data stores found: {stores_found}.")

    # Connectivity / Edges (15 pts)
    total_edges = analysis.get("total_edges", 0)
    if total_edges >= 20:
        score += 15
        feedback.append(f"Connectivity good ({total_edges} edges).")
    elif total_edges >= 10:
        score += 8
        feedback.append(f"Connectivity partial ({total_edges} edges).")
    elif total_edges >= 5:
        score += 4
        feedback.append(f"Connectivity sparse ({total_edges} edges).")
    else:
        feedback.append("Diagram lacks connections.")

    # Notation / Labels (10 pts)
    if analysis.get("dfd_labels_found"):
        score += 10
        feedback.append("DFD numbering (P1/D1) detected.")
    
    # Pass threshold
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }