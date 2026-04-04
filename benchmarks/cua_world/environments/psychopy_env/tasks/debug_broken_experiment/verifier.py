#!/usr/bin/env python3
"""
Verifier for debug_broken_experiment task.

Verification Strategy (Hybrid: Programmatic + VLM):

The broken experiment has 5 planted bugs:
  1. Text color references $colour instead of $letterColor
  2. Keyboard allowedKeys is empty (no responses accepted)
  3. Instructions routine appears AFTER trial loop in flow
  4. Loop nReps = 0 (no trials will run)
  5. Conditions file path references stroop_conds.csv (file doesn't exist)

Programmatic checks (70 points):
  1. File exists and valid PsychoPy XML (10 pts)
  2. File created during task (5 pts)
  3. Color reference fixed: $letterColor (10 pts)
  4. AllowedKeys fixed: has valid response keys (10 pts)
  5. Flow order fixed: instructions before trial (10 pts)
  6. nReps fixed: > 0 (10 pts)
  7. Conditions file fixed: references stroop_conditions.csv (10 pts)
  8. Structural integrity: retains Stroop components (5 pts)

VLM checks (30 points):
  9. Shows debugging/editing workflow (15 pts)
  10. Final state shows corrected experiment (15 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def _parse_fixed_psyexp(filepath):
    """Independently parse the fixed .psyexp to verify bug fixes."""
    import xml.etree.ElementTree as ET

    data = {
        'is_valid_xml': False,
        'color_ref_value': '',
        'color_ref_fixed': False,
        'allowed_keys_value': '',
        'allowed_keys_fixed': False,
        'flow_order_fixed': False,
        'routine_order': [],
        'nreps_value': '',
        'nreps_fixed': False,
        'conditions_file_value': '',
        'conditions_file_fixed': False,
        'has_instructions_routine': False,
        'has_trial_routine': False,
        'param_count': 0,
        'line_count': 0,
        'routine_count': 0,
        'has_stroop_markers': False,
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
        data['routine_count'] = len(list(routines))
        stroop_markers = set()

        for routine in routines:
            rname = routine.get("name", routine.tag).lower()

            if rname == "instructions":
                data['has_instructions_routine'] = True
            elif rname == "trial":
                data['has_trial_routine'] = True

                for comp in routine:
                    for param in comp:
                        pname = param.get("name", "")
                        pval = param.get("val", "")

                        # Bug 1: color reference
                        if pname == "color" and pval.startswith("$"):
                            data['color_ref_value'] = pval
                            if "lettercolor" in pval.lower():
                                data['color_ref_fixed'] = True

                        # Bug 2: allowedKeys
                        if pname == "allowedKeys":
                            data['allowed_keys_value'] = pval
                            # Must contain at least some valid keys
                            if pval.strip() and len(pval.strip()) > 2:
                                data['allowed_keys_fixed'] = True

                        # Stroop markers
                        pval_lower = pval.lower()
                        if "lettercolor" in pval_lower:
                            stroop_markers.add("letterColor")
                        if "corrans" in pval_lower:
                            stroop_markers.add("corrAns")
                        if "stroop" in pval_lower:
                            stroop_markers.add("stroop")

        data['has_stroop_markers'] = len(stroop_markers) >= 1

    # Check flow
    flow = root.find("Flow") or root.find(".//Flow")
    if flow is not None:
        routine_order = []
        for elem in flow:
            if elem.tag == "Routine":
                routine_order.append(elem.get("name", ""))
            elif "Loop" in elem.tag:
                for param in elem:
                    pname = param.get("name", "")
                    pval = param.get("val", "")
                    # Bug 4: nReps
                    if pname == "nReps":
                        data['nreps_value'] = pval.strip()
                        try:
                            if float(pval.strip()) > 0:
                                data['nreps_fixed'] = True
                        except:
                            pass
                    # Bug 5: conditions file
                    if pname == "conditionsFile":
                        data['conditions_file_value'] = pval.strip()
                        if "stroop_conditions" in pval.lower():
                            data['conditions_file_fixed'] = True

        data['routine_order'] = routine_order

        # Bug 3: flow order
        instr_idx = -1
        trial_idx = -1
        for i, rname in enumerate(routine_order):
            if rname.lower() == "instructions" and instr_idx < 0:
                instr_idx = i
            if rname.lower() == "trial" and trial_idx < 0:
                trial_idx = i
        if instr_idx >= 0 and trial_idx >= 0 and instr_idx < trial_idx:
            data['flow_order_fixed'] = True

    return data


def verify_debug_broken_experiment(traj, env_info, task_info):
    """Verify that all 5 bugs in the Stroop experiment were identified and fixed."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    output_file = metadata.get('output_file', '/home/ga/PsychoPyExperiments/stroop_fixed.psyexp')

    feedback_parts = []
    score = 0

    # Load export result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/debug_broken_experiment_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read export result: {e}")
        feedback_parts.append(f"Could not read export result: {e}")
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

    # INDEPENDENT FILE RE-ANALYSIS
    file_data = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.psyexp') as tmp:
            psyexp_path = tmp.name
        copy_from_env(output_file, psyexp_path)
        file_data = _parse_fixed_psyexp(psyexp_path)
    except Exception as e:
        logger.warning(f"Independent file re-analysis failed: {e}")
    finally:
        if 'psyexp_path' in locals() and os.path.exists(psyexp_path):
            os.unlink(psyexp_path)

    d = file_data if file_data else result

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================

    # Criterion 1: File exists and valid PsychoPy XML (10 pts)
    if d.get('is_valid_xml'):
        score += 10
        feedback_parts.append("Fixed experiment file exists and is valid XML")
    elif result.get('file_exists'):
        score += 3
        feedback_parts.append("File exists but may not be valid PsychoPy XML")
    else:
        feedback_parts.append("FAIL: Fixed experiment file not found at expected path")

    # Criterion 2: File created during task (5 pts)
    if result.get('file_modified'):
        score += 5
        feedback_parts.append("File created during task window")
    else:
        feedback_parts.append("FAIL: File not created during task window")

    # Criterion 3: Bug 1 fixed — color references $letterColor (10 pts)
    if d.get('color_ref_fixed'):
        score += 10
        feedback_parts.append(f"Bug 1 FIXED: Color references {d.get('color_ref_value', '$letterColor')}")
    else:
        color_val = d.get('color_ref_value', '(not found)')
        feedback_parts.append(f"Bug 1 NOT FIXED: Color reference is '{color_val}', expected '$letterColor'")

    # Criterion 4: Bug 2 fixed — allowedKeys has valid keys (10 pts)
    if d.get('allowed_keys_fixed'):
        score += 10
        feedback_parts.append(f"Bug 2 FIXED: AllowedKeys set to '{d.get('allowed_keys_value', '')}'")
    else:
        keys_val = d.get('allowed_keys_value', '(empty)')
        feedback_parts.append(f"Bug 2 NOT FIXED: AllowedKeys is '{keys_val}', expected valid response keys")

    # Criterion 5: Bug 3 fixed — instructions before trial in flow (10 pts)
    if d.get('flow_order_fixed'):
        score += 10
        feedback_parts.append("Bug 3 FIXED: Instructions routine before trial in flow")
    else:
        order = d.get('routine_order', [])
        feedback_parts.append(f"Bug 3 NOT FIXED: Flow order {order} — instructions should come before trial")

    # Criterion 6: Bug 4 fixed — nReps > 0 (10 pts)
    if d.get('nreps_fixed'):
        score += 10
        feedback_parts.append(f"Bug 4 FIXED: Loop nReps = {d.get('nreps_value', '')}")
    else:
        nreps = d.get('nreps_value', '0')
        feedback_parts.append(f"Bug 4 NOT FIXED: Loop nReps is '{nreps}', must be > 0")

    # Criterion 7: Bug 5 fixed — conditions file references stroop_conditions.csv (10 pts)
    if d.get('conditions_file_fixed'):
        score += 10
        feedback_parts.append(f"Bug 5 FIXED: Conditions file = '{d.get('conditions_file_value', '')}'")
    else:
        cfile = d.get('conditions_file_value', '(not found)')
        feedback_parts.append(f"Bug 5 NOT FIXED: Conditions file is '{cfile}', should reference stroop_conditions.csv")

    # Criterion 8: Structural integrity (5 pts)
    has_stroop = d.get('has_stroop_markers', False)
    has_both = d.get('has_instructions_routine', False) and d.get('has_trial_routine', False)
    if has_stroop and has_both:
        score += 5
        feedback_parts.append("Structural integrity: Stroop experiment structure preserved")
    elif has_both:
        score += 3
        feedback_parts.append("Has both routines but Stroop markers not detected")
    elif has_stroop:
        score += 2
        feedback_parts.append("Has Stroop markers but missing routines")
    else:
        feedback_parts.append("FAIL: Experiment structure not preserved")

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
                    "Look at these screenshots of PsychoPy. "
                    "Is the user opening and editing an experiment file? "
                    "Can you see them modifying components, changing loop properties, "
                    "or rearranging the flow panel? Answer yes or no.",
                    frames
                )
                vlm_text = (vlm_response or "").strip().lower()
                if vlm_text.startswith('yes'):
                    score += 15
                    feedback_parts.append("VLM: Debugging/editing workflow confirmed")
                else:
                    feedback_parts.append("VLM: Debugging workflow not confirmed")
        except Exception as e:
            feedback_parts.append(f"VLM trajectory check skipped: {e}")

    if query_vlm and get_final_screenshot:
        try:
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                vlm_response = query_vlm(
                    "Does this PsychoPy Builder screenshot show a complete experiment "
                    "with an instructions routine followed by a trial loop in the flow panel? "
                    "Answer yes or no.",
                    [final_screenshot]
                )
                vlm_text = (vlm_response or "").strip().lower()
                if vlm_text.startswith('yes'):
                    score += 15
                    feedback_parts.append("VLM: Corrected experiment visible")
                else:
                    feedback_parts.append("VLM: Corrected experiment not clearly visible")
        except Exception as e:
            feedback_parts.append(f"VLM final check skipped: {e}")

    # ================================================================
    # SCORE AND PASS
    # ================================================================
    score = min(score, 100)
    passed = score >= 60

    bugs_fixed = sum([
        d.get('color_ref_fixed', False),
        d.get('allowed_keys_fixed', False),
        d.get('flow_order_fixed', False),
        d.get('nreps_fixed', False),
        d.get('conditions_file_fixed', False),
    ])

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "bugs_fixed": f"{bugs_fixed}/5",
            "color_ref_fixed": d.get('color_ref_fixed', False),
            "allowed_keys_fixed": d.get('allowed_keys_fixed', False),
            "flow_order_fixed": d.get('flow_order_fixed', False),
            "nreps_fixed": d.get('nreps_fixed', False),
            "conditions_file_fixed": d.get('conditions_file_fixed', False),
            "independent_analysis": file_data is not None,
        }
    }
