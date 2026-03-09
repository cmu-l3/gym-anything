#!/usr/bin/env python3
"""
Verifier for create_conditions_file task.

Verification Strategy (Programmatic + VLM):

Programmatic checks (55 points max):
  1. File exists and created during task (10 pts)
  2. Valid CSV with correct header columns (10 pts)
  3. At least 8 data rows (5 pts)
  4. Has both congruent and incongruent conditions (10 pts)
  5. corrAns values are valid (left/right) for both directions (10 pts)
  6. Stimuli use arrow notation with variety (5 pts)
  7. Semantic correctness: corrAns matches stimulus direction (5 pts)

VLM checks (45 points):
  8. Shows PsychoPy environment usage during file creation (25 pts)
  9. Final state shows completed conditions file (20 pts)

Pass threshold: 60 points (requires VLM to pass — cannot pass via terminal scripting alone)
"""

import json
import tempfile
import os
import csv
import logging

logger = logging.getLogger(__name__)


def verify_create_conditions_file(traj, env_info, task_info):
    """Verify that a valid flanker conditions CSV was created."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    output_file = metadata.get('output_file', '/home/ga/PsychoPyExperiments/conditions/my_flanker_conditions.csv')
    min_rows = 8

    feedback_parts = []
    score = 0

    # Load export result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/create_conditions_file_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback_parts.append(f"Could not read export result: {e}")
    finally:
        if 'tmp_path' in locals() and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # ================================================================
    # NONCE GATE
    # ================================================================
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_path = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_path)
        with open(nonce_path, 'r') as f:
            expected_nonce = f.read().strip()
        result_nonce = result.get('result_nonce', '')
        if expected_nonce and result_nonce != expected_nonce:
            return {
                "passed": False,
                "score": 0,
                "feedback": "FAIL: Result nonce mismatch",
                "details": {"nonce_mismatch": True}
            }
    except Exception as e:
        logger.warning(f"Nonce check skipped: {e}")
    finally:
        if 'nonce_path' in locals() and os.path.exists(nonce_path):
            os.unlink(nonce_path)

    # ================================================================
    # PROGRAMMATIC CHECKS (55 points max)
    # ================================================================

    # Criterion 1: File exists and created during task (10 pts)
    if result.get('file_exists') and result.get('file_modified'):
        score += 10
        feedback_parts.append("File exists and created during task")
    elif result.get('file_exists'):
        score += 5
        feedback_parts.append("File exists but may not be from this task")
    else:
        feedback_parts.append("FAIL: File not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Pull the actual CSV file for independent validation
    rows = []
    headers = []
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as tmp:
            csv_path = tmp.name
        copy_from_env(output_file, csv_path)
        with open(csv_path, 'r', newline='') as f:
            reader = csv.DictReader(f)
            headers = [h.strip().lower() for h in (reader.fieldnames or [])]
            for row in reader:
                rows.append({k.strip().lower(): v.strip() if v else '' for k, v in row.items()})
    except Exception as e:
        feedback_parts.append(f"FAIL: Could not parse CSV: {e}")
    finally:
        if 'csv_path' in locals() and os.path.exists(csv_path):
            os.unlink(csv_path)

    # Criterion 2: Valid CSV with correct columns (10 pts)
    required_columns = ['stimulus', 'condition', 'direction', 'corrans']
    # Also accept 'correctans' or 'correct' as alternatives
    cols_found = 0
    for rc in required_columns:
        if rc in headers:
            cols_found += 1
        elif rc == 'corrans' and any(h in headers for h in ['correctans', 'correct']):
            cols_found += 1

    if cols_found == len(required_columns):
        score += 10
        feedback_parts.append(f"All {len(required_columns)} required columns present")
    elif cols_found >= 3:
        score += 7
        feedback_parts.append(f"{cols_found}/{len(required_columns)} required columns found")
    elif cols_found >= 2:
        score += 3
        feedback_parts.append(f"Only {cols_found}/{len(required_columns)} columns found")
    else:
        feedback_parts.append(f"FAIL: Only {cols_found}/{len(required_columns)} required columns")

    # Criterion 3: At least 8 data rows (5 pts)
    if len(rows) >= min_rows:
        score += 5
        feedback_parts.append(f"{len(rows)} data rows (min {min_rows})")
    elif len(rows) >= min_rows // 2:
        score += 3
        feedback_parts.append(f"Only {len(rows)} rows (need {min_rows})")
    else:
        feedback_parts.append(f"FAIL: Only {len(rows)} rows (need {min_rows})")

    # Criterion 4: Has both congruent and incongruent (10 pts)
    conditions = set()
    for row in rows:
        cond = row.get('condition', '').lower()
        if 'incongruent' in cond:
            conditions.add('incongruent')
        elif 'congruent' in cond:
            conditions.add('congruent')

    if 'congruent' in conditions and 'incongruent' in conditions:
        score += 10
        feedback_parts.append("Both congruent and incongruent conditions present")
    elif len(conditions) == 1:
        score += 5
        feedback_parts.append(f"Only {list(conditions)[0]} condition found")
    else:
        feedback_parts.append("FAIL: Missing condition types")

    # Criterion 5: corrAns values valid with both directions (10 pts)
    valid_answers = {'left', 'right'}
    corrans_values = set()
    for row in rows:
        ans = row.get('corrans', row.get('correctans', row.get('correct', ''))).lower()
        if ans:
            corrans_values.add(ans)

    if corrans_values == valid_answers:
        score += 10
        feedback_parts.append("corrAns has both left and right values")
    elif len(corrans_values & valid_answers) == 1:
        score += 5
        feedback_parts.append(f"corrAns only has: {corrans_values & valid_answers}")
    else:
        feedback_parts.append(f"FAIL: Invalid corrAns values: {corrans_values}")

    # Criterion 6: Stimuli use arrow notation with variety (5 pts)
    stimuli = set()
    has_arrows = False
    for row in rows:
        stim = row.get('stimulus', '')
        if stim:
            stimuli.add(stim)
            if ('<' in stim or '>' in stim) and len(stim) >= 3:
                has_arrows = True

    if has_arrows and len(stimuli) >= 4:
        score += 5
        feedback_parts.append(f"Arrow-style stimuli present ({len(stimuli)} unique)")
    elif has_arrows:
        score += 3
        feedback_parts.append(f"Arrow stimuli present but low variety ({len(stimuli)} unique)")
    elif len(stimuli) >= 2:
        score += 2
        feedback_parts.append(f"Non-arrow stimuli with some variety ({len(stimuli)} unique)")
    else:
        feedback_parts.append("FAIL: No valid stimuli found")

    # Criterion 7: Semantic correctness — corrAns matches stimulus direction (5 pts)
    # Verify that left-pointing stimuli (<<<, <, <<<<<) have corrAns=left
    # and right-pointing stimuli (>>>, >, >>>>>) have corrAns=right
    semantic_correct = 0
    semantic_total = 0
    for row in rows:
        stim = row.get('stimulus', '').strip()
        direction = row.get('direction', '').strip().lower()
        ans = row.get('corrans', row.get('correctans', row.get('correct', ''))).strip().lower()

        if not stim or not ans:
            continue
        semantic_total += 1

        # Determine expected answer from stimulus or direction
        expected_ans = None
        # Check stimulus arrow direction
        if stim and ('<' in stim or '>' in stim):
            # Count center character direction (flanker: center char determines answer)
            center_idx = len(stim) // 2
            if center_idx < len(stim):
                center_char = stim[center_idx]
                if center_char == '<':
                    expected_ans = 'left'
                elif center_char == '>':
                    expected_ans = 'right'
        # Fall back to direction column if available
        if expected_ans is None and direction in ('left', 'right'):
            expected_ans = direction

        if expected_ans and ans == expected_ans:
            semantic_correct += 1

    if semantic_total > 0:
        semantic_ratio = semantic_correct / semantic_total
        if semantic_ratio >= 0.9:
            score += 5
            feedback_parts.append(f"Semantic correctness: {semantic_correct}/{semantic_total} corrAns match stimulus direction")
        elif semantic_ratio >= 0.6:
            score += 3
            feedback_parts.append(f"Partial semantic correctness: {semantic_correct}/{semantic_total} corrAns match")
        else:
            feedback_parts.append(f"FAIL: Poor semantic correctness: {semantic_correct}/{semantic_total} corrAns match direction")
    else:
        feedback_parts.append("Note: Could not verify semantic correctness")

    # ================================================================
    # VLM CHECKS (45 points)
    # These are essential — programmatic max is 55, below the 60-point
    # pass threshold. An agent must show they used the PsychoPy environment.
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    sample_trajectory_frames = env_info.get('sample_trajectory_frames')
    get_final_screenshot = env_info.get('get_final_screenshot')

    if query_vlm and sample_trajectory_frames:
        try:
            frames = sample_trajectory_frames(traj, 4)
            if frames:
                vlm_response = query_vlm(
                    "Is the user working within the PsychoPy application environment? "
                    "Can you see PsychoPy Builder, Coder, or a file editor open within "
                    "the PsychoPy desktop? Look for the PsychoPy toolbar or window. "
                    "Answer only 'yes' or 'no' as the first word.",
                    frames
                )
                vlm_text = (vlm_response or "").strip().lower()
                if vlm_text.startswith('yes'):
                    score += 25
                    feedback_parts.append("VLM: PsychoPy environment usage confirmed")
                else:
                    feedback_parts.append("VLM: PsychoPy environment usage not confirmed")
        except Exception as e:
            feedback_parts.append(f"VLM trajectory check skipped: {e}")

    if query_vlm and get_final_screenshot:
        try:
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                vlm_response = query_vlm(
                    "Does this screenshot show a completed CSV or conditions file "
                    "with columns like stimulus, condition, direction, and corrAns? "
                    "Answer only 'yes' or 'no' as the first word.",
                    [final_screenshot]
                )
                vlm_text = (vlm_response or "").strip().lower()
                if vlm_text.startswith('yes'):
                    score += 20
                    feedback_parts.append("VLM: Completed conditions file visible")
                else:
                    feedback_parts.append("VLM: Conditions file not clearly visible")
        except Exception as e:
            feedback_parts.append(f"VLM final check skipped: {e}")

    score = min(score, 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "file_exists": result.get('file_exists', False),
            "row_count": len(rows),
            "columns_found": headers,
            "conditions": list(conditions),
            "corrans_values": list(corrans_values),
            "unique_stimuli": len(stimuli),
            "has_arrows": has_arrows,
        }
    }
