#!/usr/bin/env python3
import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hospital_dfd_decomposition(traj, env_info, task_info):
    """
    Verifies the Hospital DFD Decomposition task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    level0_procs = set(metadata.get('level0_processes', ["1.0", "2.0", "3.0", "4.0", "5.0"]))
    level1_procs = set(metadata.get('level1_processes', ["4.1", "4.2", "4.3", "4.4"]))
    
    # Copy result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. Check File Modification (Anti-Gaming)
    if result.get("file_modified"):
        score += 5
    else:
        feedback.append("File was not modified.")
    
    # 2. Check Page Count
    total_pages = result.get("total_pages", 0)
    pages = result.get("pages", [])
    if total_pages >= 3:
        score += 20
        feedback.append(f"Page count correct ({total_pages}).")
    else:
        feedback.append(f"Insufficient pages ({total_pages}/3).")

    # 3. Analyze Level-0 DFD (Page 2)
    # Note: Page index 1 is the second page
    level0_found = False
    if len(pages) > 1:
        page2 = pages[1]
        labels = " ".join(page2.get("labels", [])).lower()
        
        # Check for processes 1.0 - 5.0
        found_procs = 0
        for proc in level0_procs:
            if proc in labels:
                found_procs += 1
        
        if found_procs >= 4:
            score += 15
            feedback.append(f"Level-0 Processes found ({found_procs}/5).")
            level0_found = True
        else:
            feedback.append(f"Missing Level-0 processes (found {found_procs}/5).")

        # Check for Data Stores D1-D5
        found_stores = 0
        for i in range(1, 6):
            if f"d{i}" in labels or f"D{i}" in labels:
                found_stores += 1
        if found_stores >= 4:
            score += 10
            feedback.append("Level-0 Data Stores found.")
        
        # Check edges
        if len(page2.get("edges", [])) >= 8:
            score += 10
            feedback.append("Level-0 Edges sufficient.")
        else:
            feedback.append("Level-0 Edges insufficient.")

    # 4. Analyze Level-1 DFD (Page 3)
    # Note: Page index 2 is the third page
    level1_found = False
    if len(pages) > 2:
        page3 = pages[2]
        labels = " ".join(page3.get("labels", [])).lower()
        
        # Check for sub-processes 4.1 - 4.4
        found_subs = 0
        for proc in level1_procs:
            if proc in labels:
                found_subs += 1
        
        if found_subs >= 3:
            score += 10
            feedback.append(f"Level-1 Sub-processes found ({found_subs}/4).")
            level1_found = True
        else:
            feedback.append(f"Missing Level-1 sub-processes (found {found_subs}/4).")

        # Check for Billing Data Stores (D4.1, D4.2, etc)
        if "d4.1" in labels or "d4.2" in labels:
             score += 5
             feedback.append("Level-1 Data Stores found.")
        
        # Check edges
        if len(page3.get("edges", [])) >= 5:
            score += 5
            feedback.append("Level-1 Edges sufficient.")

    # 5. Check SVG Export
    if result.get("svg_exists") and result.get("svg_size", 0) > 1000:
        score += 20
        feedback.append("SVG Export successful.")
    else:
        feedback.append("SVG Export missing or empty.")

    # Final Pass Determination
    # Must have 3 pages, found core processes in both levels, and file modified
    passed = (score >= 60) and (total_pages >= 3) and level0_found and level1_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }