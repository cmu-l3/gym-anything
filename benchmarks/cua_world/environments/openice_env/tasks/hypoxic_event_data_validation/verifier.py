#!/usr/bin/env python3
"""
Verifier for hypoxic_event_data_validation task.

Scoring Criteria:
1. Environment Setup (Monitor created, Apps launched) - 20 pts
2. Data File Recovery (File exists, valid timestamp) - 20 pts
3. Baseline Data (Normal values found in data) - 20 pts
4. Distress Data (Hypoxic/Tachycardic values found) - 20 pts
5. Workflow (Distress occurs AFTER baseline) - 20 pts

Total: 100 pts
Pass Threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_hypoxic_event(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load Result
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    
    # 1. Environment Setup (20 pts)
    apps_ok = 0
    if result.get('monitor_created'): apps_ok += 1
    if result.get('recorder_launched'): apps_ok += 1
    if result.get('sim_control_launched'): apps_ok += 1
    
    env_score = min(20, apps_ok * 7) # 7 pts each, max 20
    score += env_score
    if env_score == 20:
        feedback.append("Environment setup complete (Monitor, Recorder, Control).")
    else:
        feedback.append(f"Environment setup partial ({apps_ok}/3 components detected).")

    # 2. Data File Recovery (20 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 20
        feedback.append("Data file recovered successfully.")
    elif result.get('file_exists'):
        score += 10
        feedback.append("Data file exists but timestamp check inconclusive.")
    else:
        feedback.append("Data file NOT found at /home/ga/Desktop/hypoxia_test_data.csv.")

    # 3. Data Content Analysis
    data = result.get('data_analysis', {})
    
    # Baseline (20 pts)
    if data.get('baseline_found'):
        score += 20
        feedback.append("Baseline physiological data identified.")
    else:
        feedback.append("No valid baseline data (Normal HR/SpO2) found in file.")

    # Distress (20 pts)
    if data.get('distress_found'):
        score += 20
        feedback.append("Distress event data identified (High HR / Low SpO2).")
    else:
        feedback.append("No valid distress data (Hypoxic/Tachycardic) found in file.")

    # 4. Workflow / Transition (20 pts)
    if data.get('transition_valid'):
        score += 20
        feedback.append("Physiological transition confirmed (Baseline -> Distress).")
    else:
        feedback.append("Transition sequence not verified (Distress did not follow Baseline).")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }