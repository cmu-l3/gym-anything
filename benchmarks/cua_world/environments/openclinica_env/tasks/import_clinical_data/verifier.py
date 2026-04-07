#!/usr/bin/env python3
"""Verifier for import_clinical_data task."""

import json
import tempfile
import os
import logging
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from vlm_utils import sample_trajectory_frames, get_final_screenshot
from vlm_utils import query_vlm as _query_vlm_direct

logger = logging.getLogger(__name__)


def _build_vlm_prompt():
    """Build VLM prompt to verify the agent navigated the Import Data workflow."""
    return """Examine these screenshots of an OpenClinica session.

Look across the images to determine if the agent performed the data import workflow:
1. Is there evidence that the 'Import Data' screen or file upload interface was used?
2. Is there a success message, confirmation screen, or summary showing that data was imported or processed?
3. Did the agent navigate to a subject record, event schedule, or CRF view (e.g. Demographics Survey) to inspect the data?

Respond in JSON format:
{
    "import_ui_used": true/false,
    "import_success_visible": true/false,
    "crf_inspection_visible": true/false,
    "confidence": "low"/"medium"/"high"
}
"""


def verify_import_clinical_data(traj, env_info, task_info):
    """
    Verify the import_clinical_data task completion.

    Scoring logic (100 points total):
    - event_crf record exists (data entry initiated): 20 pts (Gated criteria)
    - Partial import (>= 3 items): 15 pts
    - Complete import (5 items): 10 pts
    - Value match: Age=56 (5 pts), Weight=82.5 (5 pts), Height=168 (5 pts), 
                   Smoking="Former" (5 pts), Diabetes=8 (5 pts).
    - Data added natively (count increase): 5 pts
    - Audit log entries created (anti-SQL-gaming): 10 pts
    - VLM Verification: Navigated Import UI (8 pts) and CRF view (7 pts).

    Pass threshold: 60 points with event_crf record existing.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/import_clinical_data_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify integrity nonce
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
    except Exception:
        expected_nonce = ""
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    result_nonce = result.get('result_nonce', '')
    if expected_nonce and result_nonce != expected_nonce:
        return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: Result file nonce mismatch"}

    score = 0
    feedback_parts = []

    # Expected values from task config
    metadata = task_info.get('metadata', {})
    expected_values = metadata.get('expected_values', {
        "I_DEMO_AGE": "56",
        "I_DEMO_WEIGHT_KG": "82.5",
        "I_DEMO_HEIGHT_CM": "168",
        "I_DEMO_SMOKING_STATUS": "Former",
        "I_DEMO_DIABETES_YEARS": "8"
    })

    # 1. Event CRF Exists (20 pts)
    event_crf_exists = result.get('event_crf_exists', False)
    if event_crf_exists:
        score += 20
        feedback_parts.append("CRF entry created for DM-101 (+20)")
    else:
        feedback_parts.append("FAIL: No CRF entry created for DM-101. Did the import succeed?")
        # Hard requirement fail
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Check item_data counts (15 + 10 pts)
    event_item_count = result.get('event_item_data_count', 0)
    if event_item_count >= 5:
        score += 25
        feedback_parts.append("All 5 items imported (+25)")
    elif event_item_count >= 3:
        score += 15
        feedback_parts.append(f"Partial data imported: {event_item_count} items (+15)")
    elif event_item_count > 0:
        feedback_parts.append(f"Minimal data imported: {event_item_count} items (0)")
    else:
        feedback_parts.append("No item data values found associated with CRF (0)")

    # 3. Value validations (5 pts each)
    imported_vals = result.get('imported_values', {})
    for key, expected in expected_values.items():
        actual = str(imported_vals.get(key, "")).strip()
        if actual == str(expected):
            score += 5
            feedback_parts.append(f"{key} correct (+5)")
        elif actual:
            feedback_parts.append(f"{key} incorrect (expected {expected}, got {actual})")

    # 4. Anti-gaming: DB count check (5 pts)
    initial_db_count = result.get('initial_db_item_count', 0)
    current_db_count = result.get('current_db_item_count', 0)
    if current_db_count > initial_db_count:
        score += 5
    else:
        feedback_parts.append("WARNING: Total DB item count did not increase (0)")

    # 5. Anti-gaming: Audit log check (10 pts)
    audit_baseline = result.get('audit_baseline_count', 0)
    audit_current = result.get('audit_current_count', 0)
    if audit_current > audit_baseline:
        score += 10
        feedback_parts.append("Audit trail confirmed GUI interaction (+10)")
    else:
        feedback_parts.append("PENALTY: No audit log entries found. Was data injected directly?")
        score -= 20

    # 6. VLM Trajectory Verification (up to 15 pts)
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_res = query_vlm(prompt=_build_vlm_prompt(), images=images)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("import_ui_used") or parsed.get("import_success_visible"):
                    score += 8
                    feedback_parts.append("VLM confirmed Import Data UI usage (+8)")
                if parsed.get("crf_inspection_visible"):
                    score += 7
                    feedback_parts.append("VLM confirmed CRF view inspection (+7)")
            else:
                logger.warning(f"VLM verification failed: {vlm_res.get('error')}")

    # Ensure score stays in [0, 100]
    score = max(0, min(100, score))
    passed = (score >= 60 and event_crf_exists)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }