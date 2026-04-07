#!/usr/bin/env python3
"""
Verifier for Attentional Network Test (ANT) experiment.

Verification is primarily handled by vlm_checklist_verifier.
This programmatic verifier provides basic structural checks as a stub.

Scoring:
- Total: 100 points
- Pass threshold: 60 points
"""

import json
import tempfile
import os
import csv
import logging

logger = logging.getLogger(__name__)


def verify_create_ant_experiment(traj, env_info, task_info):
    """Verify the ANT experiment implementation."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    exp_file_path = metadata.get('experiment_file', '/home/ga/PsychoPyExperiments/ant_experiment.psyexp')
    cond_file_path = metadata.get('conditions_file', '/home/ga/PsychoPyExperiments/ant_conditions.csv')

    feedback_parts = []
    score = 0

    # 1. Load export result JSON
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            json_path = tmp.name
        copy_from_env("/tmp/create_ant_experiment_result.json", json_path)
        with open(json_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if 'json_path' in locals() and os.path.exists(json_path):
            os.unlink(json_path)

    # 2. Nonce gate
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_path = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_path)
        with open(nonce_path, 'r') as f:
            expected_nonce = f.read().strip()
        if expected_nonce and result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "Nonce mismatch (anti-gaming check failed)"}
    except Exception:
        pass
    finally:
        if 'nonce_path' in locals() and os.path.exists(nonce_path):
            os.unlink(nonce_path)

    # =========================================================
    # CHECK 1: File existence and validity (10 points)
    # =========================================================
    file_score = 0
    file_fb = []

    if result.get('exp_file_exists') and result.get('exp_file_modified'):
        file_score += 3
        file_fb.append("Experiment file created")
    else:
        file_fb.append("Experiment file missing or not modified during task")

    if result.get('is_valid_xml'):
        file_score += 3
        file_fb.append("Valid PsychoPy XML")
    else:
        file_fb.append("Invalid or unparseable XML")

    if result.get('cond_file_exists') and result.get('cond_file_modified'):
        file_score += 2
        file_fb.append("Conditions CSV created")
    else:
        file_fb.append("Conditions CSV missing or not modified during task")

    # Check file was created during task (not pre-existing)
    if result.get('exp_file_modified') and result.get('cond_file_modified'):
        file_score += 2
        file_fb.append("Files created during task session")

    score += file_score
    feedback_parts.append(f"Files: {file_score}/10 ({'; '.join(file_fb)})")

    # =========================================================
    # CHECK 2: Conditions CSV content (20 points)
    # =========================================================
    csv_score = 0
    csv_fb = []

    required_cols = metadata.get('required_csv_columns',
                                 ['cue_type', 'flanker_type', 'target_location', 'target_direction', 'corrAns'])
    actual_cols = result.get('csv_columns', [])
    missing_cols = [c for c in required_cols if c not in actual_cols]

    if not missing_cols:
        csv_score += 5
        csv_fb.append("All required columns present")
    else:
        partial = max(0, 5 - len(missing_cols))
        csv_score += partial
        csv_fb.append(f"Missing columns: {missing_cols}")

    row_count = result.get('csv_row_count', 0)
    if row_count >= 48:
        csv_score += 3
        csv_fb.append(f"Row count OK ({row_count})")
    elif row_count >= 24:
        csv_score += 1
        csv_fb.append(f"Partial rows ({row_count}/48)")
    else:
        csv_fb.append(f"Insufficient rows ({row_count})")

    # Check factorial coverage
    cue_types = result.get('csv_cue_types', [])
    flanker_types = result.get('csv_flanker_types', [])
    target_locs = result.get('csv_target_locations', [])
    target_dirs = result.get('csv_target_directions', [])

    if len(cue_types) >= 4:
        csv_score += 3
        csv_fb.append("All 4 cue types present")
    elif len(cue_types) >= 2:
        csv_score += 1

    if len(flanker_types) >= 3:
        csv_score += 3
        csv_fb.append("All 3 flanker types present")
    elif len(flanker_types) >= 2:
        csv_score += 1

    if len(target_locs) >= 2:
        csv_score += 2
        csv_fb.append("Both target locations present")

    if len(target_dirs) >= 2:
        csv_score += 2
        csv_fb.append("Both target directions present")

    if result.get('csv_corrAns_matches_direction'):
        csv_score += 2
        csv_fb.append("corrAns matches target_direction")
    else:
        csv_fb.append("corrAns does not match target_direction")

    score += csv_score
    feedback_parts.append(f"Conditions CSV: {csv_score}/20 ({'; '.join(csv_fb)})")

    # =========================================================
    # CHECK 3: Experiment flow structure (20 points)
    # =========================================================
    flow_score = 0
    flow_fb = []

    routine_names = [r.lower() for r in result.get('routine_names', [])]

    def has_routine_like(*keywords):
        return any(any(kw in rn for kw in keywords) for rn in routine_names)

    if has_routine_like('instruct', 'intro', 'welcome'):
        flow_score += 3
        flow_fb.append("Instructions routine found")

    if has_routine_like('practice', 'prac'):
        flow_score += 3
        flow_fb.append("Practice routine found")

    if has_routine_like('feedback', 'fb'):
        flow_score += 4
        flow_fb.append("Feedback routine found")

    if has_routine_like('rest', 'break', 'pause'):
        flow_score += 3
        flow_fb.append("Rest/break routine found")

    if has_routine_like('trial', 'target', 'stim', 'main'):
        flow_score += 3
        flow_fb.append("Trial routine found")

    if has_routine_like('summary', 'debrief', 'end', 'results', 'finish'):
        flow_score += 4
        flow_fb.append("Summary/debrief routine found")

    score += flow_score
    feedback_parts.append(f"Flow structure: {flow_score}/20 ({'; '.join(flow_fb)})")

    # =========================================================
    # CHECK 4: Loops and blocking (15 points)
    # =========================================================
    loop_score = 0
    loop_fb = []

    loop_count = result.get('loop_count', 0)
    if loop_count >= 3:
        loop_score += 5
        loop_fb.append(f"3+ loops found ({loop_count})")
    elif loop_count >= 2:
        loop_score += 3
        loop_fb.append(f"2 loops found")
    elif loop_count >= 1:
        loop_score += 1
        loop_fb.append(f"1 loop found")
    else:
        loop_fb.append("No loops found")

    cond_files = result.get('loop_conditions_files', [])
    has_ant_cond_ref = any('ant_conditions' in cf.lower() for cf in cond_files)
    if has_ant_cond_ref:
        loop_score += 5
        loop_fb.append("Loop references ant_conditions.csv")
    else:
        loop_fb.append("No loop references ant_conditions.csv")

    # Check for nested/multi-block structure (flow elements suggest complexity)
    flow_elements = result.get('flow_element_count', 0)
    if flow_elements >= 10:
        loop_score += 5
        loop_fb.append(f"Complex flow ({flow_elements} elements)")
    elif flow_elements >= 5:
        loop_score += 3
        loop_fb.append(f"Moderate flow ({flow_elements} elements)")

    score += loop_score
    feedback_parts.append(f"Loops/blocking: {loop_score}/15 ({'; '.join(loop_fb)})")

    # =========================================================
    # CHECK 5: Code component (15 points)
    # =========================================================
    code_score = 0
    code_fb = []

    if result.get('has_code_component'):
        code_score += 3
        code_fb.append("Code component present")

        code = result.get('code_content', '').lower()

        # Check for fixation duration randomization
        if any(kw in code for kw in ['random', 'uniform', 'randint', 'randrange', 'np.random']):
            code_score += 4
            code_fb.append("Randomization logic found")

        # Check for cue-related conditional logic
        if 'cue_type' in code or 'cue' in code:
            code_score += 4
            code_fb.append("Cue conditional logic found")

        # Check for summary statistics
        if any(kw in code for kw in ['mean', 'accuracy', 'correct', 'score', 'percent']):
            code_score += 4
            code_fb.append("Summary statistics logic found")
    else:
        code_fb.append("No Code component found")

    score += code_score
    feedback_parts.append(f"Code component: {code_score}/15 ({'; '.join(code_fb)})")

    # =========================================================
    # CHECK 6: Component configuration (10 points)
    # =========================================================
    comp_score = 0
    comp_fb = []

    if result.get('has_keyboard_component'):
        comp_score += 4
        comp_fb.append("Keyboard component present")
        # Check if left/right keys are configured
        allowed = result.get('keyboard_allowed_keys', [])
        if any('left' in k.lower() and 'right' in k.lower() for k in allowed):
            comp_score += 2
            comp_fb.append("Left/right keys configured")

    if result.get('has_text_component'):
        comp_score += 4
        comp_fb.append("Text component present")

    score += comp_score
    feedback_parts.append(f"Components: {comp_score}/10 ({'; '.join(comp_fb)})")

    # =========================================================
    # CHECK 7: Structural complexity (10 points)
    # =========================================================
    struct_score = 0
    struct_fb = []

    routine_count = result.get('routine_count', 0)
    if routine_count >= 6:
        struct_score += 4
        struct_fb.append(f"6+ routines ({routine_count})")
    elif routine_count >= 4:
        struct_score += 2
        struct_fb.append(f"4-5 routines ({routine_count})")

    param_count = result.get('param_count', 0)
    if param_count >= 80:
        struct_score += 3
        struct_fb.append(f"Complex experiment ({param_count} params)")
    elif param_count >= 40:
        struct_score += 1

    line_count = result.get('line_count', 0)
    if line_count >= 150:
        struct_score += 3
        struct_fb.append(f"Substantial file ({line_count} lines)")
    elif line_count >= 80:
        struct_score += 1

    score += struct_score
    feedback_parts.append(f"Complexity: {struct_score}/10 ({'; '.join(struct_fb)})")

    # =========================================================
    # Final Result
    # =========================================================
    score = min(score, 100)
    passed = score >= 60 and result.get('exp_file_exists') and result.get('cond_file_exists')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "file_score": file_score,
            "csv_score": csv_score,
            "flow_score": flow_score,
            "loop_score": loop_score,
            "code_score": code_score,
            "comp_score": comp_score,
            "struct_score": struct_score
        }
    }
