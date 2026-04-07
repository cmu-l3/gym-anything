#!/usr/bin/env python3
"""
Verifier for groundwater_heavy_metal_exposure task.

This task requires the agent to manage a multi-patient incident context.
Scoring breakdown (100 points total):
  - 20 pts: John Zenon Diagnosis (T56.x)
  - 20 pts: Matt Zenon Diagnosis (T56.x)
  - 20 pts: John Zenon Lab Order (>=1)
  - 20 pts: Matt Zenon Lab Order (>=1)
  - 20 pts: Incident Documentation for John containing exact phrase
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_groundwater_heavy_metal_exposure(traj, env_info, task_info):
    """Verify Cadmium exposure documentation for John and Matt."""
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})
    required_eval_text = metadata.get('required_eval_text', "Cadmium well water exposure").lower()

    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/groundwater_heavy_metal_exposure_result.json', local_path)
        with open(local_path) as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        logger.error(f"Failed to retrieve result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file from VM: {e}",
            "subscores": {}
        }

    # --- CRITICAL CHECK: Correct setup ---
    john_id = result.get('john_patient_id', 0)
    matt_id = result.get('matt_patient_id', 0)
    if not john_id or not matt_id:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: Target patients not found in database — setup failed.",
            "subscores": {}
        }

    # --- Criterion 1: John Zenon T56.x Diagnosis (20 pts) ---
    john_t56_found = result.get('john_t56_found', False)
    john_t56_active = result.get('john_t56_active', False)
    john_t56_code = result.get('john_t56_code', 'none')

    if john_t56_found and john_t56_active:
        score += 20
        subscores['john_diagnosis'] = 20
        feedback_parts.append(f"John Zenon: Heavy metal toxicity documented (ICD-10 {john_t56_code}, active)")
    elif john_t56_found:
        score += 15
        subscores['john_diagnosis'] = 15
        feedback_parts.append(f"John Zenon: Diagnosis {john_t56_code} documented but NOT marked active")
    else:
        subscores['john_diagnosis'] = 0
        feedback_parts.append("John Zenon: MISSING T56.x diagnosis")

    # --- Criterion 2: Matt Zenon Betz T56.x Diagnosis (20 pts) ---
    matt_t56_found = result.get('matt_t56_found', False)
    matt_t56_active = result.get('matt_t56_active', False)
    matt_t56_code = result.get('matt_t56_code', 'none')

    if matt_t56_found and matt_t56_active:
        score += 20
        subscores['matt_diagnosis'] = 20
        feedback_parts.append(f"Matt Zenon Betz: Heavy metal toxicity documented (ICD-10 {matt_t56_code}, active)")
    elif matt_t56_found:
        score += 15
        subscores['matt_diagnosis'] = 15
        feedback_parts.append(f"Matt Zenon Betz: Diagnosis {matt_t56_code} documented but NOT marked active")
    else:
        subscores['matt_diagnosis'] = 0
        feedback_parts.append("Matt Zenon Betz: MISSING T56.x diagnosis")

    # --- Criterion 3: John Zenon Lab Order >= 1 (20 pts) ---
    john_lab_count = result.get('john_lab_count', 0)
    try:
        john_lab_count = int(john_lab_count)
    except (ValueError, TypeError):
        john_lab_count = 0

    if john_lab_count >= 1:
        score += 20
        subscores['john_labs'] = 20
        feedback_parts.append(f"John Zenon: {john_lab_count} lab test(s) ordered")
    else:
        subscores['john_labs'] = 0
        feedback_parts.append("John Zenon: MISSING lab test orders")

    # --- Criterion 4: Matt Zenon Betz Lab Order >= 1 (20 pts) ---
    matt_lab_count = result.get('matt_lab_count', 0)
    try:
        matt_lab_count = int(matt_lab_count)
    except (ValueError, TypeError):
        matt_lab_count = 0

    if matt_lab_count >= 1:
        score += 20
        subscores['matt_labs'] = 20
        feedback_parts.append(f"Matt Zenon Betz: {matt_lab_count} lab test(s) ordered")
    else:
        subscores['matt_labs'] = 0
        feedback_parts.append("Matt Zenon Betz: MISSING lab test orders")

    # --- Criterion 5: Incident Documentation for John (20 pts) ---
    john_eval_exists = result.get('john_eval_exists', False)
    john_eval_text = result.get('john_eval_text', '').lower()

    # Simple string matching to see if the phrase is present
    # Using python to strip extra characters in case of newline spacing
    normalized_text = ' '.join(john_eval_text.split())
    normalized_required = ' '.join(required_eval_text.split())
    
    # We will also accept a case where they might have missed a single word but largely got the idea
    text_present = normalized_required in normalized_text
    
    if text_present:
        score += 20
        subscores['john_incident_eval'] = 20
        feedback_parts.append(f"John Zenon: Evaluation contains exact phrase '{required_eval_text}'")
    elif john_eval_exists and "cadmium" in normalized_text and ("water" in normalized_text or "exposure" in normalized_text):
        score += 15
        subscores['john_incident_eval'] = 15
        feedback_parts.append("John Zenon: Evaluation mentions Cadmium exposure but does not contain the exact required phrase")
    elif john_eval_exists:
        score += 8
        subscores['john_incident_eval'] = 8
        feedback_parts.append("John Zenon: Evaluation created but missing required incident exposure details")
    else:
        subscores['john_incident_eval'] = 0
        feedback_parts.append("John Zenon: MISSING clinical evaluation")

    # Determine final outcome
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }