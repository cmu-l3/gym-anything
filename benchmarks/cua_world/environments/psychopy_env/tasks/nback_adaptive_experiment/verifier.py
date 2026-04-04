#!/usr/bin/env python3
"""
Verifier for nback_adaptive_experiment task.

Background: The n-back task (Kirchner, 1958) is a working memory capacity paradigm used
extensively in cognitive neuroscience and clinical neuropsychology. The adaptive variant
(Owen et al., 2005; Jaeggi et al., 2008) adjusts the n-back level dynamically based on
individual performance, keeping the task in the participant's zone of proximal development.
This makes it suitable for both healthy populations and clinical groups (e.g., ADHD, schizophrenia).

Scoring (100 points):
  1. Experiment file: exists, valid XML, created during task (10 pts)
  2. Conditions file: exists, >=30 rows, has 'letter' and 'is_target' columns,
     target rate 25-45%, consonants only (20 pts)
  3. Trial structure: fixation (200ms) + letter (500ms) + blank ISI (300ms) components (15 pts)
  4. Keyboard response component available during letter and ISI (10 pts)
  5. Code component with adaptive n-back logic (accuracy thresholds 85%/55%) (20 pts)
  6. At least 3 loops/blocks in the experiment (10 pts)
  7. Between-block summary/feedback routine present (15 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import csv
import logging
import re

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/nback_adaptive_experiment_result.json"


def _parse_nback_psyexp(filepath):
    """Independent parse of n-back psyexp file."""
    import xml.etree.ElementTree as ET

    data = {
        "is_valid_xml": False,
        "routine_count": 0,
        "routine_names": [],
        "has_fixation": False,
        "has_letter_stimulus": False,
        "has_isi": False,
        "has_keyboard": False,
        "has_code_component": False,
        "has_block_summary": False,
        "loop_count": 0,
        "has_conditions_ref": False,
        "code_has_adaptive": False,
        "code_has_accuracy": False,
        "code_has_nback": False,
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
            rnames = []
            for routine in routines:
                rname = routine.get("name", routine.tag)
                rnames.append(rname)
                rl = rname.lower()
                if any(kw in rl for kw in ["summary", "break", "between", "block_info", "feedback", "rest"]):
                    data["has_block_summary"] = True

                for comp in routine:
                    ctag = comp.tag
                    cname = comp.get("name", "").lower()
                    if "Text" in ctag:
                        for param in comp:
                            pn = param.get("name", "")
                            pv = param.get("val", "")
                            if pn == "text":
                                if "+" in pv:
                                    data["has_fixation"] = True
                                if "$letter" in pv or "$stimulus" in pv or "$stim" in pv:
                                    data["has_letter_stimulus"] = True
                            if pn == "stopVal":
                                try:
                                    d = float(pv)
                                    if abs(d - 0.2) < 0.05:
                                        data["has_fixation"] = True
                                    if 0.4 <= d <= 0.6:
                                        data["has_letter_stimulus"] = True
                                    if 0.2 <= d <= 0.4:
                                        data["has_isi"] = True
                                except Exception:
                                    pass
                    if "Keyboard" in ctag or "keyboard" in cname:
                        data["has_keyboard"] = True
                    if "Code" in ctag or "code" in cname:
                        data["has_code_component"] = True
                        for param in comp:
                            val = param.get("val", "")
                            if val:
                                all_code.append(val)

            data["routine_count"] = len(rnames)
            data["routine_names"] = rnames

        combined = "\n".join(all_code)
        cl = combined.lower()
        data["code_has_nback"] = any(
            kw in cl for kw in ["n_back", "nback", "n-back", "n_level", "nlevel"]
        )
        data["code_has_accuracy"] = any(
            kw in cl for kw in ["accuracy", "correct", "acc_"]
        )
        data["code_has_adaptive"] = (
            data["code_has_nback"]
            and data["code_has_accuracy"]
            and ("85" in combined or "0.85" in combined)
            and ("55" in combined or "0.55" in combined)
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
        logger.warning(f"N-back parse error: {e}")

    return data


def _parse_nback_conditions(filepath):
    """Parse the n-back conditions CSV."""
    data = {
        "exists": False,
        "row_count": 0,
        "has_letter_col": False,
        "has_target_col": False,
        "target_rate": 0.0,
        "consonants_only": False,
    }
    if not os.path.isfile(filepath):
        return data

    data["exists"] = True
    vowels = set("aeiouAEIOU")
    try:
        with open(filepath, newline="") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            fieldnames = reader.fieldnames or []

        data["row_count"] = len(rows)
        data["has_letter_col"] = any("letter" in fn.lower() for fn in fieldnames)
        data["has_target_col"] = any(
            "target" in fn.lower() for fn in fieldnames
        )

        target_col = next(
            (fn for fn in fieldnames if "target" in fn.lower()), None
        )
        letter_col = next(
            (fn for fn in fieldnames if "letter" in fn.lower()), None
        )

        if target_col and rows:
            try:
                tvals = [
                    float(r[target_col])
                    for r in rows
                    if r.get(target_col, "").strip()
                ]
                if tvals:
                    data["target_rate"] = sum(tvals) / len(tvals)
            except Exception:
                pass

        if letter_col and rows:
            letters = [r.get(letter_col, "").strip() for r in rows if r.get(letter_col)]
            if letters and all(l and l[0].upper() not in vowels for l in letters):
                data["consonants_only"] = True

    except Exception as e:
        logger.warning(f"Conditions parse error: {e}")

    return data


def verify_nback_adaptive_experiment(traj, env_info, task_info):
    """
    Verify the adaptive n-back working memory experiment.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    subscores = {}
    metadata = task_info.get("metadata", {})

    # --- Step 1: Copy export JSON ---
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
    independent = {}
    psyexp_path = metadata.get("output_file", "/home/ga/PsychoPyExperiments/nback_experiment.psyexp")
    tmp2 = tempfile.NamedTemporaryFile(delete=False, suffix=".psyexp")
    tmp2.close()
    try:
        copy_from_env(psyexp_path, tmp2.name)
        independent = _parse_nback_psyexp(tmp2.name)
    except Exception as e:
        logger.warning(f"Independent psyexp parse failed: {e}")
    finally:
        try:
            os.unlink(tmp2.name)
        except Exception:
            pass

    # --- Independent re-parse of conditions file ---
    conditions_ind = {}
    conditions_path = metadata.get("conditions_file",
                                   "/home/ga/PsychoPyExperiments/conditions/nback_conditions.csv")
    tmp3 = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
    tmp3.close()
    try:
        copy_from_env(conditions_path, tmp3.name)
        conditions_ind = _parse_nback_conditions(tmp3.name)
    except Exception as e:
        logger.warning(f"Conditions parse failed: {e}")
    finally:
        try:
            os.unlink(tmp3.name)
        except Exception:
            pass

    # --- Criterion 1: File exists, valid, created during task (10 pts) ---
    file_exists = result.get("file_exists") or independent.get("is_valid_xml")
    file_modified = result.get("file_modified", False)
    valid_xml = result.get("is_valid_xml") or independent.get("is_valid_xml")

    if file_exists and valid_xml and file_modified:
        score += 10
        subscores["file_valid"] = True
        feedback_parts.append("Experiment file created and valid (10/10)")
    elif file_exists and valid_xml:
        score += 5
        subscores["file_valid"] = False
        feedback_parts.append("File is valid XML but not newly created (5/10)")
    else:
        subscores["file_valid"] = False
        feedback_parts.append("Experiment file missing or invalid (0/10)")

    # --- Criterion 2: Conditions file (20 pts) ---
    cond_exists = result.get("conditions_exists") or conditions_ind.get("exists")
    cond_row_count = max(result.get("conditions_row_count", 0),
                         conditions_ind.get("row_count", 0))
    has_letter = result.get("conditions_has_letter_col") or conditions_ind.get("has_letter_col")
    has_target = result.get("conditions_has_target_col") or conditions_ind.get("has_target_col")
    target_rate = max(result.get("conditions_target_rate", 0.0),
                      conditions_ind.get("target_rate", 0.0))
    consonants = result.get("conditions_uses_consonants") or conditions_ind.get("consonants_only")
    cond_modified = result.get("conditions_modified", False)

    cond_score = 0
    if cond_exists and cond_modified:
        cond_score += 5
    if cond_row_count >= 30:
        cond_score += 5
    if has_letter and has_target:
        cond_score += 5
    if 0.25 <= target_rate <= 0.45:
        cond_score += 3
    if consonants:
        cond_score += 2

    score += cond_score
    subscores["conditions"] = cond_score > 0
    feedback_parts.append(
        f"Conditions file: {cond_row_count} rows, letter={has_letter}, target_col={has_target}, "
        f"target_rate={target_rate:.2f}, consonants={consonants} ({cond_score}/20)"
    )

    # --- Criterion 3: Trial timing structure (15 pts) ---
    has_fix = result.get("has_fixation_component") or independent.get("has_fixation")
    has_letter_comp = result.get("has_letter_text_component") or independent.get("has_letter_stimulus")
    has_isi = result.get("has_blank_isi_component") or independent.get("has_isi")

    timing_score = 0
    if has_fix:
        timing_score += 5
    if has_letter_comp:
        timing_score += 5
    if has_isi:
        timing_score += 5

    score += timing_score
    subscores["timing"] = timing_score >= 10
    feedback_parts.append(
        f"Trial timing: fixation={has_fix}, letter={has_letter_comp}, ISI={has_isi} ({timing_score}/15)"
    )

    # --- Criterion 4: Keyboard response (10 pts) ---
    has_kb = result.get("has_keyboard_response") or independent.get("has_keyboard")
    if has_kb:
        score += 10
        subscores["keyboard"] = True
        feedback_parts.append("Keyboard response component present (10/10)")
    else:
        subscores["keyboard"] = False
        feedback_parts.append("No keyboard response component found (0/10)")

    # --- Criterion 5: Adaptive code component (20 pts) ---
    has_code = result.get("has_code_component") or independent.get("has_code_component")
    code_nback = result.get("code_has_nback_logic") or independent.get("code_has_nback")
    code_acc = result.get("code_has_accuracy_tracking") or independent.get("code_has_accuracy")
    code_adaptive = result.get("code_has_adaptive_logic") or independent.get("code_has_adaptive")

    code_score = 0
    if has_code:
        code_score += 5
    if code_nback:
        code_score += 5
    if code_acc:
        code_score += 5
    if code_adaptive:
        code_score += 5

    score += code_score
    subscores["adaptive_code"] = code_adaptive
    feedback_parts.append(
        f"Code component: present={has_code}, n-back logic={code_nback}, "
        f"accuracy={code_acc}, adaptive thresholds={code_adaptive} ({code_score}/20)"
    )

    # --- Criterion 6: Multiple blocks/loops (10 pts) ---
    loop_count = max(result.get("loop_count", 0), independent.get("loop_count", 0))
    if loop_count >= 3:
        score += 10
        subscores["loops"] = True
        feedback_parts.append(f"At least 3 blocks/loops found ({loop_count} loops) (10/10)")
    elif loop_count >= 1:
        score += 4
        subscores["loops"] = False
        feedback_parts.append(f"Only {loop_count} loop(s) found — need at least 3 blocks (4/10)")
    else:
        subscores["loops"] = False
        feedback_parts.append("No loops found — trial sequence structure missing (0/10)")

    # --- Criterion 7: Between-block summary (15 pts) ---
    has_summary = result.get("has_block_summary") or independent.get("has_block_summary")
    if has_summary:
        score += 15
        subscores["block_summary"] = True
        feedback_parts.append("Between-block summary/feedback routine present (15/15)")
    else:
        subscores["block_summary"] = False
        feedback_parts.append("No between-block summary routine found (0/15)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
