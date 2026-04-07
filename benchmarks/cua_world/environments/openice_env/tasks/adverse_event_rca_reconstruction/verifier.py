#!/usr/bin/env python3
"""
Verifier for Adverse Event RCA Reconstruction task.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_adverse_event_rca(traj, env_info, task_info):
    """
    Verify the reconstruction of the adverse event and the RCA report.
    
    Scoring Criteria (100 points):
    - Device: Pulse Oximeter created (15 pts)
    - Device: Multiparameter Monitor created (15 pts)
    - App: Vital Signs app launched (15 pts)
    - Interaction: Detail view opened / Windows increased (5 pts)
    - Report: File exists & valid metadata (15 pts)
    - Report Content: Incident/Hypotension context (8 pts)
    - Report Content: Root cause/Transport context (7 pts)
    - Report Content: Monitoring gap described (5 pts)
    - Report Content: Corrective actions/Protocol (8 pts)
    - Report Content: OpenICE reference (4 pts)
    - Report Structure: Paragraphs present (3 pts)
    
    Gate: If < 1 device created AND no report -> Score 0.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load result
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    subscores = {}
    
    # 1. Gate Check
    pulse_ox = result.get('pulse_ox_created', False)
    multiparam = result.get('multiparam_created', False)
    report_exists = result.get('report_exists', False)
    window_increase = result.get('window_increase', 0)
    
    if not pulse_ox and not multiparam and not report_exists and window_increase < 2:
         return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAIL: No devices created and no report written.",
            "subscores": {}
        }

    # 2. Device Creation (30 pts)
    if pulse_ox:
        score += 15
        subscores['pulse_ox'] = 15
        feedback_parts.append("Pulse Oximeter created")
    else:
        feedback_parts.append("Pulse Oximeter MISSING")

    if multiparam:
        score += 15
        subscores['multiparam'] = 15
        feedback_parts.append("Multiparameter Monitor created")
    else:
        feedback_parts.append("Multiparameter Monitor MISSING")

    # 3. Clinical App Launch (15 pts)
    if result.get('app_launched', False):
        score += 15
        subscores['app'] = 15
        feedback_parts.append("Vital Signs app launched")
    else:
        feedback_parts.append("Vital Signs app NOT detected")

    # 4. Interaction/Detail View (5 pts)
    # If window count increased by at least 3 (2 devices + 1 app), 
    # anything more suggests detail views or extensive interaction
    if window_increase >= 4: 
        score += 5
        subscores['interaction'] = 5
        feedback_parts.append("Extensive interaction detected")
    elif window_increase >= 1:
        score += 2
        feedback_parts.append("Some interaction detected")
    
    # 5. Report Metadata (15 pts)
    task_start = result.get('task_start', 0)
    report_mtime = result.get('report_mtime', 0)
    report_size = result.get('report_size', 0)
    
    if report_exists:
        if report_mtime > task_start and report_size > 100:
            score += 15
            subscores['report_meta'] = 15
            feedback_parts.append("Report exists and valid")
        elif report_size > 0:
            score += 10
            subscores['report_meta'] = 10
            feedback_parts.append("Report exists (timestamp/size warning)")
        else:
            feedback_parts.append("Report file is empty")
    else:
        feedback_parts.append("Report file MISSING")

    # 6. Report Content (35 pts)
    if report_exists:
        # Incident context (8)
        if result.get('report_content_incident', False):
            score += 8
            subscores['content_incident'] = 8
        else:
            feedback_parts.append("Report missing incident details (hypotension/BP)")

        # Root cause (7)
        if result.get('report_content_root', False):
            score += 7
            subscores['content_root'] = 7
        else:
            feedback_parts.append("Report missing root cause (transport/disconnect)")

        # Gap analysis (5)
        if result.get('report_content_gap', False):
            score += 5
            subscores['content_gap'] = 5
        
        # Actions (8)
        if result.get('report_content_action', False):
            score += 8
            subscores['content_action'] = 8

        # OpenICE ref (4)
        if result.get('report_content_openice', False):
            score += 4
            subscores['content_openice'] = 4
            
        # Structure (3)
        if result.get('report_structure_count', 0) >= 3:
            score += 3
            subscores['structure'] = 3

    # Final Result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }