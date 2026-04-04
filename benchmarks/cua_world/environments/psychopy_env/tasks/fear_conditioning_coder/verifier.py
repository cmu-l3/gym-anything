#!/usr/bin/env python3
"""
Verifier for fear_conditioning_coder task.

Background: The differential fear conditioning paradigm with adaptive US intensity
staircase is a standard laboratory procedure in anxiety and clinical psychology research
(Lonsdorf et al., 2017, Psychophysiology). The staircase ensures consistent subjective
aversiveness of the unconditioned stimulus (US) across participants, addressing a major
confound in fear conditioning research. The paradigm requires:

- Differential design: CS+ paired with US; CS- never paired
- Habituation phase: expose to CS without US to reduce orienting responses
- Acquisition phase: CS-US pairings (CS+ only), interspersed with CS- trials
- Adaptive US intensity: PsychoPy StairHandler adjusts amplitude based on ratings
- Data export via ExperimentHandler to structured CSV files

This task uses PsychoPy Coder (not Builder), testing the agent's ability to write
a complete experimental script from scratch.

Scoring (100 points):
  1. Valid Python file created during task (10 pts)
  2. Required psychopy imports (core, visual, data, event) (10 pts)
  3. StairHandler with correct parameters (startVal=0.8, stepSizes, nReversals>=4) (20 pts)
  4. Experimental phase structure (habituation + acquisition + CS+/CS-) (20 pts)
  5. Rating scale component with staircase-adjustment logic (15 pts)
  6. ExperimentHandler / data saving to correct directory (15 pts)
  7. CS/US timing (4s CS, 3.5s onset, 1s US) and counterbalancing (10 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import re
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/fear_conditioning_coder_result.json"


def _parse_fear_conditioning_script(filepath):
    """Independently parse the fear conditioning Python script."""
    import ast

    data = {
        "exists": False,
        "is_valid_python": False,
        "line_count": 0,
        "imports_core": False,
        "imports_visual": False,
        "imports_data": False,
        "imports_event": False,
        "has_stairhandler": False,
        "stair_startval": None,
        "stair_stepsizes": None,
        "stair_nreversals": None,
        "stair_steptype": None,
        "stairhandler_params_correct": False,
        "has_experiment_handler": False,
        "has_data_save": False,
        "has_habituation_phase": False,
        "has_acquisition_phase": False,
        "has_cs_plus": False,
        "has_cs_minus": False,
        "has_us": False,
        "has_rating_scale": False,
        "has_rating_logic": False,
        "has_counterbalancing": False,
        "cs_duration_present": False,
        "us_onset_present": False,
        "has_data_directory": False,
        "has_participant_var": False,
        "has_visual_square": False,
    }

    if not os.path.isfile(filepath):
        return data

    data["exists"] = True
    try:
        with open(filepath) as f:
            source = f.read()
    except Exception as e:
        logger.warning(f"Cannot read fear conditioning script: {e}")
        return data

    data["line_count"] = source.count("\n") + 1

    try:
        ast.parse(source)
        data["is_valid_python"] = True
    except SyntaxError:
        pass

    src_lower = source.lower()

    data["imports_core"] = bool(re.search(r"from\s+psychopy\s+import.*\bcore\b|import\s+psychopy\.core", source))
    data["imports_visual"] = bool(re.search(r"from\s+psychopy\s+import.*\bvisual\b|import\s+psychopy\.visual", source))
    data["imports_data"] = bool(re.search(r"from\s+psychopy\s+import.*\bdata\b|import\s+psychopy\.data", source))
    data["imports_event"] = bool(re.search(r"from\s+psychopy\s+import.*\bevent\b|import\s+psychopy\.event", source))

    data["has_stairhandler"] = bool(re.search(r"StairHandler", source))

    if data["has_stairhandler"]:
        m = re.search(r"startVal\s*=\s*([\d.]+)", source)
        if m:
            data["stair_startval"] = float(m.group(1))

        m = re.search(r"stepSizes\s*=\s*\[([^\]]+)\]", source)
        if m:
            try:
                data["stair_stepsizes"] = [float(x.strip()) for x in m.group(1).split(",")]
            except Exception:
                pass

        m = re.search(r"nReversals\s*=\s*(\d+)", source)
        if m:
            data["stair_nreversals"] = int(m.group(1))

        m = re.search(r"stepType\s*=\s*['\"](\w+)['\"]", source)
        if m:
            data["stair_steptype"] = m.group(1)

        sv_ok = data["stair_startval"] == 0.8
        nr_ok = data["stair_nreversals"] is not None and data["stair_nreversals"] >= 4
        data["stairhandler_params_correct"] = sv_ok and nr_ok

    data["has_experiment_handler"] = bool(re.search(r"ExperimentHandler", source))
    data["has_data_save"] = bool(re.search(
        r"saveAsWideText|saveAsText|\.addData|experiment\.close|\.save", source, re.IGNORECASE
    ))

    data["has_habituation_phase"] = bool(re.search(r"habitu", src_lower))
    data["has_acquisition_phase"] = bool(re.search(r"acqui", src_lower))
    data["has_cs_plus"] = bool(re.search(r"cs[\s_]*\+|cs_?plus|csplus", src_lower))
    data["has_cs_minus"] = bool(re.search(r"cs[\s_]*-|cs_?minus|csminus", src_lower))
    data["has_us"] = bool(re.search(r"\bus\b|unconditioned|white.?noise|shock", src_lower))

    data["has_rating_scale"] = bool(re.search(r"RatingScale|ratingscale|rating_scale|Slider|slider", source))
    data["has_rating_logic"] = bool(re.search(r"rating\s*[><=!]+\s*[0-9]|aversive|subjective", src_lower))

    data["has_counterbalancing"] = bool(re.search(r"modulo|%\s*2|participant.*%|counterbal", src_lower))

    data["cs_duration_present"] = bool(re.search(r"\b4\.0\b|\bcs.*4\b|\bduration.*4\b", src_lower))
    data["us_onset_present"] = bool(re.search(r"3\.5|us.*onset|onset.*us|us.*delay", src_lower))

    data["has_data_directory"] = bool(re.search(r"PsychoPyExperiments/data|/home/ga.*data", source))
    data["has_participant_var"] = bool(re.search(r"participant|expInfo|expinfo", src_lower))
    data["has_visual_square"] = bool(re.search(r"Rect|rect|square|ShapeStim|fillColor|cs_stim|visual.*stim", source))

    return data


def verify_fear_conditioning_coder(traj, env_info, task_info):
    """
    Verify the fear conditioning PsychoPy Coder script.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    subscores = {}
    metadata = task_info.get("metadata", {})

    # --- Copy export JSON ---
    result = {}
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Cannot read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    # --- Independent re-parse of the Python script ---
    independent = {}
    script_path = metadata.get("output_file", "/home/ga/PsychoPyExperiments/fear_conditioning.py")
    tmp2 = tempfile.NamedTemporaryFile(delete=False, suffix=".py")
    tmp2.close()
    try:
        copy_from_env(script_path, tmp2.name)
        independent = _parse_fear_conditioning_script(tmp2.name)
    except Exception as e:
        logger.warning(f"Independent script parse failed: {e}")
    finally:
        try:
            os.unlink(tmp2.name)
        except Exception:
            pass

    def get(key, default=False):
        """Get value from result or independent parse, whichever is truthy."""
        rv = result.get(key, default)
        iv = independent.get(key, default)
        if isinstance(rv, bool) or isinstance(iv, bool):
            return bool(rv) or bool(iv)
        if rv is not None and rv is not False:
            return rv
        return iv

    # --- Criterion 1: Valid Python file created during task (10 pts) ---
    file_exists = get("file_exists")
    file_modified = result.get("file_modified", False)
    is_valid_python = get("is_valid_python")
    line_count = max(result.get("line_count", 0), independent.get("line_count", 0))

    if file_exists and is_valid_python and file_modified:
        score += 10
        subscores["file_valid"] = True
        feedback_parts.append(f"Python script created, valid ({line_count} lines) (10/10)")
    elif file_exists and is_valid_python:
        score += 6
        subscores["file_valid"] = False
        feedback_parts.append(f"Script valid but not newly created (6/10)")
    elif file_exists:
        score += 3
        subscores["file_valid"] = False
        feedback_parts.append("Script exists but has syntax errors (3/10)")
    else:
        subscores["file_valid"] = False
        feedback_parts.append("Script not found (0/10)")

    # --- Criterion 2: Required imports (10 pts) ---
    imports_core = get("imports_core")
    imports_visual = get("imports_visual")
    imports_data = get("imports_data")
    imports_event = get("imports_event")

    import_score = sum([imports_core, imports_visual, imports_data, imports_event]) * 2 + (
        2 if all([imports_core, imports_visual, imports_data, imports_event]) else 0
    )
    import_score = min(import_score, 10)

    score += import_score
    subscores["imports"] = import_score >= 8
    feedback_parts.append(
        f"Imports: core={imports_core}, visual={imports_visual}, "
        f"data={imports_data}, event={imports_event} ({import_score}/10)"
    )

    # --- Criterion 3: StairHandler with correct parameters (20 pts) ---
    has_stair = get("has_stairhandler")
    stair_sv = result.get("stair_startval") or independent.get("stair_startval")
    stair_nr = result.get("stair_nreversals") or independent.get("stair_nreversals")
    stair_st = result.get("stair_steptype") or independent.get("stair_steptype")
    stair_ss = result.get("stair_stepsizes") or independent.get("stair_stepsizes")
    params_correct = get("stairhandler_params_correct")

    stair_score = 0
    if has_stair:
        stair_score += 5
    if stair_sv == 0.8:
        stair_score += 5
    if stair_nr is not None and stair_nr >= 4:
        stair_score += 5
    if params_correct or (has_stair and stair_sv == 0.8 and stair_nr and stair_nr >= 4):
        stair_score += 5

    score += stair_score
    subscores["stairhandler"] = stair_score >= 15
    feedback_parts.append(
        f"StairHandler: present={has_stair}, startVal={stair_sv}, "
        f"nReversals={stair_nr}, stepType={stair_st} ({stair_score}/20)"
    )

    # --- Criterion 4: Phase structure (20 pts) ---
    has_habituation = get("has_habituation_phase")
    has_acquisition = get("has_acquisition_phase")
    has_cs_plus = get("has_cs_plus")
    has_cs_minus = get("has_cs_minus")
    has_us = get("has_us")

    phase_score = 0
    if has_habituation:
        phase_score += 4
    if has_acquisition:
        phase_score += 4
    if has_cs_plus:
        phase_score += 4
    if has_cs_minus:
        phase_score += 4
    if has_us:
        phase_score += 4

    score += phase_score
    subscores["phase_structure"] = phase_score >= 16
    feedback_parts.append(
        f"Phases: habituation={has_habituation}, acquisition={has_acquisition}, "
        f"CS+={has_cs_plus}, CS-={has_cs_minus}, US={has_us} ({phase_score}/20)"
    )

    # --- Criterion 5: Rating scale with staircase-adjustment logic (15 pts) ---
    has_rating = get("has_rating_scale")
    has_rating_logic = get("has_rating_logic")

    rating_score = 0
    if has_rating:
        rating_score += 8
    if has_rating_logic:
        rating_score += 7

    score += rating_score
    subscores["rating_staircase"] = rating_score >= 12
    feedback_parts.append(
        f"Rating/staircase: rating_scale={has_rating}, adjustment_logic={has_rating_logic} ({rating_score}/15)"
    )

    # --- Criterion 6: Data saving to correct location (15 pts) ---
    has_exp_handler = get("has_experiment_handler")
    has_data_save = get("has_data_save")
    has_data_dir = get("has_data_directory")
    has_participant = get("has_participant_var")
    has_date = get("has_date_in_filename")

    data_score = 0
    if has_exp_handler:
        data_score += 5
    if has_data_save:
        data_score += 4
    if has_data_dir:
        data_score += 3
    if has_participant:
        data_score += 2
    if has_date or has_participant:  # date OR participant suffix both acceptable
        data_score += 1

    data_score = min(data_score, 15)
    score += data_score
    subscores["data_saving"] = data_score >= 10
    feedback_parts.append(
        f"Data saving: ExperimentHandler={has_exp_handler}, save_call={has_data_save}, "
        f"data_dir={has_data_dir}, participant_var={has_participant} ({data_score}/15)"
    )

    # --- Criterion 7: CS/US timing and counterbalancing (10 pts) ---
    cs_timing = get("cs_duration_present")
    us_onset = get("us_onset_present")
    counterbal = get("has_counterbalancing")

    timing_score = 0
    if cs_timing:
        timing_score += 4
    if us_onset:
        timing_score += 3
    if counterbal:
        timing_score += 3

    score += timing_score
    subscores["timing_counterbalancing"] = timing_score >= 7
    feedback_parts.append(
        f"Timing/CB: cs_4s={cs_timing}, us_3.5s_onset={us_onset}, "
        f"counterbalancing={counterbal} ({timing_score}/10)"
    )

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
