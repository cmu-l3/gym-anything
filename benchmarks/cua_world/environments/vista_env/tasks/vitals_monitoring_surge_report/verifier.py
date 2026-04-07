#!/usr/bin/env python3
"""
Verifier for Vitals Monitoring Surge Report task in VistA.

Scoring (100 points):
- VistA container running: 10 points
- Output file exists and created during task session: 20 points
- Output file has substantial content (>150 chars): 10 points
- File contains the #1 patient's name (most vitals): 30 points
- File contains 2nd and 3rd patients' names: 15 points
- File mentions total vital count (correct order of magnitude): 15 points

Pass threshold: 60 points
"""

import os
import logging
from collections import Counter

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

OUTPUT_FILE = "/home/ga/Desktop/vitals_monitoring_report.txt"


def _query_vista(exec_capture, m_command):
    """Execute M/MUMPS code in VistA and return stdout."""
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
    """Return patient name from ^DPT(DFN,0) piece 1."""
    raw = _query_vista(exec_capture, f'W $P($G(^DPT({dfn},0)),"^",1)')
    return raw.strip()


def verify_vitals_monitoring_surge_report(traj, env_info, task_info):
    """
    Verify the agent produced a vitals monitoring surge report identifying
    the top 5 patients by vital sign recording frequency from ^GMR(120.5).
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
    # Read output file
    # ================================================================
    file_content = exec_capture(f"cat {OUTPUT_FILE} 2>/dev/null") or ""
    file_content_lower = file_content.lower()

    # ================================================================
    # Criterion 3: File has substantial content (10 points)
    # ================================================================
    if len(file_content.strip()) > 150:
        score += 10
        subscores['has_content'] = True
        feedback_parts.append(f"File has substantial content ({len(file_content.strip())} chars)")
    else:
        subscores['has_content'] = False
        feedback_parts.append("File content too short")

    # ================================================================
    # Compute ground truth: vital count per patient from ^GMR(120.5)
    # ^GMR(120.5,IEN,0) zero-node piece 1 = patient DFN
    # ================================================================
    logger.info("Computing vital sign counts from ^GMR(120.5)...")
    raw_vitals = _query_vista(
        exec_capture,
        'S IEN=0 F  S IEN=$O(^GMR(120.5,IEN)) Q:IEN=""  S DFN=$P($G(^GMR(120.5,IEN,0)),"^",1) I +DFN>0  W DFN,";"'
    )

    if not raw_vitals:
        logger.warning("No vitals data returned from ^GMR(120.5)")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | No vitals data in ^GMR(120.5)",
            "subscores": subscores
        }

    dfn_entries = [x.strip() for x in raw_vitals.split(';') if x.strip().isdigit()]
    counts = Counter(dfn_entries)
    total_vitals = len(dfn_entries)

    logger.info(f"Total vital entries: {total_vitals}, unique patients: {len(counts)}")

    top5 = counts.most_common(5)
    logger.info(f"Top 5 patients by vital count: {top5}")

    top5_info = []
    for dfn_str, vital_count in top5:
        name = _get_patient_name(exec_capture, dfn_str)
        top5_info.append((dfn_str, name, vital_count))
        logger.info(f"DFN={dfn_str} name='{name}' vital_count={vital_count}")

    # ================================================================
    # Criterion 4: File contains #1 patient name (30 points)
    # ================================================================
    if top5_info and top5_info[0][1]:
        top1_name = top5_info[0][1].lower()
        name_parts = [p.strip().lower() for p in top1_name.replace(',', ' ').split() if len(p.strip()) > 2]
        found_top1 = any(part in file_content_lower for part in name_parts) if name_parts else False

        if found_top1:
            score += 30
            subscores['top1_patient_found'] = True
            feedback_parts.append(f"Top patient '{top5_info[0][1]}' identified correctly")
        else:
            subscores['top1_patient_found'] = False
            feedback_parts.append(f"Top patient '{top5_info[0][1]}' not found in file")
    else:
        subscores['top1_patient_found'] = False
        feedback_parts.append("Could not determine top patient from database")

    # ================================================================
    # Criterion 5: File contains 2nd and 3rd patients' names (15 points)
    # ================================================================
    found_others = 0
    for dfn_str, name, _ in top5_info[1:3]:
        if name:
            name_parts = [p.strip().lower() for p in name.replace(',', ' ').split() if len(p.strip()) > 2]
            if name_parts and any(part in file_content_lower for part in name_parts):
                found_others += 1

    if found_others >= 2:
        score += 15
        subscores['other_patients_found'] = True
        feedback_parts.append("2nd and 3rd top patients also identified")
    elif found_others == 1:
        score += 8
        subscores['other_patients_found'] = 'partial'
        feedback_parts.append("One of 2nd/3rd top patients identified")
    else:
        subscores['other_patients_found'] = False
        feedback_parts.append("2nd and 3rd top patients not found in file")

    # ================================================================
    # Criterion 6: File mentions total vital count (15 points)
    # Accepts within 10% of actual total OR mentions the right order of magnitude
    # ================================================================
    total_str = str(total_vitals)
    # Check if total appears directly or a close number does
    found_total = total_str in file_content
    if not found_total:
        # Accept any number within ±10% of actual total
        for word in file_content.split():
            cleaned = ''.join(c for c in word if c.isdigit())
            if cleaned.isdigit():
                reported = int(cleaned)
                if total_vitals > 0 and abs(reported - total_vitals) / total_vitals <= 0.1:
                    found_total = True
                    break

    if found_total:
        score += 15
        subscores['total_count_mentioned'] = True
        feedback_parts.append(f"Total vital count (~{total_vitals}) mentioned accurately")
    else:
        subscores['total_count_mentioned'] = False
        feedback_parts.append(f"Total vital count ({total_vitals}) not found in file")

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
            "total_vital_entries": total_vitals,
            "top5_patients": [
                {"dfn": info[0], "name": info[1], "vital_count": info[2]}
                for info in top5_info
            ]
        }
    }
