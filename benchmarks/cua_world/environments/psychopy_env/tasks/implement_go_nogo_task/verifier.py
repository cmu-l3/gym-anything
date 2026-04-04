#!/usr/bin/env python3
"""
Verifier for implement_go_nogo_task.

Verification Strategy (Hybrid: Programmatic + VLM):

Programmatic checks (70 points):
  1. Experiment file exists and valid XML (10 pts)
  2. Files created during task (5 pts)
  3. Conditions file: correct columns, go/nogo ratio, color mapping (10 pts)
  4. Multiple routines: instructions, practice, trial, feedback, debrief (10 pts)
  5. Loop with conditions file reference (10 pts)
  6. Code component for feedback (10 pts)
  7. Break routine between practice and main (5 pts)
  8. Structural complexity (10 pts)

VLM checks (30 points):
  9. Builder workflow visible (15 pts)
  10. Final state shows multi-routine experiment (15 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import csv
import logging

logger = logging.getLogger(__name__)


def _parse_go_nogo_psyexp(filepath):
    """Independently parse the go/no-go .psyexp."""
    import xml.etree.ElementTree as ET

    data = {
        'is_valid_xml': False,
        'routine_names': [],
        'routine_count': 0,
        'has_instructions': False,
        'has_practice': False,
        'has_trial': False,
        'has_feedback': False,
        'has_break': False,
        'has_debrief': False,
        'has_code_component': False,
        'loop_count': 0,
        'has_conditions_ref': False,
        'param_count': 0,
        'line_count': 0,
    }

    with open(filepath) as f:
        data['line_count'] = sum(1 for _ in f)

    tree = ET.parse(filepath)
    root = tree.getroot()

    if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
        data['is_valid_xml'] = True

    data['param_count'] = len(root.findall(".//*[@name]"))

    routines = root.find("Routines") or root.find(".//Routines")
    if routines is not None:
        names = []
        for routine in routines:
            rname = routine.get("name", routine.tag)
            names.append(rname)
            rl = rname.lower()

            if "instruct" in rl or "welcome" in rl:
                data['has_instructions'] = True
            if "practice" in rl or "prac" in rl:
                data['has_practice'] = True
            if "trial" in rl:
                data['has_trial'] = True
            if "feedback" in rl or "fb" in rl:
                data['has_feedback'] = True
            if "break" in rl or "rest" in rl or "pause" in rl:
                data['has_break'] = True
            if "debrief" in rl or "end" in rl or "thanks" in rl:
                data['has_debrief'] = True

            for comp in routine:
                if "code" in comp.tag.lower():
                    data['has_code_component'] = True

        data['routine_names'] = names
        data['routine_count'] = len(names)

    flow = root.find("Flow") or root.find(".//Flow")
    if flow is not None:
        for elem in flow:
            if "LoopInit" in elem.tag:
                data['loop_count'] += 1
                for param in elem:
                    if param.get("name") == "conditionsFile" and param.get("val", "").strip():
                        data['has_conditions_ref'] = True

    return data


def _parse_go_nogo_csv(filepath):
    """Parse and validate the go/no-go conditions CSV."""
    data = {
        'exists': False,
        'columns': [],
        'row_count': 0,
        'has_color_col': False,
        'has_type_col': False,
        'has_corrAns_col': False,
        'go_count': 0,
        'nogo_count': 0,
        'ratio_valid': False,
        'has_green_go': False,
        'has_red_nogo': False,
    }

    if not os.path.isfile(filepath):
        return data

    data['exists'] = True
    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        columns = reader.fieldnames or []
        data['columns'] = list(columns)

        col_lower = {c.lower().strip(): c for c in columns}
        data['has_color_col'] = any("color" in c or "colour" in c for c in col_lower)
        data['has_type_col'] = any("trial" in c and "type" in c for c in col_lower)
        data['has_corrAns_col'] = any("corrans" in c or "correct" in c for c in col_lower)

        rows = list(reader)
        data['row_count'] = len(rows)

        # Find columns
        type_col = None
        for c in columns:
            if "trial" in c.lower() and "type" in c.lower():
                type_col = c
                break

        color_col = None
        for c in columns:
            if "color" in c.lower() or "colour" in c.lower():
                color_col = c
                break

        for r in rows:
            if type_col:
                tt = r.get(type_col, "").strip().lower()
                if tt == "go":
                    data['go_count'] += 1
                elif "nogo" in tt or "no-go" in tt or "no_go" in tt:
                    data['nogo_count'] += 1

            if color_col and type_col:
                color = r.get(color_col, "").strip().lower()
                tt = r.get(type_col, "").strip().lower()
                if "green" in color and tt == "go":
                    data['has_green_go'] = True
                if "red" in color and ("nogo" in tt or "no-go" in tt or "no_go" in tt):
                    data['has_red_nogo'] = True

        total = data['go_count'] + data['nogo_count']
        if total > 0 and data['go_count'] > data['nogo_count']:
            data['ratio_valid'] = True

    return data


def verify_implement_go_nogo_task(traj, env_info, task_info):
    """Verify the Go/No-Go experiment was built correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    output_file = metadata.get('output_file', '/home/ga/PsychoPyExperiments/go_nogo_experiment.psyexp')
    conditions_file = metadata.get('conditions_file', '/home/ga/PsychoPyExperiments/conditions/go_nogo_conditions.csv')

    feedback_parts = []
    score = 0

    # Load export result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/implement_go_nogo_task_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read export result: {e}")
    finally:
        if 'tmp_path' in locals() and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # NONCE GATE
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_path = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_path)
        with open(nonce_path, 'r') as f:
            expected_nonce = f.read().strip()
        result_nonce = result.get('result_nonce', '')
        if expected_nonce and result_nonce != expected_nonce:
            return {
                "passed": False, "score": 0,
                "feedback": "FAIL: Result nonce mismatch",
                "details": {"nonce_mismatch": True}
            }
    except Exception as e:
        logger.warning(f"Nonce check skipped: {e}")
    finally:
        if 'nonce_path' in locals() and os.path.exists(nonce_path):
            os.unlink(nonce_path)

    # INDEPENDENT FILE RE-ANALYSIS
    psyexp_data = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.psyexp') as tmp:
            psyexp_path = tmp.name
        copy_from_env(output_file, psyexp_path)
        psyexp_data = _parse_go_nogo_psyexp(psyexp_path)
    except Exception as e:
        logger.warning(f"psyexp re-analysis failed: {e}")
    finally:
        if 'psyexp_path' in locals() and os.path.exists(psyexp_path):
            os.unlink(psyexp_path)

    csv_data = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as tmp:
            csv_path = tmp.name
        copy_from_env(conditions_file, csv_path)
        csv_data = _parse_go_nogo_csv(csv_path)
    except Exception as e:
        logger.warning(f"CSV re-analysis failed: {e}")
    finally:
        if 'csv_path' in locals() and os.path.exists(csv_path):
            os.unlink(csv_path)

    d = psyexp_data if psyexp_data else result
    cd = csv_data if csv_data else {}

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================

    # 1. File exists and valid XML (10 pts)
    if d.get('is_valid_xml'):
        score += 10
        feedback_parts.append("Experiment file exists and valid")
    elif result.get('psyexp_exists'):
        score += 3
        feedback_parts.append("File exists but not valid PsychoPy XML")
    else:
        feedback_parts.append("FAIL: Experiment file not found")

    # 2. Files created during task (5 pts)
    created = 0
    if result.get('psyexp_modified'):
        created += 1
    if result.get('conditions_modified'):
        created += 1
    if created == 2:
        score += 5
        feedback_parts.append("Both files created during task")
    elif created == 1:
        score += 2
        feedback_parts.append("Only one file created during task")
    else:
        feedback_parts.append("FAIL: Files not created during task")

    # 3. Conditions file (10 pts)
    csv_score = 0
    if cd.get('exists') or result.get('conditions_exists'):
        if cd.get('has_color_col') or result.get('has_stimColor_column'):
            csv_score += 2
        if cd.get('has_type_col') or result.get('has_trial_type_column'):
            csv_score += 2
        if cd.get('has_corrAns_col') or result.get('has_corrAns_column'):
            csv_score += 2
        # Color mapping: green=go, red=nogo
        if cd.get('has_green_go') or result.get('has_green_go'):
            csv_score += 1
        if cd.get('has_red_nogo') or result.get('has_red_nogo'):
            csv_score += 1
        # Go/nogo ratio
        if cd.get('ratio_valid') or result.get('go_nogo_ratio_valid'):
            csv_score += 2

        score += min(csv_score, 10)
        go_n = cd.get('go_count', result.get('go_trial_count', 0))
        nogo_n = cd.get('nogo_count', result.get('nogo_trial_count', 0))
        feedback_parts.append(f"Conditions file: {min(csv_score, 10)}/10 pts (go={go_n}, nogo={nogo_n})")
    else:
        feedback_parts.append("FAIL: Conditions file not found")

    # 4. Multiple routines (10 pts)
    routine_score = 0
    if d.get('has_instructions'):
        routine_score += 2
    if d.get('has_practice') or result.get('has_practice_routine'):
        routine_score += 3
    if d.get('has_trial') or result.get('has_trial_routine'):
        routine_score += 3
    if d.get('has_debrief') or result.get('has_debrief_routine'):
        routine_score += 2
    score += min(routine_score, 10)
    feedback_parts.append(f"Routines: {min(routine_score, 10)}/10 pts ({d.get('routine_count', 0)} total)")

    # 5. Loop with conditions (10 pts)
    if d.get('has_conditions_ref') or result.get('has_conditions_ref'):
        score += 10
        feedback_parts.append("Loop with conditions file reference found")
    elif d.get('loop_count', 0) > 0 or result.get('loop_count', 0) > 0:
        score += 5
        feedback_parts.append("Loop found but no conditions reference")
    else:
        feedback_parts.append("FAIL: No loop found")

    # 6. Code component for feedback (10 pts)
    has_code = d.get('has_code_component') or result.get('has_code_component')
    has_feedback = d.get('has_feedback') or result.get('has_feedback_routine')
    if has_code and has_feedback:
        score += 10
        feedback_parts.append("Code component and feedback routine present")
    elif has_code:
        score += 7
        feedback_parts.append("Code component found (feedback via code)")
    elif has_feedback:
        score += 5
        feedback_parts.append("Feedback routine found but no Code component")
    else:
        feedback_parts.append("FAIL: No feedback mechanism")

    # 7. Break routine (5 pts)
    if d.get('has_break') or result.get('has_break_routine'):
        score += 5
        feedback_parts.append("Break screen between practice and main blocks")
    else:
        feedback_parts.append("FAIL: No break screen")

    # 8. Structural complexity (10 pts)
    params = d.get('param_count', result.get('param_count', 0))
    lines = d.get('line_count', result.get('line_count', 0))
    if params >= 60 and lines >= 100:
        score += 10
        feedback_parts.append(f"Structural complexity: {params} params, {lines} lines")
    elif params >= 30 and lines >= 50:
        score += 5
        feedback_parts.append(f"Moderate complexity: {params} params, {lines} lines")
    elif params >= 15:
        score += 2
        feedback_parts.append(f"Low complexity: {params} params, {lines} lines")
    else:
        feedback_parts.append(f"FAIL: Too simple ({params} params, {lines} lines)")

    # ================================================================
    # VLM CHECKS (30 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    sample_trajectory_frames = env_info.get('sample_trajectory_frames')
    get_final_screenshot = env_info.get('get_final_screenshot')

    if query_vlm and sample_trajectory_frames:
        try:
            frames = sample_trajectory_frames(traj, 4)
            if frames:
                vlm_response = query_vlm(
                    "Look at these screenshots of PsychoPy Builder. "
                    "Is the user building an experiment with routines, loops, "
                    "and components including Code components? Answer yes or no.",
                    frames
                )
                vlm_text = (vlm_response or "").strip().lower()
                if vlm_text.startswith('yes'):
                    score += 15
                    feedback_parts.append("VLM: Building workflow confirmed")
                else:
                    feedback_parts.append("VLM: Building workflow not confirmed")
        except Exception as e:
            feedback_parts.append(f"VLM trajectory check skipped: {e}")

    if query_vlm and get_final_screenshot:
        try:
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                vlm_response = query_vlm(
                    "Does this PsychoPy Builder screenshot show an experiment with "
                    "multiple routines and at least one loop in the flow panel? "
                    "Answer yes or no.",
                    [final_screenshot]
                )
                vlm_text = (vlm_response or "").strip().lower()
                if vlm_text.startswith('yes'):
                    score += 15
                    feedback_parts.append("VLM: Multi-routine experiment visible")
                else:
                    feedback_parts.append("VLM: Experiment not clearly visible")
        except Exception as e:
            feedback_parts.append(f"VLM final check skipped: {e}")

    score = min(score, 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "psyexp_valid": d.get('is_valid_xml', False),
            "conditions_valid": cd.get('exists', False) if cd else False,
            "routine_count": d.get('routine_count', 0),
            "has_code": has_code,
            "has_feedback": has_feedback,
            "go_nogo_ratio": f"{cd.get('go_count', 0)}:{cd.get('nogo_count', 0)}" if cd else "N/A",
            "independent_analysis": psyexp_data is not None,
        }
    }
