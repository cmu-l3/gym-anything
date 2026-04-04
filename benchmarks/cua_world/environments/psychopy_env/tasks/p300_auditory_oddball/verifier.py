#!/usr/bin/env python3
"""
Verifier for p300_auditory_oddball task.

Background: The P300 auditory oddball paradigm (Sutton et al., 1965) is a cornerstone of
cognitive neuroscience and clinical neuropsychology. The ERP component peaking ~300ms post-
stimulus reflects attention and context-updating processes. It is used clinically to assess
cognitive decline (Polich, 2007), consciousness disorders, and ADHD.

The critical design constraints are:
- Exact 80/20 probability ratio (240 standard : 60 deviant = 300 total)
- 1000 Hz standard tone, 2000 Hz deviant tone
- Brief 20ms tone pip duration
- EEG trigger markers at stimulus onset (codes 1 and 2)
- Jittered ISI to prevent temporal prediction

Scoring (100 points):
  1. Experiment file: exists, valid XML, created during task (10 pts)
  2. Conditions file: exists, exactly 300 rows total (10 pts)
  3. Exact probability ratio: 240 standard + 60 deviant rows (20 pts)
  4. Correct frequency values: 1000 Hz standard, 2000 Hz deviant columns (15 pts)
  5. Trigger code column present with codes 1 and 2 (10 pts)
  6. Sound component in experiment (10 pts)
  7. Code component with trigger/marker logic (10 pts)
  8. At least 2 blocks with a rest screen between them (10 pts)
  9. Accuracy feedback/summary screen at end (5 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import csv
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/p300_auditory_oddball_result.json"


def _parse_p300_conditions(filepath):
    """Independently parse the P300 conditions CSV."""
    data = {
        "exists": False,
        "total_rows": 0,
        "standard_rows": 0,
        "deviant_rows": 0,
        "has_tone_col": False,
        "has_trigger_col": False,
        "has_target_col": False,
        "standard_hz_correct": False,
        "deviant_hz_correct": False,
    }
    if not os.path.isfile(filepath):
        return data

    data["exists"] = True
    try:
        with open(filepath, newline="") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            fieldnames = reader.fieldnames or []

        data["total_rows"] = len(rows)

        tone_col = next((fn for fn in fieldnames if any(
            kw in fn.lower() for kw in ["tone", "hz", "freq"])), None)
        trigger_col = next((fn for fn in fieldnames if any(
            kw in fn.lower() for kw in ["trigger", "code", "marker"])), None)
        target_col = next((fn for fn in fieldnames if any(
            kw in fn.lower() for kw in ["target", "deviant", "is_target"])), None)

        data["has_tone_col"] = tone_col is not None
        data["has_trigger_col"] = trigger_col is not None
        data["has_target_col"] = target_col is not None

        if tone_col:
            std = [r for r in rows if r.get(tone_col, "").strip() in ("1000", "1000.0")]
            dev = [r for r in rows if r.get(tone_col, "").strip() in ("2000", "2000.0")]
            data["standard_rows"] = len(std)
            data["deviant_rows"] = len(dev)
            data["standard_hz_correct"] = len(std) == 240
            data["deviant_hz_correct"] = len(dev) == 60

        if trigger_col and not (data["standard_hz_correct"] and data["deviant_hz_correct"]):
            std_t = [r for r in rows if r.get(trigger_col, "").strip() in ("1",)]
            dev_t = [r for r in rows if r.get(trigger_col, "").strip() in ("2",)]
            if len(std_t) == 240:
                data["standard_rows"] = len(std_t)
                data["standard_hz_correct"] = True
            if len(dev_t) == 60:
                data["deviant_rows"] = len(dev_t)
                data["deviant_hz_correct"] = True

    except Exception as e:
        logger.warning(f"P300 conditions parse error: {e}")

    return data


def _parse_p300_psyexp(filepath):
    """Independent parse of P300 psyexp."""
    import xml.etree.ElementTree as ET

    data = {
        "is_valid_xml": False,
        "has_sound": False,
        "has_keyboard": False,
        "has_code": False,
        "has_rest": False,
        "has_feedback": False,
        "loop_count": 0,
        "has_conditions_ref": False,
        "code_has_trigger": False,
        "routine_count": 0,
        "param_count": 0,
        "line_count": 0,
    }

    try:
        with open(filepath) as f:
            data["line_count"] = sum(1 for _ in f)

        tree = ET.parse(filepath)
        root = tree.getroot()
        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            data["is_valid_xml"] = True
        data["param_count"] = len(root.findall(".//*[@name]"))

        routines = root.find("Routines") or root.find(".//Routines")
        all_code = []
        if routines is not None:
            rc = 0
            for routine in routines:
                rc += 1
                rname = routine.get("name", routine.tag).lower()
                if any(kw in rname for kw in ["rest", "break", "pause", "between"]):
                    data["has_rest"] = True
                if any(kw in rname for kw in ["feedback", "result", "end", "summary", "score"]):
                    data["has_feedback"] = True
                for comp in routine:
                    ctag = comp.tag
                    cname = comp.get("name", "").lower()
                    if "Sound" in ctag or "sound" in cname:
                        data["has_sound"] = True
                    if "Keyboard" in ctag or "keyboard" in cname:
                        data["has_keyboard"] = True
                    if "Code" in ctag or "code" in cname:
                        data["has_code"] = True
                        for param in comp:
                            val = param.get("val", "")
                            if val:
                                all_code.append(val)
            data["routine_count"] = rc

        combined = "\n".join(all_code)
        cl = combined.lower()
        data["code_has_trigger"] = any(
            kw in cl for kw in ["trigger", "parallel", "marker", "code", "send"]
        )

        flow = root.find("Flow") or root.find(".//Flow")
        if flow is not None:
            data["loop_count"] = sum(1 for e in flow if "LoopInitiator" in e.tag)
            for elem in flow:
                if "Loop" in elem.tag:
                    for param in elem:
                        if param.get("name") == "conditionsFile" and param.get("val", "").strip():
                            data["has_conditions_ref"] = True

    except Exception as e:
        logger.warning(f"P300 psyexp parse error: {e}")

    return data


def verify_p300_auditory_oddball(traj, env_info, task_info):
    """
    Verify the P300 auditory oddball paradigm.
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

    # --- Independent re-parse of psyexp ---
    independent_exp = {}
    psyexp_path = metadata.get("output_file", "/home/ga/PsychoPyExperiments/p300_oddball.psyexp")
    tmp2 = tempfile.NamedTemporaryFile(delete=False, suffix=".psyexp")
    tmp2.close()
    try:
        copy_from_env(psyexp_path, tmp2.name)
        independent_exp = _parse_p300_psyexp(tmp2.name)
    except Exception as e:
        logger.warning(f"Independent psyexp parse failed: {e}")
    finally:
        try:
            os.unlink(tmp2.name)
        except Exception:
            pass

    # --- Independent re-parse of conditions file ---
    independent_cond = {}
    cond_path = metadata.get("conditions_file",
                             "/home/ga/PsychoPyExperiments/conditions/p300_conditions.csv")
    tmp3 = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
    tmp3.close()
    try:
        copy_from_env(cond_path, tmp3.name)
        independent_cond = _parse_p300_conditions(tmp3.name)
    except Exception as e:
        logger.warning(f"Conditions parse failed: {e}")
    finally:
        try:
            os.unlink(tmp3.name)
        except Exception:
            pass

    # --- Criterion 1: Experiment file valid (10 pts) ---
    file_exists = result.get("file_exists") or independent_exp.get("is_valid_xml")
    file_modified = result.get("file_modified", False)
    valid_xml = result.get("is_valid_xml") or independent_exp.get("is_valid_xml")

    if file_exists and valid_xml and file_modified:
        score += 10
        subscores["file_valid"] = True
        feedback_parts.append("Experiment file created and valid (10/10)")
    elif file_exists and valid_xml:
        score += 5
        subscores["file_valid"] = False
        feedback_parts.append("File valid but not newly created (5/10)")
    else:
        subscores["file_valid"] = False
        feedback_parts.append("Experiment file missing or invalid (0/10)")

    # --- Criterion 2: Conditions file exists with 300 rows (10 pts) ---
    cond_exists = result.get("conditions_exists") or independent_cond.get("exists")
    cond_modified = result.get("conditions_modified", False)
    total_rows = max(result.get("conditions_total_rows", 0), independent_cond.get("total_rows", 0))

    if cond_exists and cond_modified and total_rows == 300:
        score += 10
        subscores["conditions_rows"] = True
        feedback_parts.append(f"Conditions file: exactly 300 rows ✓ (10/10)")
    elif cond_exists and total_rows == 300:
        score += 7
        subscores["conditions_rows"] = False
        feedback_parts.append(f"Conditions file has 300 rows but may not be newly created (7/10)")
    elif cond_exists and total_rows > 0:
        score += 3
        subscores["conditions_rows"] = False
        feedback_parts.append(f"Conditions file exists but has {total_rows} rows (need 300) (3/10)")
    else:
        subscores["conditions_rows"] = False
        feedback_parts.append("Conditions file missing (0/10)")

    # --- Criterion 3: Exact 240 standard + 60 deviant (20 pts) ---
    std_rows = max(result.get("conditions_standard_rows", 0), independent_cond.get("standard_rows", 0))
    dev_rows = max(result.get("conditions_deviant_rows", 0), independent_cond.get("deviant_rows", 0))
    std_correct = result.get("conditions_standard_hz_correct") or independent_cond.get("standard_hz_correct")
    dev_correct = result.get("conditions_deviant_hz_correct") or independent_cond.get("deviant_hz_correct")

    ratio_score = 0
    if std_correct and dev_correct:
        ratio_score = 20
    elif std_rows == 240 or dev_rows == 60:
        ratio_score = 10
    elif std_rows > 0 and dev_rows > 0:
        # Check approximate 80/20 ratio
        if total_rows > 0:
            dev_rate = dev_rows / total_rows
            if 0.17 <= dev_rate <= 0.23:
                ratio_score = 8

    score += ratio_score
    subscores["probability_ratio"] = ratio_score == 20
    feedback_parts.append(
        f"Probability ratio: {std_rows} standard + {dev_rows} deviant = {std_rows+dev_rows} "
        f"(need 240+60=300) ({ratio_score}/20)"
    )

    # --- Criterion 4: Frequency columns with correct values (15 pts) ---
    has_tone_col = result.get("conditions_has_tone_col") or independent_cond.get("has_tone_col")
    has_1000 = result.get("has_1000hz") or result.get("conditions_standard_hz_correct") or independent_cond.get("standard_hz_correct")
    has_2000 = result.get("has_2000hz") or result.get("conditions_deviant_hz_correct") or independent_cond.get("deviant_hz_correct")

    freq_score = 0
    if has_tone_col:
        freq_score += 5
    if has_1000:
        freq_score += 5
    if has_2000:
        freq_score += 5

    score += freq_score
    subscores["frequencies"] = freq_score == 15
    feedback_parts.append(
        f"Frequencies: tone_col={has_tone_col}, 1000Hz={has_1000}, 2000Hz={has_2000} ({freq_score}/15)"
    )

    # --- Criterion 5: Trigger code column (10 pts) ---
    has_trigger_col = result.get("conditions_has_trigger_col") or independent_cond.get("has_trigger_col")
    if has_trigger_col:
        score += 10
        subscores["trigger_col"] = True
        feedback_parts.append("Trigger code column present in conditions (10/10)")
    else:
        subscores["trigger_col"] = False
        feedback_parts.append("No trigger code column found in conditions (0/10)")

    # --- Criterion 6: Sound component in experiment (10 pts) ---
    has_sound = result.get("has_sound_component") or independent_exp.get("has_sound")
    if has_sound:
        score += 10
        subscores["sound"] = True
        feedback_parts.append("Sound component found in experiment (10/10)")
    else:
        subscores["sound"] = False
        feedback_parts.append("No Sound component found in experiment (0/10)")

    # --- Criterion 7: Code component with trigger logic (10 pts) ---
    has_code = result.get("has_code_component") or independent_exp.get("has_code")
    code_trigger = result.get("code_has_trigger") or independent_exp.get("code_has_trigger")

    code_score = 0
    if has_code:
        code_score += 5
    if code_trigger:
        code_score += 5

    score += code_score
    subscores["trigger_code"] = code_trigger
    feedback_parts.append(f"Code component: present={has_code}, trigger logic={code_trigger} ({code_score}/10)")

    # --- Criterion 8: Multiple blocks with rest screen (10 pts) ---
    loop_count = max(result.get("loop_count", 0), independent_exp.get("loop_count", 0))
    has_rest = result.get("has_rest_screen") or independent_exp.get("has_rest")

    block_score = 0
    if loop_count >= 2:
        block_score += 5
    if has_rest:
        block_score += 5

    score += block_score
    subscores["blocks"] = block_score == 10
    feedback_parts.append(f"Blocks: {loop_count} loops, rest_screen={has_rest} ({block_score}/10)")

    # --- Criterion 9: Feedback screen (5 pts) ---
    has_feedback = result.get("has_feedback_screen") or independent_exp.get("has_feedback")
    if has_feedback:
        score += 5
        subscores["feedback"] = True
        feedback_parts.append("Accuracy feedback/summary screen present (5/5)")
    else:
        subscores["feedback"] = False
        feedback_parts.append("No accuracy feedback screen found (0/5)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
