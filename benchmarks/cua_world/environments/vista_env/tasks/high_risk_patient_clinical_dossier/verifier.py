#!/usr/bin/env python3
"""
Verifier for High-Risk Patient Clinical Dossier task in VistA.

The task requires:
1. Computing risk scores across all patients in both ^PS(55) and ^GMR(120.8)
2. Identifying the single highest-risk patient
3. Compiling a dossier with resolved pointer values from 7 globals

Scoring (100 points):
- VistA container running: 10 points
- Output file exists and created during task session: 15 points
- Output file has substantial content (>500 chars): 5 points
- File identifies the correct highest-risk patient by name: 25 points
- File contains resolved pointer values (service/eligibility names): 15 points
- File contains allergy reactant names: 10 points
- File contains prescription drug names: 10 points
- File contains contraindication analysis section: 10 points

Pass threshold: 60 points

NOTE: This is a stub verifier. Full programmatic verification is deferred
to VLM checklist-based verification.
"""

import logging
from collections import Counter

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

OUTPUT_FILE = "/home/ga/Desktop/patient_risk_dossier.txt"


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


def verify_high_risk_patient_clinical_dossier(traj, env_info, task_info):
    """
    Verify the agent produced a comprehensive clinical dossier for the
    highest medication-allergy risk patient in VistA.
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
        return {
            "passed": False, "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # ================================================================
    # Criterion 2: Output file exists and was created during task (15 pts)
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
        score += 15
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
            "passed": False, "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # ================================================================
    # Read output file
    # ================================================================
    file_content = exec_capture(f"cat {OUTPUT_FILE} 2>/dev/null") or ""
    file_content_lower = file_content.lower()

    # ================================================================
    # Criterion 3: File has substantial content (5 points)
    # ================================================================
    if len(file_content.strip()) > 500:
        score += 5
        subscores['has_content'] = True
        feedback_parts.append(f"File has substantial content ({len(file_content.strip())} chars)")
    else:
        subscores['has_content'] = False
        feedback_parts.append("File content too short for comprehensive dossier")

    # ================================================================
    # Compute ground truth: find highest-risk patient
    # Risk score = (prescription_count * 2) + (allergy_count * 3)
    # ================================================================
    logger.info("Computing risk scores from ^PS(55) and ^GMR(120.8)...")

    # Prescription counts per patient from ^PS(55)
    raw_rx = _query_vista(
        exec_capture,
        'S DFN=0 F  S DFN=$O(^PS(55,DFN)) Q:DFN=""  S K=0 F  S K=$O(^PS(55,DFN,"P",K)) Q:K=""  W DFN,";"'
    )
    rx_counts = _count_per_dfn(raw_rx)

    # Allergy counts per patient from ^GMR(120.8)
    raw_allergies = _query_vista(
        exec_capture,
        'S IEN=0 F  S IEN=$O(^GMRD(120.8,IEN)) Q:IEN=""  S DFN=$P($G(^GMRD(120.8,IEN,0)),"^",1) I +DFN>0  W DFN,";"'
    )
    allergy_counts = _count_per_dfn(raw_allergies)

    if not rx_counts or not allergy_counts:
        feedback_parts.append("Could not retrieve clinical data from VistA for ground truth")
        return {
            "passed": False, "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # Intersection: patients in BOTH systems
    intersection_dfns = set(rx_counts.keys()) & set(allergy_counts.keys())

    if not intersection_dfns:
        feedback_parts.append("No patients found in both pharmacy and allergy systems")
        return {
            "passed": False, "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # Compute risk scores
    risk_scores = {
        dfn: (rx_counts.get(dfn, 0) * 2) + (allergy_counts.get(dfn, 0) * 3)
        for dfn in intersection_dfns
    }
    top_dfn = max(risk_scores, key=lambda d: risk_scores[d])
    top_risk = risk_scores[top_dfn]
    top_name = _get_patient_name(exec_capture, top_dfn)

    logger.info(
        f"Top risk patient: DFN={top_dfn} name='{top_name}' "
        f"risk_score={top_risk} "
        f"(rx={rx_counts.get(top_dfn, 0)}, allergies={allergy_counts.get(top_dfn, 0)})"
    )

    # ================================================================
    # Criterion 4: File identifies the correct top-risk patient (25 pts)
    # ================================================================
    found_top = False
    if top_name:
        name_parts = [
            p.strip().lower()
            for p in top_name.replace(',', ' ').split()
            if len(p.strip()) > 2
        ]
        found_top = any(part in file_content_lower for part in name_parts) if name_parts else False

    if not found_top and top_dfn in file_content:
        found_top = True

    if found_top:
        score += 25
        subscores['top_patient_found'] = True
        feedback_parts.append(
            f"Top risk patient '{top_name}' (DFN={top_dfn}) identified"
        )
    else:
        subscores['top_patient_found'] = False
        feedback_parts.append(
            f"Top risk patient '{top_name}' (DFN={top_dfn}) not found in file"
        )

    # ================================================================
    # Criterion 5: File contains resolved pointer values (15 pts)
    # Check for human-readable names from ^DIC(21), ^DIC(8), ^DIC(31)
    # ================================================================
    pointer_keywords = [
        'period of service', 'service', 'eligibility',
        'world war', 'vietnam', 'korea', 'persian gulf', 'post-',
        'sc less', 'sc greater', 'nsc', 'service connected',
        'disability', 'disabilities', 'rated'
    ]
    pointer_matches = [kw for kw in pointer_keywords if kw in file_content_lower]

    if len(pointer_matches) >= 3:
        score += 15
        subscores['pointer_resolution'] = True
        feedback_parts.append("Resolved pointer values present in file")
    elif len(pointer_matches) >= 1:
        score += 7
        subscores['pointer_resolution'] = 'partial'
        feedback_parts.append("Some pointer resolution present")
    else:
        subscores['pointer_resolution'] = False
        feedback_parts.append("No resolved pointer values found")

    # ================================================================
    # Criterion 6: File contains allergy reactant names (10 pts)
    # ================================================================
    allergy_keywords = [
        'allerg', 'reactant', 'penicillin', 'sulfa', 'aspirin',
        'codeine', 'morphine', 'ibuprofen', 'nkda', 'drug allergy',
        'adverse', 'reaction'
    ]
    allergy_matches = [kw for kw in allergy_keywords if kw in file_content_lower]

    if len(allergy_matches) >= 2:
        score += 10
        subscores['allergy_data'] = True
        feedback_parts.append("Allergy data present in file")
    else:
        subscores['allergy_data'] = False
        feedback_parts.append("Allergy reactant data not found")

    # ================================================================
    # Criterion 7: File contains prescription drug names (10 pts)
    # ================================================================
    rx_keywords = [
        'prescription', 'drug name', 'medication',
        'tablet', 'capsule', 'mg', 'tab', 'cap',
        'ointment', 'cream', 'solution', 'inject'
    ]
    rx_matches = [kw for kw in rx_keywords if kw in file_content_lower]

    if len(rx_matches) >= 2:
        score += 10
        subscores['prescription_data'] = True
        feedback_parts.append("Prescription data present in file")
    else:
        subscores['prescription_data'] = False
        feedback_parts.append("Prescription drug names not found")

    # ================================================================
    # Criterion 8: File contains contraindication analysis (10 pts)
    # ================================================================
    contra_keywords = [
        'contraindic', 'flag', 'match', 'conflict',
        'allergy.*drug', 'drug.*allergy', 'substring',
        'screen', 'interaction', 'warning', 'alert',
        'no contraindic', 'no match', 'none found', 'no flag'
    ]
    contra_matches = [kw for kw in contra_keywords if kw in file_content_lower]

    if len(contra_matches) >= 1:
        score += 10
        subscores['contraindication_analysis'] = True
        feedback_parts.append("Contraindication analysis present")
    else:
        subscores['contraindication_analysis'] = False
        feedback_parts.append("Contraindication analysis not found")

    # ================================================================
    # Final determination
    # ================================================================
    passed = (
        score >= 60
        and subscores.get('vista_running', False)
        and subscores.get('output_file_new', False)
        and subscores.get('top_patient_found', False)
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "ground_truth": {
            "intersection_count": len(intersection_dfns),
            "top_risk_patient": {
                "dfn": top_dfn,
                "name": top_name,
                "risk_score": top_risk,
                "prescription_count": rx_counts.get(top_dfn, 0),
                "allergy_count": allergy_counts.get(top_dfn, 0),
            }
        }
    }
