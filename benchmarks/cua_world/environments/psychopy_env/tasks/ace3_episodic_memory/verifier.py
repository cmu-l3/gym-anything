#!/usr/bin/env python3
"""
Verifier for ace3_episodic_memory task.

Background: The Addenbrooke's Cognitive Examination III (ACE-III; Mioshi et al., 2006)
is the most widely used brief cognitive battery in memory clinics worldwide. The episodic
memory subscale uses a three-word registration–interference–delayed recall–recognition
paradigm. Words used: Lemon, Key, Ball (standard ACE-III stimuli). The recognition phase
uses 12 items: 3 targets + 9 foils, matched for word frequency and imageability.

This task requires the agent to digitize the episodic memory subscale using PsychoPy
Builder, requiring: learning routines, an interference task, free recall with keyboard
input, recognition phase with conditions file loop, code components for scoring, and
a final summary screen.

Scoring (100 points):
  1. Experiment file: exists, valid XML, created during task (10 pts)
  2. Conditions file: exists, exactly 12 rows, correct columns (10 pts)
  3. Target/foil split: exactly 3 targets + 9 foils in conditions (15 pts)
  4. Correct response coding: 3 'y' targets + 9 'n' foils in conditions (10 pts)
  5. Target words present: Lemon, Key, Ball in experiment text (15 pts)
  6. Memory task structure: learning + interference + recall + recognition routines (20 pts)
  7. Code component with scoring logic (10 pts)
  8. Final scoring/summary screen (10 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import csv
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/ace3_episodic_memory_result.json"


def _parse_ace3_conditions(filepath):
    """Independently parse the ACE-III recognition conditions CSV."""
    data = {
        "exists": False,
        "total_rows": 0,
        "target_rows": 0,
        "foil_rows": 0,
        "has_word_col": False,
        "has_is_target_col": False,
        "has_correct_response_col": False,
        "y_count": 0,
        "n_count": 0,
        "has_lemon": False,
        "has_key": False,
        "has_ball": False,
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

        word_col = next(
            (fn for fn in fieldnames if fn.lower() in ("word", "stimulus", "item", "stim")), None
        )
        target_col = next(
            (fn for fn in fieldnames if fn.lower() in ("is_target", "target", "istarget", "is_tgt")), None
        )
        resp_col = next(
            (fn for fn in fieldnames if fn.lower() in (
                "correct_response", "correct_resp", "correctresponse", "answer", "correct_key"
            )), None
        )

        data["has_word_col"] = word_col is not None
        data["has_is_target_col"] = target_col is not None
        data["has_correct_response_col"] = resp_col is not None

        if target_col:
            targets = [r for r in rows if r.get(target_col, "").strip() in ("1", "1.0", "True", "true", "yes")]
            foils = [r for r in rows if r.get(target_col, "").strip() in ("0", "0.0", "False", "false", "no")]
            data["target_rows"] = len(targets)
            data["foil_rows"] = len(foils)

        if resp_col:
            data["y_count"] = sum(1 for r in rows if r.get(resp_col, "").strip().lower() in ("y", "yes"))
            data["n_count"] = sum(1 for r in rows if r.get(resp_col, "").strip().lower() in ("n", "no"))

        if word_col:
            all_words = [r.get(word_col, "").strip().lower() for r in rows]
            data["has_lemon"] = "lemon" in all_words
            data["has_key"] = "key" in all_words
            data["has_ball"] = "ball" in all_words

    except Exception as e:
        logger.warning(f"ACE-III conditions parse error: {e}")

    return data


def _parse_ace3_psyexp(filepath):
    """Independently parse the ACE-III psyexp XML."""
    import xml.etree.ElementTree as ET

    data = {
        "is_valid_xml": False,
        "routine_count": 0,
        "has_learning_phase": False,
        "has_interference_phase": False,
        "has_free_recall": False,
        "has_recognition_phase": False,
        "has_scoring_screen": False,
        "has_keyboard_recall": False,
        "has_keyboard_recognition": False,
        "has_code_component": False,
        "code_has_scoring": False,
        "code_has_recall_score": False,
        "code_has_recognition_score": False,
        "loop_count": 0,
        "has_conditions_ref": False,
        "has_text_lemon": False,
        "has_text_key": False,
        "has_text_ball": False,
        "interference_has_duration": False,
        "interference_duration_sec": 0.0,
    }

    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        data["is_valid_xml"] = True

        routines = root.find("Routines") or root.find(".//Routines")
        all_code_text = []

        if routines is not None:
            rc = 0
            for routine in routines:
                rc += 1
                rname = routine.get("name", routine.tag).lower()

                if any(kw in rname for kw in ["learn", "study", "present", "word", "target", "stimul", "register"]):
                    data["has_learning_phase"] = True
                if any(kw in rname for kw in ["interfere", "distract", "count", "math", "filler", "delay", "task"]):
                    data["has_interference_phase"] = True
                if any(kw in rname for kw in ["recall", "free", "retrieve", "remember"]):
                    data["has_free_recall"] = True
                if any(kw in rname for kw in ["recogni", "identify", "test", "probe"]):
                    data["has_recognition_phase"] = True
                if any(kw in rname for kw in ["score", "result", "summary", "feedback", "end", "final", "debrief"]):
                    data["has_scoring_screen"] = True

                for comp in routine:
                    ctag = comp.tag
                    cname = comp.get("name", "").lower()

                    if "Keyboard" in ctag or "keyboard" in cname:
                        if any(kw in rname for kw in ["recall", "free", "retrieve", "remember"]):
                            data["has_keyboard_recall"] = True
                        if any(kw in rname for kw in ["recogni", "identify", "test", "probe"]):
                            data["has_keyboard_recognition"] = True

                    if "Code" in ctag or "code" in cname:
                        data["has_code_component"] = True
                        for param in comp:
                            val = param.get("val", "")
                            if val:
                                all_code_text.append(val)

                    if "Text" in ctag or "text" in cname:
                        for param in comp:
                            val = param.get("val", "")
                            vl = val.lower() if val else ""
                            if "lemon" in vl:
                                data["has_text_lemon"] = True
                            if " key" in vl or vl.startswith("key") or "\nkey" in vl or vl == "key":
                                data["has_text_key"] = True
                            if "ball" in vl:
                                data["has_text_ball"] = True

                    # Interference duration from any component
                    if any(kw in rname for kw in ["interfere", "distract", "count", "math", "filler", "delay"]):
                        for param in comp:
                            if param.get("name") in ("stopVal", "duration") and param.get("val", ""):
                                try:
                                    dur = float(param.get("val", "0"))
                                    if dur >= 30:
                                        data["interference_has_duration"] = True
                                        data["interference_duration_sec"] = max(
                                            data["interference_duration_sec"], dur
                                        )
                                except ValueError:
                                    pass

            data["routine_count"] = rc

        combined_code = "\n".join(all_code_text).lower()
        if combined_code:
            data["code_has_scoring"] = any(kw in combined_code for kw in ["score", "correct", "hit", "tally"])
            data["code_has_recall_score"] = any(kw in combined_code for kw in [
                "recall_score", "recall score", "free_recall", "recall_hit", "n_recall", "nrecall", "recallscore"
            ])
            data["code_has_recognition_score"] = any(kw in combined_code for kw in [
                "recog_score", "recognition_score", "recog_hit", "n_recog", "nrecog", "recognitionscore"
            ])

        flow = root.find("Flow") or root.find(".//Flow")
        if flow is not None:
            data["loop_count"] = sum(1 for e in flow if "LoopInitiator" in e.tag)
            for elem in flow:
                if "Loop" in elem.tag:
                    for param in elem:
                        if param.get("name") == "conditionsFile" and param.get("val", "").strip():
                            data["has_conditions_ref"] = True

    except Exception as e:
        logger.warning(f"ACE-III psyexp parse error: {e}")

    return data


def verify_ace3_episodic_memory(traj, env_info, task_info):
    """
    Verify the ACE-III episodic memory PsychoPy experiment.
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
    psyexp_path = metadata.get("output_file", "/home/ga/PsychoPyExperiments/ace3_episodic_memory.psyexp")
    tmp2 = tempfile.NamedTemporaryFile(delete=False, suffix=".psyexp")
    tmp2.close()
    try:
        copy_from_env(psyexp_path, tmp2.name)
        independent_exp = _parse_ace3_psyexp(tmp2.name)
    except Exception as e:
        logger.warning(f"Independent psyexp parse failed: {e}")
    finally:
        try:
            os.unlink(tmp2.name)
        except Exception:
            pass

    # --- Independent re-parse of conditions file ---
    independent_cond = {}
    cond_path = metadata.get(
        "conditions_file", "/home/ga/PsychoPyExperiments/conditions/ace3_recognition.csv"
    )
    tmp3 = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
    tmp3.close()
    try:
        copy_from_env(cond_path, tmp3.name)
        independent_cond = _parse_ace3_conditions(tmp3.name)
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

    # --- Criterion 2: Conditions file with correct columns (10 pts) ---
    cond_exists = result.get("conditions_exists") or independent_cond.get("exists")
    cond_modified = result.get("conditions_modified", False)
    total_rows = max(result.get("conditions_total_rows", 0), independent_cond.get("total_rows", 0))
    has_word_col = result.get("conditions_has_word_col") or independent_cond.get("has_word_col")
    has_target_col = result.get("conditions_has_is_target_col") or independent_cond.get("has_is_target_col")
    has_resp_col = result.get("conditions_has_correct_response_col") or independent_cond.get("has_correct_response_col")

    cond_score = 0
    if cond_exists:
        cond_score += 2
    if total_rows == 12:
        cond_score += 3
    if has_word_col:
        cond_score += 2
    if has_target_col:
        cond_score += 2
    if has_resp_col:
        cond_score += 1

    score += cond_score
    subscores["conditions_structure"] = cond_score >= 8
    feedback_parts.append(
        f"Conditions file: rows={total_rows}/12, word_col={has_word_col}, "
        f"target_col={has_target_col}, resp_col={has_resp_col} ({cond_score}/10)"
    )

    # --- Criterion 3: Target/foil split (15 pts) ---
    target_rows = max(result.get("conditions_target_rows", 0), independent_cond.get("target_rows", 0))
    foil_rows = max(result.get("conditions_foil_rows", 0), independent_cond.get("foil_rows", 0))

    split_score = 0
    if target_rows == 3:
        split_score += 8
    elif target_rows > 0:
        split_score += 3
    if foil_rows == 9:
        split_score += 7
    elif foil_rows > 0:
        split_score += 2

    score += split_score
    subscores["target_foil_split"] = split_score == 15
    feedback_parts.append(
        f"Target/foil split: {target_rows} targets (need 3), {foil_rows} foils (need 9) ({split_score}/15)"
    )

    # --- Criterion 4: Correct response coding (10 pts) ---
    y_count = max(result.get("conditions_correct_response_y_count", 0), independent_cond.get("y_count", 0))
    n_count = max(result.get("conditions_correct_response_n_count", 0), independent_cond.get("n_count", 0))

    resp_score = 0
    if y_count == 3:
        resp_score += 5
    elif y_count > 0:
        resp_score += 2
    if n_count == 9:
        resp_score += 5
    elif n_count > 0:
        resp_score += 2

    score += resp_score
    subscores["response_coding"] = resp_score == 10
    feedback_parts.append(
        f"Response coding: {y_count} 'y' (need 3), {n_count} 'n' (need 9) ({resp_score}/10)"
    )

    # --- Criterion 5: Target words (Lemon, Key, Ball) in experiment (15 pts) ---
    has_lemon = (result.get("has_text_lemon") or independent_exp.get("has_text_lemon") or
                 result.get("conditions_has_lemon") or independent_cond.get("has_lemon"))
    has_key = (result.get("has_text_key") or independent_exp.get("has_text_key") or
               result.get("conditions_has_key") or independent_cond.get("has_key"))
    has_ball = (result.get("has_text_ball") or independent_exp.get("has_text_ball") or
                result.get("conditions_has_ball") or independent_cond.get("has_ball"))

    word_score = 0
    if has_lemon:
        word_score += 5
    if has_key:
        word_score += 5
    if has_ball:
        word_score += 5

    score += word_score
    subscores["target_words"] = word_score == 15
    feedback_parts.append(
        f"Target words: Lemon={has_lemon}, Key={has_key}, Ball={has_ball} ({word_score}/15)"
    )

    # --- Criterion 6: Memory task structure (20 pts) ---
    has_learning = result.get("has_learning_phase") or independent_exp.get("has_learning_phase")
    has_interference = result.get("has_interference_phase") or independent_exp.get("has_interference_phase")
    has_recall = result.get("has_free_recall") or independent_exp.get("has_free_recall")
    has_recognition = result.get("has_recognition_phase") or independent_exp.get("has_recognition_phase")

    struct_score = 0
    if has_learning:
        struct_score += 5
    if has_interference:
        struct_score += 5
    if has_recall:
        struct_score += 5
    if has_recognition:
        struct_score += 5

    score += struct_score
    subscores["task_structure"] = struct_score == 20
    feedback_parts.append(
        f"Structure: learning={has_learning}, interference={has_interference}, "
        f"recall={has_recall}, recognition={has_recognition} ({struct_score}/20)"
    )

    # --- Criterion 7: Code component with scoring logic (10 pts) ---
    has_code = result.get("has_code_component") or independent_exp.get("has_code_component")
    code_scoring = result.get("code_has_scoring") or independent_exp.get("code_has_scoring")
    code_recall = result.get("code_has_recall_score") or independent_exp.get("code_has_recall_score")
    code_recog = result.get("code_has_recognition_score") or independent_exp.get("code_has_recognition_score")

    code_score = 0
    if has_code:
        code_score += 3
    if code_scoring:
        code_score += 3
    if code_recall or code_recog:
        code_score += 4

    score += code_score
    subscores["scoring_code"] = code_score >= 7
    feedback_parts.append(
        f"Code: present={has_code}, scoring={code_scoring}, "
        f"recall_score={code_recall}, recog_score={code_recog} ({code_score}/10)"
    )

    # --- Criterion 8: Final scoring/summary screen (10 pts) ---
    has_summary = result.get("has_scoring_screen") or independent_exp.get("has_scoring_screen")
    if has_summary:
        score += 10
        subscores["summary_screen"] = True
        feedback_parts.append("Final scoring/summary screen present (10/10)")
    else:
        subscores["summary_screen"] = False
        feedback_parts.append("No scoring/summary screen found (0/10)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
