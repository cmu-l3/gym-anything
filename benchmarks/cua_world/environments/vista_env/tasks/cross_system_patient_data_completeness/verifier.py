#!/usr/bin/env python3
"""
Verifier for Cross-System Patient Data Completeness task in VistA.

The task requires finding the patient with the highest composite data volume:
  composite = rx_count*3 + vital_count + allergy_count*2 + problem_count*2

Scoring (100 points):
- VistA container running: 10 points
- Output file exists and created during task session: 20 points
- Output file has substantial content (>300 chars): 10 points
- File identifies the correct top-composite patient by name: 35 points
- File covers data from 3+ clinical domains (with numbers): 15 points
- File contains a clinical narrative (3+ sentences): 10 points

Pass threshold: 60 points
"""

import os
import logging
from collections import Counter, defaultdict

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

OUTPUT_FILE = "/home/ga/Desktop/patient_profile.txt"

# Domain keywords to check for multi-domain coverage (procedure vocabulary)
DOMAIN_KEYWORDS = {
    'pharmacy': ['prescription', 'medication', 'rx', 'drug', 'pharmacy', 'ps(55)', 'outpatient'],
    'vitals': ['vital', 'blood pressure', 'temperature', 'pulse', 'gmr', '120.5', 'weight', 'height'],
    'allergies': ['allerg', 'adverse reaction', 'gmrd', '120.8', 'reaction'],
    'problems': ['problem', 'diagnosis', 'diagnos', 'aupnprob', 'condition', 'disease'],
}


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


def verify_cross_system_patient_data_completeness(traj, env_info, task_info):
    """
    Verify the agent produced a comprehensive patient profile for the patient
    with the highest composite data score across four VistA clinical globals.
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
    if len(file_content.strip()) > 300:
        score += 10
        subscores['has_content'] = True
        feedback_parts.append(f"File has substantial content ({len(file_content.strip())} chars)")
    else:
        subscores['has_content'] = False
        feedback_parts.append("File content too short for comprehensive profile")

    # ================================================================
    # Compute ground truth: composite scores across all 4 globals
    # ================================================================
    logger.info("Computing composite scores from all 4 clinical globals...")

    # Pharmacy counts (^PS(55,"P"))
    rx_raw = _query_vista(
        exec_capture,
        'S DFN=0 F  S DFN=$O(^PS(55,DFN)) Q:DFN=""  S K=0 F  S K=$O(^PS(55,DFN,"P",K)) Q:K=""  W DFN,";"'
    )
    rx_counts = _count_per_dfn(rx_raw)

    # Vital counts (^GMR(120.5))
    vital_raw = _query_vista(
        exec_capture,
        'S IEN=0 F  S IEN=$O(^GMR(120.5,IEN)) Q:IEN=""  S DFN=$P($G(^GMR(120.5,IEN,0)),"^",1) I +DFN>0  W DFN,";"'
    )
    vital_counts = _count_per_dfn(vital_raw)

    # Allergy counts (^GMRD(120.8))
    allergy_raw = _query_vista(
        exec_capture,
        'S IEN=0 F  S IEN=$O(^GMRD(120.8,IEN)) Q:IEN=""  S DFN=$P($G(^GMRD(120.8,IEN,0)),"^",1) I +DFN>0  W DFN,";"'
    )
    allergy_counts = _count_per_dfn(allergy_raw)

    # Problem counts (^AUPNPROB)
    prob_raw = _query_vista(
        exec_capture,
        'S IEN=0 F  S IEN=$O(^AUPNPROB(IEN)) Q:IEN=""  S DFN=$P($G(^AUPNPROB(IEN,0)),"^",1) I +DFN>0  W DFN,";"'
    )
    prob_counts = _count_per_dfn(prob_raw)

    # Get all unique DFNs across all globals
    all_dfns = set(rx_counts.keys()) | set(vital_counts.keys()) | set(allergy_counts.keys()) | set(prob_counts.keys())

    if not all_dfns:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | No clinical data found across globals",
            "subscores": subscores
        }

    # Compute composite score per patient: rx*3 + vitals + allergies*2 + problems*2
    composite_scores = {}
    for dfn_str in all_dfns:
        rx = rx_counts.get(dfn_str, 0)
        vitals = vital_counts.get(dfn_str, 0)
        allergies = allergy_counts.get(dfn_str, 0)
        problems = prob_counts.get(dfn_str, 0)
        composite_scores[dfn_str] = (rx * 3) + vitals + (allergies * 2) + (problems * 2)

    # Find top patient
    top_dfn_str = max(composite_scores, key=lambda d: composite_scores[d])
    top_score = composite_scores[top_dfn_str]
    top_name = _get_patient_name(exec_capture, top_dfn_str)

    logger.info(f"Top composite patient: DFN={top_dfn_str} name='{top_name}' composite={top_score}")
    logger.info(f"  rx={rx_counts.get(top_dfn_str,0)} vitals={vital_counts.get(top_dfn_str,0)} "
                f"allergies={allergy_counts.get(top_dfn_str,0)} problems={prob_counts.get(top_dfn_str,0)}")

    # ================================================================
    # Criterion 4: File identifies the correct top-composite patient (35 pts)
    # ================================================================
    found_top = False
    if top_name:
        name_parts = [p.strip().lower() for p in top_name.replace(',', ' ').split() if len(p.strip()) > 2]
        found_top = any(part in file_content_lower for part in name_parts) if name_parts else False

    # Also accept if the DFN appears in the file
    if not found_top and top_dfn_str in file_content:
        found_top = True

    if found_top:
        score += 35
        subscores['top_patient_found'] = True
        feedback_parts.append(f"Correct top-composite patient '{top_name}' (DFN={top_dfn_str}) identified")
    else:
        subscores['top_patient_found'] = False
        feedback_parts.append(f"Top-composite patient '{top_name}' (DFN={top_dfn_str}) not found in file")

    # ================================================================
    # Criterion 5: File covers data from 3+ clinical domains (15 points)
    # ================================================================
    domains_covered = 0
    for domain, keywords in DOMAIN_KEYWORDS.items():
        if any(kw in file_content_lower for kw in keywords):
            domains_covered += 1

    if domains_covered >= 3:
        score += 15
        subscores['multi_domain_coverage'] = domains_covered
        feedback_parts.append(f"File covers {domains_covered}/4 clinical domains")
    elif domains_covered == 2:
        score += 8
        subscores['multi_domain_coverage'] = domains_covered
        feedback_parts.append(f"File covers only {domains_covered}/4 clinical domains")
    else:
        subscores['multi_domain_coverage'] = domains_covered
        feedback_parts.append(f"File covers only {domains_covered}/4 clinical domains (need 3+)")

    # ================================================================
    # Criterion 6: File contains a clinical narrative (10 points)
    # Check for at least 3 sentences and narrative-style text
    # ================================================================
    sentences = [s.strip() for s in file_content.replace('\n', ' ').split('.') if len(s.strip()) > 20]
    if len(sentences) >= 3:
        score += 10
        subscores['has_narrative'] = True
        feedback_parts.append(f"File contains clinical narrative ({len(sentences)} sentences)")
    else:
        subscores['has_narrative'] = False
        feedback_parts.append(f"File lacks clinical narrative (found {len(sentences)} sentences, need 3+)")

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
            "top_patient": {
                "dfn": top_dfn_str,
                "name": top_name,
                "composite_score": top_score,
                "rx_count": rx_counts.get(top_dfn_str, 0),
                "vital_count": vital_counts.get(top_dfn_str, 0),
                "allergy_count": allergy_counts.get(top_dfn_str, 0),
                "problem_count": prob_counts.get(top_dfn_str, 0),
            },
            "domains_covered_in_file": domains_covered,
            "total_patients_with_data": len(all_dfns),
        }
    }
