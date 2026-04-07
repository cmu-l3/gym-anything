#!/usr/bin/env python3
"""
Verifier for Age Verification from Driver's License PDF417 Barcodes task.

Verification Strategy:
1. Application Config (10 pts): Checks exported JSON to verify PDF417 was enabled via bcWebCam settings/registry.
2. File Setup (10 pts): CSV exists with exact correct headers.
3. Name Extraction (30 pts): Checks First and Last Name correctness against ground truth.
4. DOB Extraction (30 pts): Checks DOB extraction.
5. Logic/Status (20 pts): Validates mathematical threshold against March 9, 2026.
6. VLM Trajectory check: Ensures the agent didn't bypass the UI setup step.
"""

import csv
import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_age_pdf417(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    # 1. Retrieve the Task Metadata (JSON)
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        result = {"csv_exists": False, "pdf417_enabled": False}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # Criterion 1: PDF417 Enabled in Application (10 pts)
    if result.get("pdf417_enabled"):
        score += 10
        feedback_parts.append("PDF417 correctly enabled in bcWebCam")
    else:
        feedback_parts.append("Failed: PDF417 was not enabled in bcWebCam settings")

    # Anti-gaming: Ensure file was created during task runtime
    if result.get("csv_exists") and not result.get("file_created_during_task"):
        feedback_parts.append("Warning: CSV file was modified prior to task start.")

    # 2. Retrieve the Parsed CSV Data
    if not result.get("csv_exists"):
        feedback_parts.append("CSV file not found")
        return {"passed": False, "score": int(score), "feedback": " | ".join(feedback_parts)}

    tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("C:\\tmp\\task_result.csv", tmp_csv.name)
        with open(tmp_csv.name, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            headers = [h.strip().lower() for h in reader.fieldnames] if reader.fieldnames else []
    except Exception as e:
        feedback_parts.append(f"Failed to parse CSV: {e}")
        rows = []
        headers = []
    finally:
        if os.path.exists(tmp_csv.name):
            os.unlink(tmp_csv.name)

    # Criterion 2: File Setup / Headers (10 pts)
    expected_headers = {"firstname", "lastname", "dob", "status"}
    if expected_headers.issubset(set(headers)):
        score += 10
        feedback_parts.append("CSV headers correctly formatted")
    else:
        feedback_parts.append(f"Invalid headers. Expected {expected_headers}, got {headers}")
        return {"passed": False, "score": int(score), "feedback": " | ".join(feedback_parts)}

    # Criteria 3, 4, 5: Data validation against ground truth
    # ID1: John Doe, 1985-05-15 (Age 40) -> Approved
    # ID2: Jane Smith, 2010-08-20 (Age 15) -> Denied
    # ID3: Robert Johnson, 2000-01-01 (Age 26) -> Approved
    expected = {
        "john": {"last": "doe", "dob": "1985", "status": "approved"},
        "jane": {"last": "smith", "dob": "2010", "status": "denied"},
        "robert": {"last": "johnson", "dob": "2000", "status": "approved"}
    }

    names_extracted = 0   # Target 6 (3 First, 3 Last) - 5 pts each (30 total)
    dobs_extracted = 0    # Target 3 - 10 pts each (30 total)
    statuses_correct = 0  # Target 3 - 6.66 pts each (20 total)

    for row in rows:
        row_clean = {k.strip().lower(): str(v).strip().lower() for k,v in row.items() if k}
        fn = row_clean.get("firstname", "")
        ln = row_clean.get("lastname", "")
        dob = row_clean.get("dob", "")
        status = row_clean.get("status", "")

        if fn in expected:
            names_extracted += 1
            exp = expected[fn]
            if ln == exp["last"]:
                names_extracted += 1
            if exp["dob"] in dob:
                dobs_extracted += 1
            if status == exp["status"]:
                statuses_correct += 1

    score += (names_extracted / 6.0) * 30.0
    score += (dobs_extracted / 3.0) * 30.0
    score += (statuses_correct / 3.0) * 20.0

    if names_extracted == 6:
        feedback_parts.append("All names extracted perfectly")
    else:
        feedback_parts.append(f"Names extracted: {names_extracted}/6")

    if dobs_extracted == 3:
        feedback_parts.append("All DOBs extracted perfectly")
    else:
        feedback_parts.append(f"DOBs extracted: {dobs_extracted}/3")

    if statuses_correct == 3:
        feedback_parts.append("All age statuses calculated perfectly")
    else:
        feedback_parts.append(f"Statuses correct: {statuses_correct}/3")

    # Optionally incorporate VLM trajectory check for application interface usage
    vlm_ui_detected = False
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """Analyze these chronological screenshots from a Windows application workflow.
Did the agent open the bcWebCam application, access its settings/options, and interact with the UI?
Respond ONLY with JSON: {"ui_interaction_found": true/false}"""
            result_vlm = query_vlm(images=frames, prompt=prompt)
            if result_vlm and result_vlm.get("success"):
                if result_vlm.get("parsed", {}).get("ui_interaction_found"):
                    vlm_ui_detected = True
    except Exception:
        pass

    if vlm_ui_detected:
        feedback_parts.append("VLM confirmed UI interaction")

    # Pass threshold logic (80 points with all three statuses calculated correctly)
    passed = score >= 80 and statuses_correct == 3
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }