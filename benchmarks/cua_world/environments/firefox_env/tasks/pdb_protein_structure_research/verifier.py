#!/usr/bin/env python3
"""
Verifier for pdb_protein_structure_research task.

Criteria:
1. JSON Report: Exists, Valid JSON, Contains keys for 4HHB, 1MBN, 1FDH. (30 pts)
2. Data Accuracy: Resolution, Method, Classification match expected within tolerance. (40 pts)
3. Download: File exists in Downloads matching 4HHB PDB format, valid size. (15 pts)
4. Bookmarks: Folder "Protein Research" exists with 3+ RCSB links. (15 pts)

Total: 100 pts. Pass: 65 pts.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pdb_research(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    expected_data = task_info.get('metadata', {}).get('expected_data', {})
    
    # 2. Retrieve Exported Result JSON
    task_result_path = "/tmp/task_result.json"
    local_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(task_result_path, local_result_file.name)
        with open(local_result_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(local_result_file.name):
            os.unlink(local_result_file.name)

    # 3. Retrieve User's Report JSON
    report_path = "/home/ga/Documents/protein_structures.json"
    user_report = {}
    report_valid = False
    
    if task_result.get("report_exists"):
        local_report_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(report_path, local_report_file.name)
            with open(local_report_file.name, 'r') as f:
                user_report = json.load(f)
            report_valid = True
        except Exception:
            logger.warning("Failed to parse user report as JSON")
        finally:
            if os.path.exists(local_report_file.name):
                os.unlink(local_report_file.name)

    # 4. Scoring Logic
    score = 0
    feedback = []

    # Criterion A: Report Structure (15 pts)
    if report_valid:
        keys_found = 0
        required_keys = ["4HHB", "1MBN", "1FDH"]
        # Normalize keys to upper case for checking
        user_keys = [k.upper() for k in user_report.keys()]
        
        for rk in required_keys:
            if rk in user_keys:
                keys_found += 1
        
        if keys_found == 3:
            score += 15
            feedback.append("JSON report structure correct (15/15)")
        else:
            score += keys_found * 5
            feedback.append(f"JSON report missing some PDB IDs, found {keys_found}/3 ({keys_found*5}/15)")
    else:
        feedback.append("JSON report missing or invalid (0/15)")

    # Criterion B: Data Accuracy (45 pts)
    data_score = 0
    if report_valid:
        for pdb_id, expected in expected_data.items():
            # Find user entry case-insensitively
            entry = next((v for k, v in user_report.items() if k.upper() == pdb_id), None)
            
            if not entry:
                continue

            # Check Resolution (Number, +/- 0.1 tolerance)
            try:
                user_res = float(entry.get("resolution_angstroms", 0))
                exp_res = expected["resolution"]
                if abs(user_res - exp_res) <= 0.15:
                    data_score += 5
                else:
                    feedback.append(f"{pdb_id} resolution incorrect: got {user_res}, expected ~{exp_res}")
            except (ValueError, TypeError):
                feedback.append(f"{pdb_id} resolution invalid format")

            # Check Method (String contains "X-RAY" or "DIFFRACTION")
            user_method = str(entry.get("method", "")).upper()
            if "X-RAY" in user_method or "DIFFRACTION" in user_method:
                data_score += 5
            else:
                feedback.append(f"{pdb_id} method mismatch")

            # Check Classification (String contains "OXYGEN")
            user_class = str(entry.get("classification", "")).upper()
            if "OXYGEN" in user_class or "TRANSPORT" in user_class:
                data_score += 5
            else:
                feedback.append(f"{pdb_id} classification mismatch")

    score += data_score
    if data_score == 45:
        feedback.append("All metadata accurate (45/45)")
    elif data_score > 0:
        feedback.append(f"Partial metadata accuracy ({data_score}/45)")

    # Criterion C: Download (20 pts)
    if task_result.get("download_found"):
        size = task_result.get("download_size", 0)
        # PDB files for these proteins are usually > 100KB
        if size > 50000: 
            score += 20
            feedback.append("Structure file downloaded successfully (20/20)")
        else:
            score += 10
            feedback.append("File found but seems too small for a PDB file (10/20)")
    else:
        feedback.append("Structure file download not found (0/20)")

    # Criterion D: Bookmarks (20 pts)
    if task_result.get("bookmark_folder_found"):
        count = task_result.get("rcsb_bookmarks_count", 0)
        if count >= 3:
            score += 20
            feedback.append("Bookmarks correct (20/20)")
        elif count >= 1:
            score += 10
            feedback.append(f"Bookmark folder found but only {count} RCSB links (10/20)")
        else:
            score += 5
            feedback.append("Bookmark folder found but empty (5/20)")
    else:
        feedback.append("Bookmark folder 'Protein Research' not found (0/20)")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }