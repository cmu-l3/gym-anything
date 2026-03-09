#!/usr/bin/env python3
"""
Verifier for create_stroop_experiment task.

Verification Strategy (Hybrid: Programmatic + VLM):

Programmatic checks (70 points):
  1. File exists and valid PsychoPy XML (10 pts)
  2. File created/modified during task (10 pts)
  3. Has 'trial' routine (10 pts, partial 5 for any routine)
  4. Text component with variable reference (10 pts)
  5. Keyboard component with correct answer ref (10 pts)
  6. Loop with conditions file + correct nReps (10 pts)
  7. Structural complexity - genuine PsychoPy file (10 pts)

VLM checks (30 points):
  8. Trajectory shows Builder interface usage (15 pts)
  9. Final state shows experiment with flow (15 pts)

Pass threshold: 60 points (requires VLM OR structural complexity to pass)
Nonce gate: result_nonce must match task nonce (instant fail if mismatch)
Independent file re-analysis: verifier pulls and re-parses the actual .psyexp
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def _parse_psyexp(filepath):
    """Independently parse a .psyexp file and extract validation data."""
    import xml.etree.ElementTree as ET

    data = {
        'is_valid_xml': False,
        'param_count': 0,
        'component_count': 0,
        'line_count': 0,
        'has_routine': False,
        'has_trial_routine': False,
        'has_text_component': False,
        'text_uses_variable': False,
        'text_uses_color_variable': False,
        'text_uses_lettercolor': False,
        'has_keyboard_component': False,
        'keyboard_has_correct_ans': False,
        'has_loop': False,
        'has_conditions_ref': False,
        'loop_nreps': '',
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
        for routine in routines:
            data['has_routine'] = True
            rname = routine.get("name", routine.tag).lower()
            if rname == "trial":
                data['has_trial_routine'] = True

            for comp in routine:
                data['component_count'] += 1
                comp_type = comp.tag

                if "Text" in comp_type:
                    data['has_text_component'] = True
                    for param in comp:
                        pname = param.get("name", "")
                        pval = param.get("val", "")
                        if pname == "text" and "$" in pval:
                            data['text_uses_variable'] = True
                        if pname == "color" and "$" in pval:
                            data['text_uses_color_variable'] = True
                            if "lettercolor" in pval.lower() or "letterColor" in pval:
                                data['text_uses_lettercolor'] = True

                if "Key" in comp_type or "Keyboard" in comp_type:
                    data['has_keyboard_component'] = True
                    for param in comp:
                        pname = param.get("name", "")
                        pval = param.get("val", "")
                        if pname in ("correctAns", "corrAns"):
                            if "$" in pval or "corrAns" in pval:
                                data['keyboard_has_correct_ans'] = True

    flow = root.find("Flow") or root.find(".//Flow")
    if flow is not None:
        for elem in flow:
            if "Loop" in elem.tag:
                data['has_loop'] = True
                for param in elem:
                    pname = param.get("name", "")
                    pval = param.get("val", "")
                    if pname == "conditionsFile":
                        if "stroop_conditions" in pval.lower():
                            data['has_conditions_ref'] = True
                    if pname == "nReps":
                        data['loop_nreps'] = pval.strip()

    return data


def verify_create_stroop_experiment(traj, env_info, task_info):
    """Verify that a Stroop experiment was created in PsychoPy Builder."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_file = metadata.get('expected_file', '/home/ga/PsychoPyExperiments/stroop_experiment.psyexp')

    feedback_parts = []
    score = 0

    # ================================================================
    # Load export result JSON (used for nonce, modification time, etc.)
    # ================================================================
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/create_stroop_experiment_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read export result: {e}")
        feedback_parts.append(f"Could not read export result: {e}")
    finally:
        if 'tmp_path' in locals() and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # ================================================================
    # NONCE GATE: Verify result integrity
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
                "feedback": "FAIL: Result nonce mismatch — export result may have been tampered with",
                "details": {"nonce_mismatch": True}
            }
    except Exception as e:
        logger.warning(f"Nonce check skipped: {e}")
    finally:
        if 'nonce_path' in locals() and os.path.exists(nonce_path):
            os.unlink(nonce_path)

    # ================================================================
    # INDEPENDENT FILE RE-ANALYSIS
    # Pull the actual .psyexp file and re-parse it on the host side.
    # This is the PRIMARY data source for scoring — export JSON is only
    # used for nonce and file_modified (which requires VM-side timestamps).
    # ================================================================
    file_data = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.psyexp') as tmp:
            psyexp_path = tmp.name
        copy_from_env(expected_file, psyexp_path)
        file_data = _parse_psyexp(psyexp_path)
    except Exception as e:
        logger.warning(f"Independent file re-analysis failed: {e}")
        # Fall back to export result data
        file_data = None
    finally:
        if 'psyexp_path' in locals() and os.path.exists(psyexp_path):
            os.unlink(psyexp_path)

    # Use independent analysis if available, else fall back to export result
    d = file_data if file_data else result

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================

    # Criterion 1: File exists and valid PsychoPy XML (10 points)
    if d.get('is_valid_xml'):
        score += 10
        feedback_parts.append("Experiment file exists and is valid PsychoPy XML")
    elif result.get('file_exists'):
        score += 3
        feedback_parts.append("Experiment file exists but not valid PsychoPy XML")
    else:
        feedback_parts.append("FAIL: Experiment file not found")

    # Criterion 2: File modified during task (10 points)
    if result.get('file_modified'):
        score += 10
        feedback_parts.append("File created/modified during task")
    else:
        feedback_parts.append("FAIL: File not modified during task window")

    # Criterion 3: Contains routine named 'trial' (10 points)
    if d.get('has_trial_routine'):
        score += 10
        feedback_parts.append("Experiment has 'trial' routine")
    elif d.get('has_routine'):
        score += 5
        feedback_parts.append("Experiment has routine but not named 'trial'")
    else:
        feedback_parts.append("FAIL: No routine found in experiment")

    # Criterion 4: Text component with variable reference (10 points)
    if d.get('has_text_component') and d.get('text_uses_variable') and d.get('text_uses_lettercolor'):
        score += 10
        feedback_parts.append("Text component uses $text and $letterColor")
    elif d.get('has_text_component') and d.get('text_uses_variable'):
        score += 8
        feedback_parts.append("Text component uses $text variable but color is not $letterColor")
    elif d.get('has_text_component') and d.get('text_uses_color_variable'):
        score += 6
        feedback_parts.append("Text component uses color variable but text is static")
    elif d.get('has_text_component'):
        score += 5
        feedback_parts.append("Text component present but no variable reference")
    else:
        feedback_parts.append("FAIL: No text component found")

    # Criterion 5: Keyboard component with correct answer (10 points)
    if d.get('has_keyboard_component') and d.get('keyboard_has_correct_ans'):
        score += 10
        feedback_parts.append("Keyboard component with corrAns reference")
    elif d.get('has_keyboard_component'):
        score += 5
        feedback_parts.append("Keyboard component present but no corrAns reference")
    else:
        feedback_parts.append("FAIL: No keyboard component found")

    # Criterion 6: Loop with conditions and nReps (10 points)
    if d.get('has_loop') and d.get('has_conditions_ref'):
        nreps = str(d.get('loop_nreps', '')).strip()
        if nreps == '2':
            score += 10
            feedback_parts.append("Loop with conditions file and nReps=2")
        else:
            score += 7
            feedback_parts.append(f"Loop with conditions file but nReps={nreps} (expected 2)")
    elif d.get('has_loop'):
        score += 3
        feedback_parts.append("Loop present but conditions file reference not found")
    else:
        feedback_parts.append("FAIL: No loop found")

    # Criterion 7: Structural complexity — genuine PsychoPy file (10 points)
    param_count = d.get('param_count', 0)
    line_count = d.get('line_count', 0)

    if param_count >= 40 and line_count >= 80:
        score += 10
        feedback_parts.append(f"Structural complexity OK ({param_count} params, {line_count} lines)")
    elif param_count >= 20 and line_count >= 40:
        score += 5
        feedback_parts.append(f"Low structural complexity ({param_count} params, {line_count} lines)")
    else:
        feedback_parts.append(f"FAIL: Minimal file structure ({param_count} params, {line_count} lines) — likely not created via PsychoPy GUI")

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
                    "Look at these screenshots of a PsychoPy session. "
                    "Answer these questions:\n"
                    "1. Is the PsychoPy Builder interface visible (not just Runner or Coder)? (yes/no)\n"
                    "2. Can you see components being added or edited in a routine? (yes/no)\n"
                    "3. Is there a loop visible in the flow panel at the bottom? (yes/no)\n"
                    "Answer each with just yes or no.",
                    frames
                )
                vlm_text = (vlm_response or "").strip().lower()

                # Count 'yes' answers — but only whole-word matches to avoid
                # false positives from words like "yesterday"
                import re
                yes_count = len(re.findall(r'\byes\b', vlm_text))
                if yes_count >= 2:
                    score += 15
                    feedback_parts.append(f"VLM: Builder usage confirmed ({yes_count}/3)")
                elif yes_count >= 1:
                    score += 8
                    feedback_parts.append(f"VLM: Partial Builder usage ({yes_count}/3)")
                else:
                    feedback_parts.append("VLM: Builder usage not confirmed")
        except Exception as e:
            logger.warning(f"VLM trajectory check failed: {e}")
            feedback_parts.append(f"VLM trajectory check skipped: {e}")

    if query_vlm and get_final_screenshot:
        try:
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                vlm_response = query_vlm(
                    "Look at this screenshot of PsychoPy. "
                    "Is there a completed experiment visible with components in a routine "
                    "and a flow diagram showing a loop? Answer yes or no and briefly describe.",
                    [final_screenshot]
                )
                vlm_text = (vlm_response or "").strip().lower()

                if vlm_text.startswith('yes'):
                    score += 15
                    feedback_parts.append("VLM: Final state shows completed experiment")
                else:
                    feedback_parts.append("VLM: Final state does not show completed experiment")
        except Exception as e:
            logger.warning(f"VLM final check failed: {e}")
            feedback_parts.append(f"VLM final check skipped: {e}")

    # ================================================================
    # SCORE CAP AND PASS CRITERIA
    # ================================================================
    score = min(score, 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "file_exists": result.get('file_exists', False) or (file_data is not None),
            "file_modified": result.get('file_modified', False),
            "has_routine": d.get('has_routine', False),
            "has_trial_routine": d.get('has_trial_routine', False),
            "has_text_component": d.get('has_text_component', False),
            "text_uses_variable": d.get('text_uses_variable', False),
            "text_uses_lettercolor": d.get('text_uses_lettercolor', False),
            "has_keyboard_component": d.get('has_keyboard_component', False),
            "keyboard_has_correct_ans": d.get('keyboard_has_correct_ans', False),
            "has_loop": d.get('has_loop', False),
            "has_conditions_ref": d.get('has_conditions_ref', False),
            "param_count": param_count,
            "line_count": line_count,
            "independent_analysis": file_data is not None,
        }
    }
