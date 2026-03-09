#!/usr/bin/env python3
"""
Verifier for replicate_posner_cueing task.

Verification Strategy (Hybrid: Programmatic + VLM):

Programmatic checks (70 points):
  1. Experiment file exists and valid XML (10 pts)
  2. Files created during task (5 pts)
  3. Conditions file: correct columns (cue_location, target_location,
     cue_validity, corrAns) with valid/invalid/neutral trials (10 pts)
  4. Multiple routines: instructions, fixation, cue, target, debrief (15 pts)
  5. Loop with conditions file reference (10 pts)
  6. Temporal structure: fixation and cue as separate routines (10 pts)
  7. Structural complexity (10 pts)

VLM checks (30 points):
  8. Builder workflow visible (15 pts)
  9. Final state shows multi-routine experiment (15 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import csv
import logging

logger = logging.getLogger(__name__)


def _parse_posner_psyexp(filepath):
    """Independently parse the Posner cueing .psyexp."""
    import xml.etree.ElementTree as ET

    data = {
        'is_valid_xml': False,
        'routine_names': [],
        'routine_count': 0,
        'has_instructions': False,
        'has_fixation': False,
        'has_cue': False,
        'has_target': False,
        'has_debrief': False,
        'loop_count': 0,
        'has_conditions_ref': False,
        'conditions_ref_value': '',
        'param_count': 0,
        'line_count': 0,
        # Check for temporal structure
        'has_timed_fixation': False,
        'has_timed_cue': False,
        'has_keyboard_response': False,
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

            if "fixation" in rl or "fix" == rl:
                data['has_fixation'] = True
                # Check if fixation has timed duration
                for comp in routine:
                    for param in comp:
                        pname = param.get("name", "")
                        pval = param.get("val", "")
                        if pname == "stopVal" and pval.strip():
                            try:
                                if float(pval.strip()) > 0:
                                    data['has_timed_fixation'] = True
                            except:
                                pass

            if "cue" in rl:
                data['has_cue'] = True
                for comp in routine:
                    for param in comp:
                        pname = param.get("name", "")
                        pval = param.get("val", "")
                        if pname == "stopVal" and pval.strip():
                            try:
                                if float(pval.strip()) > 0:
                                    data['has_timed_cue'] = True
                            except:
                                pass

            if "target" in rl or "response" in rl or "probe" in rl:
                data['has_target'] = True
                for comp in routine:
                    if "key" in comp.tag.lower():
                        data['has_keyboard_response'] = True

            if "debrief" in rl or "end" in rl or "thanks" in rl:
                data['has_debrief'] = True

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
                        data['conditions_ref_value'] = param.get("val", "").strip()

    return data


def _parse_posner_csv(filepath):
    """Parse and validate the Posner cueing conditions CSV."""
    data = {
        'exists': False,
        'columns': [],
        'row_count': 0,
        'has_cue_location': False,
        'has_target_location': False,
        'has_cue_validity': False,
        'has_corrAns': False,
        'has_valid_trials': False,
        'has_invalid_trials': False,
        'has_neutral_trials': False,
        'validity_types': [],
        'unique_conditions': 0,
    }

    if not os.path.isfile(filepath):
        return data

    data['exists'] = True
    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        columns = reader.fieldnames or []
        data['columns'] = list(columns)

        col_lower = {c.lower().strip(): c for c in columns}
        data['has_cue_location'] = any("cue" in c and ("loc" in c or "pos" in c or "side" in c) for c in col_lower)
        data['has_target_location'] = any("target" in c and ("loc" in c or "pos" in c or "side" in c) for c in col_lower)
        data['has_cue_validity'] = any("valid" in c for c in col_lower)
        data['has_corrAns'] = any("corrans" in c or "correct" in c for c in col_lower)

        rows = list(reader)
        data['row_count'] = len(rows)

        # Check validity types
        val_col = None
        for c in columns:
            if "valid" in c.lower():
                val_col = c
                break

        if val_col:
            vtypes = set()
            for r in rows:
                v = r.get(val_col, "").strip().lower()
                vtypes.add(v)
                if v == "valid":
                    data['has_valid_trials'] = True
                elif v == "invalid":
                    data['has_invalid_trials'] = True
                elif v == "neutral":
                    data['has_neutral_trials'] = True
            data['validity_types'] = sorted(vtypes)

        # Count unique conditions
        seen = set()
        for r in rows:
            key = tuple(r.get(c, "").strip() for c in columns)
            seen.add(key)
        data['unique_conditions'] = len(seen)

    return data


def verify_replicate_posner_cueing(traj, env_info, task_info):
    """Verify the Posner cueing experiment was built correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    output_file = metadata.get('output_file', '/home/ga/PsychoPyExperiments/posner_cueing_experiment.psyexp')
    conditions_file = metadata.get('conditions_file', '/home/ga/PsychoPyExperiments/conditions/posner_conditions.csv')

    feedback_parts = []
    score = 0

    # Load export result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/replicate_posner_cueing_result.json", tmp_path)
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
        psyexp_data = _parse_posner_psyexp(psyexp_path)
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
        csv_data = _parse_posner_csv(csv_path)
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
        if cd.get('has_cue_location') or result.get('has_cue_location_column'):
            csv_score += 2
        if cd.get('has_target_location') or result.get('has_target_location_column'):
            csv_score += 2
        if cd.get('has_cue_validity') or result.get('has_cue_validity_column'):
            csv_score += 2
        if cd.get('has_corrAns') or result.get('has_corrAns_column'):
            csv_score += 1

        # Validity types
        has_valid = cd.get('has_valid_trials') or result.get('has_valid_trials')
        has_invalid = cd.get('has_invalid_trials') or result.get('has_invalid_trials')
        has_neutral = cd.get('has_neutral_trials') or result.get('has_neutral_trials')
        validity_count = sum([has_valid, has_invalid, has_neutral])
        if validity_count >= 3:
            csv_score += 3
        elif validity_count >= 2:
            csv_score += 2
        elif validity_count >= 1:
            csv_score += 1

        score += min(csv_score, 10)
        n_unique = cd.get('unique_conditions', 0)
        vtypes = cd.get('validity_types', result.get('validity_types', []))
        feedback_parts.append(f"Conditions: {min(csv_score, 10)}/10 pts (validities={vtypes}, unique={n_unique})")
    else:
        feedback_parts.append("FAIL: Conditions file not found")

    # 4. Routines for Posner paradigm (15 pts)
    routine_score = 0
    if d.get('has_instructions'):
        routine_score += 3
    if d.get('has_fixation') or result.get('has_fixation_routine'):
        routine_score += 3
    if d.get('has_cue') or result.get('has_cue_routine'):
        routine_score += 3
    if d.get('has_target') or result.get('has_target_routine'):
        routine_score += 3
    if d.get('has_debrief') or result.get('has_debrief_routine'):
        routine_score += 3
    score += min(routine_score, 15)
    rcount = d.get('routine_count', 0)
    feedback_parts.append(f"Posner routines: {min(routine_score, 15)}/15 pts ({rcount} total)")

    # 5. Loop with conditions reference (10 pts)
    if d.get('has_conditions_ref') or result.get('has_conditions_ref'):
        score += 10
        feedback_parts.append("Loop with conditions file reference found")
    elif d.get('loop_count', 0) > 0 or result.get('loop_count', 0) > 0:
        score += 5
        feedback_parts.append("Loop found but no conditions reference")
    else:
        feedback_parts.append("FAIL: No loop found")

    # 6. Temporal structure (10 pts)
    temporal_score = 0
    if d.get('has_timed_fixation'):
        temporal_score += 3
    elif d.get('has_fixation'):
        temporal_score += 1
    if d.get('has_timed_cue'):
        temporal_score += 4
    elif d.get('has_cue'):
        temporal_score += 2
    if d.get('has_keyboard_response'):
        temporal_score += 3
    score += min(temporal_score, 10)
    feedback_parts.append(f"Temporal structure: {min(temporal_score, 10)}/10 pts")

    # 7. Structural complexity (10 pts)
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
                    "Is the user building an experiment with multiple routines "
                    "representing different trial phases (fixation, cue, target)? "
                    "Answer yes or no.",
                    frames
                )
                vlm_text = (vlm_response or "").strip().lower()
                if vlm_text.startswith('yes'):
                    score += 15
                    feedback_parts.append("VLM: Multi-phase building workflow confirmed")
                else:
                    feedback_parts.append("VLM: Building workflow not confirmed")
        except Exception as e:
            feedback_parts.append(f"VLM trajectory check skipped: {e}")

    if query_vlm and get_final_screenshot:
        try:
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                vlm_response = query_vlm(
                    "Does this PsychoPy Builder screenshot show an experiment "
                    "with separate fixation, cue, and target routines in a loop? "
                    "Answer yes or no.",
                    [final_screenshot]
                )
                vlm_text = (vlm_response or "").strip().lower()
                if vlm_text.startswith('yes'):
                    score += 15
                    feedback_parts.append("VLM: Posner cueing experiment visible")
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
            "has_fixation": d.get('has_fixation', False),
            "has_cue": d.get('has_cue', False),
            "has_target": d.get('has_target', False),
            "validity_types": cd.get('validity_types', []) if cd else [],
            "independent_analysis": psyexp_data is not None,
        }
    }
