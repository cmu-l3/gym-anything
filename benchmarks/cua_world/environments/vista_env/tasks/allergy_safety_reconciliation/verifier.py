#!/usr/bin/env python3
"""
Verifier for Allergy Safety Reconciliation task in VistA.

The task requires cross-referencing the allergy file and pharmacy file to find
patients present in BOTH, then ranking by combined allergy + prescription burden.

Scoring (100 points):
- VistA container running: 10 points
- Output file exists and created during task session: 20 points
- Output file has substantial content (>200 chars): 10 points
- File identifies the top combined-burden patient by name: 35 points
- File contains a plausible intersection patient count: 15 points
- File contains risk designation language: 10 points

Pass threshold: 60 points
"""

import logging
from collections import Counter

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

OUTPUT_FILE = "/home/ga/Desktop/allergy_safety_report.txt"

RISK_KEYWORDS = [
    'risk', 'high risk', 'medium risk', 'low risk', 'reconcil', 'flag',
    'alert', 'warning', 'contraindic', 'safety', 'review', 'action'
]


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


def _count_per_dfn(raw_output):
    """Parse semicolon-separated DFN list into a Counter of DFN -> count."""
    entries = [x.strip() for x in raw_output.split(';') if x.strip().isdigit()]
    return Counter(entries)


def verify_allergy_safety_reconciliation(traj, env_info, task_info):
    """
    Verify the agent cross-referenced allergy and pharmacy records to identify
    patients appearing in both systems and ranked them by combined burden.
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
    if len(file_content.strip()) > 200:
        score += 10
        subscores['has_content'] = True
        feedback_parts.append(f"File has substantial content ({len(file_content.strip())} chars)")
    else:
        subscores['has_content'] = False
        feedback_parts.append("File content too short")

    # ================================================================
    # Compute ground truth: cross-reference allergy and pharmacy data
    # ================================================================
    logger.info("Computing allergy counts from ^GMRD(120.8)...")
    raw_allergies = _query_vista(
        exec_capture,
        'S IEN=0 F  S IEN=$O(^GMRD(120.8,IEN)) Q:IEN=""  S DFN=$P($G(^GMRD(120.8,IEN,0)),"^",1) I +DFN>0  W DFN,";"'
    )
    allergy_counts = _count_per_dfn(raw_allergies)

    logger.info("Computing prescription counts from ^PS(55)...")
    raw_rx = _query_vista(
        exec_capture,
        'S DFN=0 F  S DFN=$O(^PS(55,DFN)) Q:DFN=""  S K=0 F  S K=$O(^PS(55,DFN,"P",K)) Q:K=""  W DFN,";"'
    )
    rx_counts = _count_per_dfn(raw_rx)

    if not allergy_counts or not rx_counts:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | Could not retrieve clinical data from VistA",
            "subscores": subscores
        }

    # Compute intersection
    allergy_dfns = set(allergy_counts.keys())
    rx_dfns = set(rx_counts.keys())
    intersection_dfns = allergy_dfns & rx_dfns

    logger.info(f"Allergy patients: {len(allergy_dfns)}, Rx patients: {len(rx_dfns)}, "
                f"Intersection: {len(intersection_dfns)}")

    if not intersection_dfns:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | No patients found in both allergy and pharmacy records",
            "subscores": subscores
        }

    # Compute combined score = allergy_count + rx_count for intersection patients
    combined_scores = {
        dfn_str: allergy_counts.get(dfn_str, 0) + rx_counts.get(dfn_str, 0)
        for dfn_str in intersection_dfns
    }
    top_dfn = max(combined_scores, key=lambda d: combined_scores[d])
    top_combined = combined_scores[top_dfn]
    top_name = _get_patient_name(exec_capture, top_dfn)

    logger.info(f"Top combined-risk patient: DFN={top_dfn} name='{top_name}' "
                f"combined={top_combined} "
                f"(allergies={allergy_counts.get(top_dfn, 0)}, rx={rx_counts.get(top_dfn, 0)})")

    # ================================================================
    # Criterion 4: File identifies top combined-risk patient (35 pts)
    # ================================================================
    found_top = False
    if top_name:
        name_parts = [p.strip().lower() for p in top_name.replace(',', ' ').split() if len(p.strip()) > 2]
        found_top = any(part in file_content_lower for part in name_parts) if name_parts else False

    if not found_top and top_dfn in file_content:
        found_top = True

    if found_top:
        score += 35
        subscores['top_patient_found'] = True
        feedback_parts.append(f"Top combined-risk patient '{top_name}' (DFN={top_dfn}) identified")
    else:
        subscores['top_patient_found'] = False
        feedback_parts.append(f"Top combined-risk patient '{top_name}' (DFN={top_dfn}) not found in file")

    # ================================================================
    # Criterion 5: File contains plausible intersection count (15 pts)
    # Check if the file mentions a number close to the true intersection size
    # ================================================================
    true_count = len(intersection_dfns)
    count_str = str(true_count)

    # Accept if exact count is mentioned, or if count within ±5 of true value appears
    count_found = count_str in file_content
    if not count_found:
        # Check nearby counts (agent may have gotten slightly different result)
        for nearby in range(max(1, true_count - 5), true_count + 6):
            if str(nearby) in file_content:
                count_found = True
                break

    if count_found:
        score += 15
        subscores['intersection_count_present'] = True
        feedback_parts.append(f"Intersection count ({true_count} patients in both systems) reflected in file")
    else:
        subscores['intersection_count_present'] = False
        feedback_parts.append(f"True intersection count ({true_count} patients) not found in file")

    # ================================================================
    # Criterion 6: File contains risk designation language (10 pts)
    # ================================================================
    found_risk = [kw for kw in RISK_KEYWORDS if kw in file_content_lower]
    if len(found_risk) >= 2:
        score += 10
        subscores['risk_language_present'] = True
        feedback_parts.append(f"Risk designation language present")
    else:
        subscores['risk_language_present'] = False
        feedback_parts.append("Risk designation language not found in file")

    # ================================================================
    # Final determination
    # ================================================================
    passed = (
        score >= 60 and
        subscores.get('vista_running', False) and
        subscores.get('output_file_new', False) and
        subscores.get('top_patient_found', False)
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "ground_truth": {
            "intersection_count": true_count,
            "top_combined_patient": {
                "dfn": top_dfn,
                "name": top_name,
                "combined_score": top_combined,
                "allergy_count": allergy_counts.get(top_dfn, 0),
                "rx_count": rx_counts.get(top_dfn, 0),
            }
        }
    }
