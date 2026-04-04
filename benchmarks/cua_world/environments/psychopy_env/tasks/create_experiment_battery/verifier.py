#!/usr/bin/env python3
"""
Verifier for create_experiment_battery task.

Verification Strategy (Hybrid: Programmatic + VLM):

Programmatic checks (70 points):
  1. Experiment file exists and valid XML (10 pts)
  2. File created during task (5 pts)
  3. Has 3 loops referencing stroop, flanker, simon conditions (15 pts)
  4. Has welcome/intro routine (5 pts)
  5. Has 3+ instruction routines (one per task block) (10 pts)
  6. Has break/rest routines between blocks (5 pts)
  7. Has debrief/end routine (5 pts)
  8. Structural complexity (min 100 params, 200 lines) (15 pts)

VLM checks (30 points):
  9. Builder workflow visible (15 pts)
  10. Final state shows large multi-block experiment (15 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def _parse_battery_psyexp(filepath):
    """Independently parse the battery .psyexp."""
    import xml.etree.ElementTree as ET

    data = {
        'is_valid_xml': False,
        'routine_names': [],
        'routine_count': 0,
        'param_count': 0,
        'line_count': 0,
        'loop_count': 0,
        'conditions_files': [],
        'has_stroop_ref': False,
        'has_flanker_ref': False,
        'has_simon_ref': False,
        'has_welcome': False,
        'has_debrief': False,
        'instruction_count': 0,
        'break_count': 0,
        'trial_count': 0,
        'flow_routine_order': [],
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

            if "welcome" in rl or rl == "intro":
                data['has_welcome'] = True
            if "debrief" in rl or "end" in rl or "thanks" in rl or "thank" in rl:
                data['has_debrief'] = True
            if "instruct" in rl:
                data['instruction_count'] += 1
            if "break" in rl or "rest" in rl or "pause" in rl:
                data['break_count'] += 1
            if "trial" in rl:
                data['trial_count'] += 1

        data['routine_names'] = names
        data['routine_count'] = len(names)

    flow = root.find("Flow") or root.find(".//Flow")
    if flow is not None:
        flow_routines = []
        for elem in flow:
            if elem.tag == "Routine":
                flow_routines.append(elem.get("name", ""))
            elif "LoopInit" in elem.tag:
                data['loop_count'] += 1
                for param in elem:
                    if param.get("name") == "conditionsFile":
                        cfile = param.get("val", "").strip()
                        if cfile:
                            data['conditions_files'].append(cfile)
                            cl = cfile.lower()
                            if "stroop" in cl:
                                data['has_stroop_ref'] = True
                            if "flanker" in cl:
                                data['has_flanker_ref'] = True
                            if "simon" in cl:
                                data['has_simon_ref'] = True
        data['flow_routine_order'] = flow_routines

    return data


def verify_create_experiment_battery(traj, env_info, task_info):
    """Verify the cognitive battery experiment was built correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    output_file = metadata.get('output_file', '/home/ga/PsychoPyExperiments/cognitive_battery.psyexp')

    feedback_parts = []
    score = 0

    # Load export result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/create_experiment_battery_result.json", tmp_path)
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
    file_data = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.psyexp') as tmp:
            psyexp_path = tmp.name
        copy_from_env(output_file, psyexp_path)
        file_data = _parse_battery_psyexp(psyexp_path)
    except Exception as e:
        logger.warning(f"psyexp re-analysis failed: {e}")
    finally:
        if 'psyexp_path' in locals() and os.path.exists(psyexp_path):
            os.unlink(psyexp_path)

    d = file_data if file_data else result

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================

    # 1. File exists and valid XML (10 pts)
    if d.get('is_valid_xml'):
        score += 10
        feedback_parts.append("Battery experiment file exists and valid")
    elif result.get('file_exists'):
        score += 3
        feedback_parts.append("File exists but not valid PsychoPy XML")
    else:
        feedback_parts.append("FAIL: Battery experiment file not found")

    # 2. File created during task (5 pts)
    if result.get('file_modified'):
        score += 5
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("FAIL: File not created during task")

    # 3. Three loops referencing correct conditions files (15 pts)
    conditions_score = 0
    has_stroop = d.get('has_stroop_ref') or result.get('has_stroop_conditions_ref')
    has_flanker = d.get('has_flanker_ref') or result.get('has_flanker_conditions_ref')
    has_simon = d.get('has_simon_ref') or result.get('has_simon_conditions_ref')

    if has_stroop:
        conditions_score += 5
    if has_flanker:
        conditions_score += 5
    if has_simon:
        conditions_score += 5
    score += conditions_score
    refs_found = sum([has_stroop, has_flanker, has_simon])
    feedback_parts.append(f"Conditions references: {refs_found}/3 ({conditions_score}/15 pts)")

    # 4. Welcome/intro routine (5 pts)
    if d.get('has_welcome') or result.get('has_welcome_routine'):
        score += 5
        feedback_parts.append("Welcome/intro routine present")
    else:
        feedback_parts.append("FAIL: No welcome/intro routine")

    # 5. Instruction routines (10 pts) — need 3+ for the three task blocks
    instr_count = d.get('instruction_count', result.get('instruction_routine_count', 0))
    if instr_count >= 3:
        score += 10
        feedback_parts.append(f"Task instruction routines: {instr_count} (need 3+)")
    elif instr_count >= 2:
        score += 6
        feedback_parts.append(f"Task instruction routines: {instr_count}/3")
    elif instr_count >= 1:
        score += 3
        feedback_parts.append(f"Task instruction routines: {instr_count}/3")
    else:
        feedback_parts.append("FAIL: No task-specific instruction routines")

    # 6. Break/rest routines (5 pts)
    break_count = d.get('break_count', result.get('break_routine_count', 0))
    if break_count >= 2:
        score += 5
        feedback_parts.append(f"Break screens: {break_count}")
    elif break_count >= 1:
        score += 3
        feedback_parts.append(f"Break screens: {break_count}/2")
    else:
        feedback_parts.append("FAIL: No break screens between blocks")

    # 7. Debrief routine (5 pts)
    if d.get('has_debrief') or result.get('has_debrief_routine'):
        score += 5
        feedback_parts.append("Debrief/end routine present")
    else:
        feedback_parts.append("FAIL: No debrief/end routine")

    # 8. Structural complexity (15 pts)
    params = d.get('param_count', result.get('param_count', 0))
    lines = d.get('line_count', result.get('line_count', 0))
    routines_n = d.get('routine_count', result.get('routine_count', 0))

    if params >= 100 and lines >= 200 and routines_n >= 8:
        score += 15
        feedback_parts.append(f"High complexity: {params} params, {lines} lines, {routines_n} routines")
    elif params >= 60 and lines >= 100 and routines_n >= 5:
        score += 10
        feedback_parts.append(f"Moderate complexity: {params} params, {lines} lines, {routines_n} routines")
    elif params >= 30 and routines_n >= 3:
        score += 5
        feedback_parts.append(f"Low complexity: {params} params, {routines_n} routines")
    else:
        feedback_parts.append(f"FAIL: Too simple ({params} params, {routines_n} routines)")

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
                    "Is the user building a large experiment with many routines "
                    "and multiple loops? Can you see them adding multiple task blocks? "
                    "Answer yes or no.",
                    frames
                )
                vlm_text = (vlm_response or "").strip().lower()
                if vlm_text.startswith('yes'):
                    score += 15
                    feedback_parts.append("VLM: Multi-block building workflow confirmed")
                else:
                    feedback_parts.append("VLM: Building workflow not confirmed")
        except Exception as e:
            feedback_parts.append(f"VLM trajectory check skipped: {e}")

    if query_vlm and get_final_screenshot:
        try:
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                vlm_response = query_vlm(
                    "Does this PsychoPy Builder screenshot show a large experiment "
                    "with 8 or more routines and multiple loops in the flow panel? "
                    "This should look like a complex multi-block experiment. "
                    "Answer yes or no.",
                    [final_screenshot]
                )
                vlm_text = (vlm_response or "").strip().lower()
                if vlm_text.startswith('yes'):
                    score += 15
                    feedback_parts.append("VLM: Large battery experiment visible")
                else:
                    feedback_parts.append("VLM: Battery experiment not clearly visible")
        except Exception as e:
            feedback_parts.append(f"VLM final check skipped: {e}")

    score = min(score, 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "has_stroop_ref": has_stroop,
            "has_flanker_ref": has_flanker,
            "has_simon_ref": has_simon,
            "loop_count": d.get('loop_count', 0),
            "routine_count": d.get('routine_count', 0),
            "instruction_count": instr_count,
            "break_count": break_count,
            "conditions_files": d.get('conditions_files', []),
            "independent_analysis": file_data is not None,
        }
    }
