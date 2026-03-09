#!/usr/bin/env python3
"""
Verifier for configure_experiment_settings task.

Verification Strategy (Hybrid: Programmatic + VLM):

Programmatic checks (70 points):
  1. File exists and valid PsychoPy XML (10 pts)
  2. File created during task (10 pts)
  3. Experiment name set to AttentionStudy (15 pts)
  4. Full-screen disabled AND window size [1024, 768] (15 pts combined)
     - Both settings prove intentional change (default fullScr=False + size
       still requires the agent to set size correctly)
  5. Data filename includes participant AND differs from default (5 pts)
  6. Settings-specific structural depth (5 pts)
  7. Structural complexity (10 pts)

VLM checks (30 points):
  8. Shows settings dialog interaction (15 pts)
  9. Final state shows configured experiment (15 pts)

Pass threshold: 60 points
Score capped at 100
Independent file re-analysis: verifier pulls and re-parses the actual .psyexp
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def _parse_settings(filepath):
    """Independently parse a .psyexp file for settings data."""
    import xml.etree.ElementTree as ET

    data = {
        'is_valid_xml': False,
        'param_count': 0,
        'line_count': 0,
        'settings_param_count': 0,
        'has_exp_name': False,
        'exp_name_value': '',
        'has_fullscr_false': False,
        'has_window_size': False,
        'window_size_value': '',
        'has_data_filename': False,
        'data_filename_value': '',
    }

    with open(filepath) as f:
        data['line_count'] = sum(1 for _ in f)

    tree = ET.parse(filepath)
    root = tree.getroot()

    if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
        data['is_valid_xml'] = True

    data['param_count'] = len(root.findall(".//*[@name]"))

    settings = root.find("Settings") or root.find(".//Settings")
    if settings is not None:
        data['settings_param_count'] = len(list(settings))

        for param in settings:
            pname = param.get("name", "")
            pval = param.get("val", "")

            if pname == "expName" and pval.strip() == "AttentionStudy":
                data['has_exp_name'] = True
                data['exp_name_value'] = pval.strip()

            if pname in ("Full-screen window", "fullScr"):
                if pval.strip().lower() == "false":
                    data['has_fullscr_false'] = True

            if pname in ("Window size (pixels)", "size"):
                data['window_size_value'] = pval.strip()
                cleaned = pval.replace("[", "").replace("]", "").replace("(", "").replace(")", "").strip()
                parts = [p.strip() for p in cleaned.split(",")]
                if len(parts) == 2 and parts[0] == "1024" and parts[1] == "768":
                    data['has_window_size'] = True

            if pname in ("Data filename", "dataFileName"):
                data['data_filename_value'] = pval.strip()
                if "participant" in pval.lower():
                    data['has_data_filename'] = True

    return data


def verify_configure_experiment_settings(traj, env_info, task_info):
    """Verify experiment settings were configured correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    output_file = metadata.get('output_file', '/home/ga/PsychoPyExperiments/attention_study.psyexp')

    feedback_parts = []
    score = 0

    # Load export result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/configure_experiment_settings_result.json", tmp_path)
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
    # INDEPENDENT FILE RE-ANALYSIS
    # ================================================================
    file_data = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.psyexp') as tmp:
            psyexp_path = tmp.name
        copy_from_env(output_file, psyexp_path)
        file_data = _parse_settings(psyexp_path)
    except Exception as e:
        logger.warning(f"Independent file re-analysis failed: {e}")
    finally:
        if 'psyexp_path' in locals() and os.path.exists(psyexp_path):
            os.unlink(psyexp_path)

    d = file_data if file_data else result

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================

    # Criterion 1: File exists and valid (10 pts)
    if d.get('is_valid_xml'):
        score += 10
        feedback_parts.append("Experiment file exists and valid PsychoPy XML")
    elif result.get('file_exists'):
        score += 3
        feedback_parts.append("File exists but may not be valid PsychoPy XML")
    else:
        feedback_parts.append("FAIL: File not found")

    # Criterion 2: File created during task (10 pts)
    if result.get('file_modified'):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("FAIL: File not created during task")

    # Criterion 3: Experiment name (15 pts)
    if d.get('has_exp_name'):
        score += 15
        feedback_parts.append(f"Experiment name set to '{d.get('exp_name_value', '')}'")
    else:
        feedback_parts.append("FAIL: Experiment name not set to 'AttentionStudy'")

    # Criterion 4: Full-screen disabled AND window size correct (15 pts combined)
    # Combining these avoids free points from fullScr default.
    # The agent must actively set window size to [1024, 768] — this proves
    # they opened the settings dialog regardless of fullScr default.
    fullscr_ok = d.get('has_fullscr_false', False)
    winsize_ok = d.get('has_window_size', False)

    if fullscr_ok and winsize_ok:
        score += 15
        feedback_parts.append(f"Full-screen=False and window size [1024, 768] correct")
    elif winsize_ok:
        score += 10
        feedback_parts.append("Window size correct but full-screen not confirmed as False")
    elif fullscr_ok:
        score += 3
        feedback_parts.append("Full-screen=False but window size not set correctly")
    else:
        wsv = d.get('window_size_value', '')
        if wsv:
            feedback_parts.append(f"FAIL: Window size '{wsv}' does not match [1024, 768]")
        else:
            feedback_parts.append("FAIL: Window size and full-screen not configured")

    # Criterion 5: Data filename includes participant AND is non-default (5 pts)
    # The default PsychoPy template already has "participant" in the pattern,
    # so we verify the pattern also references the experiment name to prove
    # the agent actively configured it.
    data_fn = d.get('data_filename_value', '')
    if d.get('has_data_filename') and 'attentionstudy' in data_fn.lower():
        score += 5
        feedback_parts.append("Data filename includes participant and experiment name")
    elif d.get('has_data_filename') and data_fn and "u'data/%s" not in data_fn:
        # Has participant but also not the raw default template
        score += 3
        feedback_parts.append("Data filename includes participant but may be default template")
    elif d.get('has_data_filename'):
        score += 2
        feedback_parts.append("Data filename has participant but appears to be default template")
    else:
        feedback_parts.append("Data filename pattern does not include participant")

    # Criterion 6: Settings-specific structural depth (5 pts)
    # A properly configured experiment has 20+ settings params
    settings_count = d.get('settings_param_count', 0)
    if settings_count >= 15:
        score += 5
        feedback_parts.append(f"Settings depth OK ({settings_count} settings params)")
    elif settings_count >= 8:
        score += 3
        feedback_parts.append(f"Low settings depth ({settings_count} settings params)")
    else:
        feedback_parts.append(f"FAIL: Minimal settings ({settings_count} params)")

    # Criterion 7: Overall structural complexity (10 pts)
    param_count = d.get('param_count', 0)
    line_count = d.get('line_count', 0)

    if param_count >= 30 and line_count >= 60:
        score += 10
        feedback_parts.append(f"Structural complexity OK ({param_count} params, {line_count} lines)")
    elif param_count >= 15 and line_count >= 30:
        score += 5
        feedback_parts.append(f"Low structural complexity ({param_count} params, {line_count} lines)")
    else:
        feedback_parts.append(f"FAIL: Minimal structure ({param_count} params, {line_count} lines)")

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
                    "Is the user interacting with PsychoPy's Experiment Settings dialog? "
                    "This dialog has tabs like Basic, Screen, Data and fields for experiment name, "
                    "screen size, and data settings. Can you see this dialog? "
                    "Answer yes or no.",
                    frames
                )
                vlm_text = (vlm_response or "").strip().lower()
                if vlm_text.startswith('yes'):
                    score += 15
                    feedback_parts.append("VLM: Settings dialog interaction confirmed")
                else:
                    feedback_parts.append("VLM: Settings dialog not clearly visible")
        except Exception as e:
            feedback_parts.append(f"VLM trajectory check skipped: {e}")

    if query_vlm and get_final_screenshot:
        try:
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                vlm_response = query_vlm(
                    "Does this PsychoPy screenshot show a saved experiment? "
                    "Can you see the experiment name 'AttentionStudy' in the title bar or interface? "
                    "Answer yes or no.",
                    [final_screenshot]
                )
                vlm_text = (vlm_response or "").strip().lower()
                if vlm_text.startswith('yes'):
                    score += 15
                    feedback_parts.append("VLM: Configured experiment visible")
                else:
                    feedback_parts.append("VLM: Configured experiment not clearly visible")
        except Exception as e:
            feedback_parts.append(f"VLM final check skipped: {e}")

    # ================================================================
    # SCORE CAP
    # ================================================================
    score = min(score, 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "file_exists": result.get('file_exists', False) or (file_data is not None),
            "exp_name": d.get('exp_name_value', ''),
            "fullscr_false": d.get('has_fullscr_false', False),
            "window_size": d.get('has_window_size', False),
            "window_size_value": d.get('window_size_value', ''),
            "data_filename": d.get('has_data_filename', False),
            "param_count": param_count,
            "line_count": line_count,
            "independent_analysis": file_data is not None,
        }
    }
