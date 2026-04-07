#!/usr/bin/env python3
"""
Verifier for Polypharmacy Risk Stratification task in VistA.

Scoring (100 points):
- VistA container running: 10 points
- Output file exists and created during task session: 20 points
- Output file has substantial content (>100 chars): 10 points
- File contains the #1 patient's name (most prescriptions): 30 points
- File contains the #2 and #3 patients' names: 20 points
- File mentions accurate prescription count for #1 patient: 10 points

Pass threshold: 60 points
"""

import os
import logging
from collections import Counter

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

OUTPUT_FILE = "/home/ga/Desktop/polypharmacy_report.txt"


def _query_vista(exec_capture, m_command):
    """Execute M/MUMPS code in VistA and return stdout.

    Escapes for double-quoted bash -c context so inner single-quoted
    M code is passed correctly to yottadb.
    """
    escaped = (
        m_command
        .replace('\\', '\\\\')
        .replace('"', '\\"')
        .replace('$', '\\$')
        .replace('`', '\\`')
    )
    cmd = (
        f"docker exec -u vehu vista-vehu bash -c "
        f"\"source /home/vehu/etc/env && yottadb -run %XCMD '{escaped}'\""
    )
    try:
        result = exec_capture(cmd)
        return result.strip() if result else ""
    except Exception as e:
        logger.error(f"VistA query failed: {e}")
        return ""


def _get_patient_name(exec_capture, dfn):
    """Return patient name (piece 1 of ^DPT(DFN,0)) for a given DFN."""
    raw = _query_vista(exec_capture, f'W $P($G(^DPT({dfn},0)),"^",1)')
    return raw.strip()


def verify_polypharmacy_risk_stratification(traj, env_info, task_info):
    """
    Verify that the agent produced a polypharmacy risk report with the
    correct top-3 patients ranked by outpatient prescription count.
    """
    exec_capture = env_info.get('exec_capture')
    if not exec_capture:
        return {"passed": False, "score": 0, "feedback": "exec_capture not available"}

    score = 0
    feedback_parts = []
    subscores = {}

    # ================================================================
    # Criterion 1: VistA container running (10 points)
    # ================================================================
    container_check = exec_capture(
        "docker ps --filter 'name=vista-vehu' --filter 'status=running' -q 2>/dev/null"
    )
    if container_check and container_check.strip():
        score += 10
        subscores['vista_running'] = True
        feedback_parts.append("VistA container running")
    else:
        subscores['vista_running'] = False
        feedback_parts.append("VistA container not running")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts), "subscores": subscores}

    # ================================================================
    # Criterion 2: Output file exists and was created during task (20 pts)
    # ================================================================
    task_start_raw = exec_capture("cat /tmp/task_start_timestamp 2>/dev/null || echo 0")
    try:
        task_start = int(task_start_raw.strip())
    except (ValueError, AttributeError):
        task_start = 0

    mtime_raw = exec_capture(f"stat -c %Y {OUTPUT_FILE} 2>/dev/null || echo 0")
    try:
        mtime = int(mtime_raw.strip())
    except (ValueError, AttributeError):
        mtime = 0

    file_exists = mtime > 0
    file_is_new = (task_start > 0) and (mtime > task_start)

    if file_exists and file_is_new:
        score += 20
        subscores['output_file_new'] = True
        feedback_parts.append("Output file created during task session")
    elif file_exists:
        score += 5
        subscores['output_file_new'] = False
        feedback_parts.append("Output file exists but may predate task start")
    else:
        subscores['output_file_new'] = False
        feedback_parts.append("Output file not found")

    if not file_exists:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # ================================================================
    # Read output file content
    # ================================================================
    file_content = exec_capture(f"cat {OUTPUT_FILE} 2>/dev/null") or ""
    file_content_lower = file_content.lower()

    # ================================================================
    # Criterion 3: File has substantial content (10 points)
    # ================================================================
    if len(file_content.strip()) > 100:
        score += 10
        subscores['has_content'] = True
        feedback_parts.append(f"File has content ({len(file_content.strip())} chars)")
    else:
        subscores['has_content'] = False
        feedback_parts.append("File content too short or empty")

    # ================================================================
    # Compute ground truth: prescription counts per patient from ^PS(55)
    # ================================================================
    logger.info("Computing prescription counts from ^PS(55)...")
    # Iterate all patients with pharmacy records; for each, iterate "P" (outpatient Rx)
    # Write DFN for each prescription — count occurrences in Python
    raw_counts = _query_vista(
        exec_capture,
        'S DFN=0 F  S DFN=$O(^PS(55,DFN)) Q:DFN=""  S K=0 F  S K=$O(^PS(55,DFN,"P",K)) Q:K=""  W DFN,";"'
    )

    if not raw_counts:
        logger.warning("No prescription data returned from ^PS(55)")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | No pharmacy data in ^PS(55)",
            "subscores": subscores
        }

    dfn_entries = [x.strip() for x in raw_counts.split(';') if x.strip().isdigit()]
    counts = Counter(dfn_entries)

    if len(counts) < 3:
        logger.warning(f"Only {len(counts)} patients with prescriptions found")

    top3 = counts.most_common(3)
    logger.info(f"Top 3 patients by Rx count: {top3}")

    # Get patient names for top 3
    top3_names = []
    top3_info = []
    for dfn_str, rx_count in top3:
        name = _get_patient_name(exec_capture, dfn_str)
        top3_names.append(name)
        top3_info.append((dfn_str, name, rx_count))
        logger.info(f"DFN={dfn_str} name='{name}' rx_count={rx_count}")

    # ================================================================
    # Criterion 4: File contains #1 patient name (30 points)
    # ================================================================
    if top3_names and top3_names[0]:
        top1_name = top3_names[0].lower()
        # Check name parts (handle LAST,FIRST format)
        name_parts = [p.strip().lower() for p in top1_name.replace(',', ' ').split() if len(p.strip()) > 2]
        found_top1 = any(part in file_content_lower for part in name_parts) if name_parts else False

        if found_top1:
            score += 30
            subscores['top1_patient_found'] = True
            feedback_parts.append(f"Top patient '{top3_names[0]}' identified correctly")
        else:
            subscores['top1_patient_found'] = False
            feedback_parts.append(f"Top patient '{top3_names[0]}' not found in file")
    else:
        subscores['top1_patient_found'] = False
        feedback_parts.append("Could not determine top patient from database")

    # ================================================================
    # Criterion 5: File contains #2 and #3 patient names (20 points)
    # ================================================================
    found_others = 0
    for i, name in enumerate(top3_names[1:], start=2):
        if name:
            name_parts = [p.strip().lower() for p in name.replace(',', ' ').split() if len(p.strip()) > 2]
            if name_parts and any(part in file_content_lower for part in name_parts):
                found_others += 1

    if found_others >= 2:
        score += 20
        subscores['other_patients_found'] = True
        feedback_parts.append("Top 2nd and 3rd patients also identified")
    elif found_others == 1:
        score += 10
        subscores['other_patients_found'] = 'partial'
        feedback_parts.append("One of 2nd/3rd top patients identified")
    else:
        subscores['other_patients_found'] = False
        feedback_parts.append("2nd and 3rd top patients not found in file")

    # ================================================================
    # Criterion 6: File mentions accurate prescription count for top patient (10 points)
    # ================================================================
    if top3_info:
        top1_count = top3_info[0][2]
        # Check if the exact count appears in the file
        if str(top1_count) in file_content:
            score += 10
            subscores['count_accurate'] = True
            feedback_parts.append(f"Prescription count {top1_count} for top patient is accurate")
        else:
            subscores['count_accurate'] = False
            feedback_parts.append(f"Prescription count {top1_count} not found in file")

    # ================================================================
    # Final determination
    # ================================================================
    passed = (
        score >= 60 and
        subscores.get('vista_running', False) and
        subscores.get('output_file_new', False) and
        subscores.get('top1_patient_found', False)
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "ground_truth": {
            "top3_patients": [
                {"dfn": info[0], "name": info[1], "rx_count": info[2]}
                for info in top3_info
            ]
        }
    }
