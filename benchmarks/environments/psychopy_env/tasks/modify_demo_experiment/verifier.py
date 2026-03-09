#!/usr/bin/env python3
"""
Verifier for modify_demo_experiment task.

Verification Strategy (Hybrid: Programmatic + VLM):

Programmatic checks (70 points):
  1. Output file exists and valid PsychoPy XML (10 pts)
  2. File created during task (10 pts)
  3. Instructions routine added (exact name match) (10 pts)
  4. Instruction text in instructions routine (not other routines) (10 pts)
  5. Space key in instructions routine (5 pts)
  6. Loop nReps exactly 3 (10 pts)
  7. Stroop derivation: has trial routine with Stroop-specific content (10 pts)
     - Strengthened: requires 2+ Stroop-specific markers (letterColor, stroop, corrAns)
  8. Instructions before trial in flow (5 pts)

VLM checks (30 points):
  9. Shows modification workflow (15 pts)
  10. Final state shows modified experiment (15 pts)

Pass threshold: 60 points
Independent file re-analysis: verifier pulls and re-parses the actual .psyexp
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def _parse_modified_psyexp(filepath):
    """Independently parse a modified .psyexp for modification verification."""
    import xml.etree.ElementTree as ET

    data = {
        'is_valid_xml': False,
        'has_instructions_routine': False,
        'has_instruction_text_in_instructions': False,
        'has_space_key_in_instructions': False,
        'has_loop': False,
        'loop_nreps': '',
        'has_trial_routine': False,
        'has_stroop_content': False,
        'stroop_marker_count': 0,
        'instructions_before_trial': False,
        'routine_order': [],
        'routine_count': 0,
        'param_count': 0,
        'component_count': 0,
        'line_count': 0,
        'trial_component_count': 0,
        'has_demo_component_names': False,
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

        # Track Stroop-specific markers across all routines
        stroop_markers = set()

        for routine in routines:
            rname = routine.get("name", routine.tag)
            rname_lower = rname.lower()

            if rname_lower == "instructions":
                data['has_instructions_routine'] = True

                for comp in routine:
                    data['component_count'] += 1
                    for param in comp:
                        pname = param.get("name", "")
                        pval = param.get("val", "")
                        if pname == "text" and "space" in pval.lower():
                            data['has_instruction_text_in_instructions'] = True
                        if pname == "allowedKeys" and "space" in pval.lower():
                            data['has_space_key_in_instructions'] = True

            elif rname_lower == "trial":
                data['has_trial_routine'] = True
                # Track original demo component names (word, resp)
                demo_comp_names = set()
                for comp in routine:
                    data['component_count'] += 1
                    data['trial_component_count'] += 1
                    cname = comp.get("name", "").lower()
                    if cname in ("word", "resp"):
                        demo_comp_names.add(cname)
                # Original Stroop demo has both 'word' and 'resp' components
                if len(demo_comp_names) >= 2:
                    data['has_demo_component_names'] = True

            else:
                for comp in routine:
                    data['component_count'] += 1

            # Check for Stroop-related content across ALL routines
            for comp in routine:
                for param in comp:
                    pval = param.get("val", "")
                    pval_lower = pval.lower()
                    if "lettercolor" in pval_lower:
                        stroop_markers.add("letterColor")
                    if "stroop" in pval_lower:
                        stroop_markers.add("stroop")
                    # Only count corrAns in non-instructions routines
                    if rname_lower != "instructions" and "corrans" in pval_lower:
                        stroop_markers.add("corrAns")

        data['stroop_marker_count'] = len(stroop_markers)
        # Require 2+ Stroop markers for confident derivation
        if len(stroop_markers) >= 2:
            data['has_stroop_content'] = True

    # Check flow ordering
    flow = root.find("Flow") or root.find(".//Flow")
    if flow is not None:
        routine_order = []
        for elem in flow:
            if elem.tag == "Routine":
                rname = elem.get("name", "")
                routine_order.append(rname)
            elif "Loop" in elem.tag:
                data['has_loop'] = True
                for param in elem:
                    pname = param.get("name", "")
                    pval = param.get("val", "")
                    if pname == "nReps":
                        data['loop_nreps'] = pval.strip()

        data['routine_order'] = routine_order

        instr_idx = -1
        trial_idx = -1
        for i, rname in enumerate(routine_order):
            if rname.lower() == "instructions" and instr_idx < 0:
                instr_idx = i
            if rname.lower() == "trial" and trial_idx < 0:
                trial_idx = i
        if instr_idx >= 0 and (trial_idx < 0 or instr_idx < trial_idx):
            data['instructions_before_trial'] = True

    return data


def verify_modify_demo_experiment(traj, env_info, task_info):
    """Verify that the Stroop demo was modified correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    output_file = metadata.get('output_file', '/home/ga/PsychoPyExperiments/stroop_modified.psyexp')

    feedback_parts = []
    score = 0

    # Load export result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/modify_demo_experiment_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read export result: {e}")
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
    # DEMO AVAILABILITY CHECK
    # If the demo was not available, the task was impossible — return
    # a clear failure message rather than scoring a doomed attempt.
    # ================================================================
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            demo_status_path = tmp.name
        copy_from_env("/home/ga/.demo_status", demo_status_path)
        with open(demo_status_path, 'r') as f:
            demo_status = f.read().strip()
        if demo_status == "missing":
            return {
                "passed": False,
                "score": 0,
                "feedback": "FAIL: Stroop demo was not available during task setup — task was impossible to complete",
                "details": {"demo_missing": True}
            }
    except Exception as e:
        logger.warning(f"Demo status check skipped: {e}")
    finally:
        if 'demo_status_path' in locals() and os.path.exists(demo_status_path):
            os.unlink(demo_status_path)

    # ================================================================
    # INDEPENDENT FILE RE-ANALYSIS
    # ================================================================
    file_data = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.psyexp') as tmp:
            psyexp_path = tmp.name
        copy_from_env(output_file, psyexp_path)
        file_data = _parse_modified_psyexp(psyexp_path)
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
        feedback_parts.append("Modified experiment file exists and valid")
    elif result.get('file_exists'):
        score += 3
        feedback_parts.append("File exists but may not be valid PsychoPy XML")
    else:
        feedback_parts.append("FAIL: Modified experiment file not found")

    # Criterion 2: File created during task (10 pts)
    if result.get('file_modified'):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("FAIL: File not created during task window")

    # Criterion 3: Instructions routine added (exact name, not substring) (10 pts)
    if d.get('has_instructions_routine'):
        score += 10
        feedback_parts.append("Instructions routine found (exact name match)")
    else:
        feedback_parts.append("FAIL: Instructions routine not found (must be named exactly 'instructions')")

    # Criterion 4: Instruction text scoped to instructions routine only (10 pts)
    if d.get('has_instruction_text_in_instructions'):
        score += 10
        feedback_parts.append("Instruction text with 'space' found in instructions routine")
    else:
        feedback_parts.append("FAIL: Expected instruction text not found in instructions routine")

    # Criterion 5: Space key in instructions routine (5 pts)
    if d.get('has_space_key_in_instructions'):
        score += 5
        feedback_parts.append("Space key response configured in instructions routine")
    else:
        feedback_parts.append("FAIL: Space key response not found in instructions routine")

    # Criterion 6: Loop with nReps exactly 3 (10 pts)
    if d.get('has_loop'):
        loop_nreps = str(d.get('loop_nreps', '')).strip()
        if loop_nreps == '3':
            score += 10
            feedback_parts.append("Loop nReps set to 3")
        else:
            score += 3
            feedback_parts.append(f"Loop present but nReps is '{loop_nreps}', expected '3'")
    else:
        feedback_parts.append("FAIL: No loop found")

    # Criterion 7: Stroop derivation — proves output derives from demo (10 pts)
    # Uses 3 signals: Stroop markers, structural depth, AND original demo
    # component names ('word', 'resp') that are unique to the PsychoPy Stroop demo.
    has_trial = d.get('has_trial_routine', False)
    has_stroop = d.get('has_stroop_content', False)
    stroop_markers = d.get('stroop_marker_count', 0)
    routine_count = d.get('routine_count', 0)
    trial_components = d.get('trial_component_count', 0)
    total_params = d.get('param_count', 0)
    has_demo_names = d.get('has_demo_component_names', False)

    # Full points: demo component names + markers + structural depth
    if has_trial and has_stroop and has_demo_names and total_params >= 50:
        score += 10
        feedback_parts.append(f"Stroop derivation confirmed (demo names + {stroop_markers} markers, {total_params} params)")
    elif has_trial and has_stroop and trial_components >= 2 and total_params >= 50:
        score += 8
        feedback_parts.append(f"Stroop derivation likely (no demo names, but {stroop_markers} markers, {trial_components} components)")
    elif has_trial and has_stroop:
        score += 5
        feedback_parts.append(f"Stroop markers found but low structural depth ({trial_components} components, {total_params} params)")
    elif has_trial and stroop_markers >= 1:
        score += 3
        feedback_parts.append(f"Trial routine found with {stroop_markers} Stroop marker (need 2+)")
    elif has_trial:
        score += 2
        feedback_parts.append("Trial routine found but no Stroop-specific content detected")
    elif routine_count >= 2:
        score += 1
        feedback_parts.append(f"Has {routine_count} routines but no trial routine")
    else:
        feedback_parts.append("FAIL: No evidence of Stroop demo derivation")

    # Criterion 8: Instructions before trial in flow (5 pts)
    if d.get('instructions_before_trial'):
        score += 5
        feedback_parts.append("Instructions routine appears before trial in flow")
    else:
        routine_order = d.get('routine_order', [])
        if routine_order:
            feedback_parts.append(f"FAIL: Routine order {routine_order} — instructions not before trial")
        else:
            feedback_parts.append("FAIL: Could not verify routine ordering in flow")

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
                    "Is the user modifying an existing experiment by adding routines, "
                    "editing loop properties, or adding components? "
                    "Can you see routine editing or loop configuration dialogs? "
                    "Answer yes or no.",
                    frames
                )
                vlm_text = (vlm_response or "").strip().lower()
                if vlm_text.startswith('yes'):
                    score += 15
                    feedback_parts.append("VLM: Modification workflow confirmed")
                else:
                    feedback_parts.append("VLM: Modification workflow not confirmed")
        except Exception as e:
            feedback_parts.append(f"VLM trajectory check skipped: {e}")

    if query_vlm and get_final_screenshot:
        try:
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                vlm_response = query_vlm(
                    "Does this PsychoPy Builder screenshot show an experiment with "
                    "an 'instructions' routine visible in the flow panel, "
                    "followed by a loop around a trial routine? Answer yes or no.",
                    [final_screenshot]
                )
                vlm_text = (vlm_response or "").strip().lower()
                if vlm_text.startswith('yes'):
                    score += 15
                    feedback_parts.append("VLM: Modified experiment with instructions visible")
                else:
                    feedback_parts.append("VLM: Modified experiment not clearly visible")
        except Exception as e:
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
            "has_instructions": d.get('has_instructions_routine', False),
            "has_instruction_text_in_instructions": d.get('has_instruction_text_in_instructions', False),
            "has_space_key_in_instructions": d.get('has_space_key_in_instructions', False),
            "loop_nreps": d.get('loop_nreps', ''),
            "has_trial_routine": has_trial,
            "has_stroop_content": has_stroop,
            "stroop_marker_count": stroop_markers,
            "trial_component_count": trial_components,
            "has_demo_component_names": has_demo_names,
            "instructions_before_trial": d.get('instructions_before_trial', False),
            "routine_order": d.get('routine_order', []),
            "independent_analysis": file_data is not None,
        }
    }
