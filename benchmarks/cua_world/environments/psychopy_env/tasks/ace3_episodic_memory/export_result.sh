#!/usr/bin/env bash
# Export results for ace3_episodic_memory task.
# Analyzes:
#   1. The psyexp XML file for routine structure, timing, keyboard/code components
#   2. The recognition conditions CSV for correct row counts and column content

set -euo pipefail
source /workspace/scripts/task_utils.sh

RESULT_PATH="/tmp/ace3_episodic_memory_result.json"
PSYEXP_PATH="/home/ga/PsychoPyExperiments/ace3_episodic_memory.psyexp"
CONDITIONS_PATH="/home/ga/PsychoPyExperiments/conditions/ace3_recognition.csv"

# ---- Check file existence and modification time ----
file_exists="false"
file_modified="false"
conditions_exists="false"
conditions_modified="false"

if [[ -f "$PSYEXP_PATH" ]]; then
    file_exists="true"
    if was_modified_after_start "$PSYEXP_PATH"; then
        file_modified="true"
    fi
fi

if [[ -f "$CONDITIONS_PATH" ]]; then
    conditions_exists="true"
    if was_modified_after_start "$CONDITIONS_PATH"; then
        conditions_modified="true"
    fi
fi

# ---- Parse psyexp and conditions via Python, write result JSON ----
python3 - <<PYEOF > "$RESULT_PATH"
import xml.etree.ElementTree as ET
import json, os, csv, sys

psyexp_path = "$PSYEXP_PATH"
cond_path = "$CONDITIONS_PATH"

result = {
    "file_exists": $file_exists,
    "file_modified": $file_modified,
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
    "learning_timing_sec": 0.0,
    "has_text_lemon": False,
    "has_text_key": False,
    "has_text_ball": False,
    "interference_has_duration": False,
    "interference_duration_sec": 0.0,
    "conditions_exists": $conditions_exists,
    "conditions_modified": $conditions_modified,
    "conditions_total_rows": 0,
    "conditions_target_rows": 0,
    "conditions_foil_rows": 0,
    "conditions_has_word_col": False,
    "conditions_has_is_target_col": False,
    "conditions_has_correct_response_col": False,
    "conditions_correct_response_y_count": 0,
    "conditions_correct_response_n_count": 0,
    "conditions_has_lemon": False,
    "conditions_has_key": False,
    "conditions_has_ball": False,
}

# ---- Parse psyexp XML ----
if os.path.isfile(psyexp_path):
    try:
        tree = ET.parse(psyexp_path)
        root = tree.getroot()
        result["is_valid_xml"] = True

        routines = root.find("Routines") or root.find(".//Routines")
        all_code_text = []

        if routines is not None:
            rc = 0
            for routine in routines:
                rc += 1
                rname = routine.get("name", routine.tag).lower()

                if any(kw in rname for kw in ["learn", "study", "present", "word", "target", "stimul"]):
                    result["has_learning_phase"] = True
                if any(kw in rname for kw in ["interfere", "distract", "count", "math", "filler", "delay", "task"]):
                    result["has_interference_phase"] = True
                if any(kw in rname for kw in ["recall", "free", "retrieve", "remember"]):
                    result["has_free_recall"] = True
                if any(kw in rname for kw in ["recogni", "identify", "test", "probe"]):
                    result["has_recognition_phase"] = True
                if any(kw in rname for kw in ["score", "result", "summary", "feedback", "end", "final", "debrief"]):
                    result["has_scoring_screen"] = True

                for comp in routine:
                    ctag = comp.tag
                    cname = comp.get("name", "").lower()

                    if "Keyboard" in ctag or "keyboard" in cname:
                        if any(kw in rname for kw in ["recall", "free", "retrieve", "remember"]):
                            result["has_keyboard_recall"] = True
                        if any(kw in rname for kw in ["recogni", "identify", "test", "probe"]):
                            result["has_keyboard_recognition"] = True

                    if "Code" in ctag or "code" in cname:
                        result["has_code_component"] = True
                        for param in comp:
                            val = param.get("val", "")
                            if val:
                                all_code_text.append(val)

                    if "Text" in ctag or "text" in cname:
                        for param in comp:
                            val = param.get("val", "")
                            vl = val.lower() if val else ""
                            if "lemon" in vl:
                                result["has_text_lemon"] = True
                            if " key" in vl or vl.startswith("key") or "\nkey" in vl:
                                result["has_text_key"] = True
                            if "ball" in vl:
                                result["has_text_ball"] = True
                            # Check timing for learning
                            if param.get("name") == "stopVal" and val:
                                try:
                                    dur = float(val)
                                    if 1.5 <= dur <= 3.5 and any(kw in rname for kw in ["learn", "study", "present", "word", "stimul"]):
                                        result["learning_timing_sec"] = dur
                                except ValueError:
                                    pass

                    # Interference duration
                    if any(kw in rname for kw in ["interfere", "distract", "count", "math", "filler", "delay"]):
                        for param in comp:
                            if param.get("name") in ("stopVal",) and param.get("val", ""):
                                try:
                                    dur = float(param.get("val", "0"))
                                    if dur >= 30:
                                        result["interference_has_duration"] = True
                                        result["interference_duration_sec"] = max(result["interference_duration_sec"], dur)
                                except ValueError:
                                    pass

            result["routine_count"] = rc

        combined_code = "\n".join(all_code_text).lower()
        if combined_code:
            result["code_has_scoring"] = any(kw in combined_code for kw in ["score", "correct", "hit", "tally"])
            result["code_has_recall_score"] = any(kw in combined_code for kw in ["recall_score", "recall score", "free_recall", "recall_hit", "n_recall", "nrecall", "recallscore"])
            result["code_has_recognition_score"] = any(kw in combined_code for kw in ["recog_score", "recognition_score", "recog_hit", "n_recog", "nrecog", "recognitionscore"])

        flow = root.find("Flow") or root.find(".//Flow")
        if flow is not None:
            result["loop_count"] = sum(1 for e in flow if "LoopInitiator" in e.tag)
            for elem in flow:
                if "Loop" in elem.tag:
                    for param in elem:
                        if param.get("name") == "conditionsFile" and param.get("val", "").strip():
                            result["has_conditions_ref"] = True

    except Exception as e:
        result["parse_error"] = str(e)

# ---- Parse conditions CSV ----
if os.path.isfile(cond_path):
    try:
        with open(cond_path, newline="") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            fieldnames = [fn.lower() for fn in (reader.fieldnames or [])]
            orig_fieldnames = reader.fieldnames or []

        result["conditions_total_rows"] = len(rows)

        word_col = next((fn for fn in orig_fieldnames if fn.lower() in ("word", "stimulus", "item", "stim")), None)
        target_col = next((fn for fn in orig_fieldnames if fn.lower() in ("is_target", "target", "istarget", "is_tgt")), None)
        resp_col = next((fn for fn in orig_fieldnames if fn.lower() in ("correct_response", "correct_resp", "correctresponse", "answer", "correct_key")), None)

        result["conditions_has_word_col"] = word_col is not None
        result["conditions_has_is_target_col"] = target_col is not None
        result["conditions_has_correct_response_col"] = resp_col is not None

        if target_col:
            targets = [r for r in rows if r.get(target_col, "").strip() in ("1", "1.0", "True", "true", "yes")]
            foils = [r for r in rows if r.get(target_col, "").strip() in ("0", "0.0", "False", "false", "no")]
            result["conditions_target_rows"] = len(targets)
            result["conditions_foil_rows"] = len(foils)

        if resp_col:
            y_rows = [r for r in rows if r.get(resp_col, "").strip().lower() in ("y", "yes")]
            n_rows = [r for r in rows if r.get(resp_col, "").strip().lower() in ("n", "no")]
            result["conditions_correct_response_y_count"] = len(y_rows)
            result["conditions_correct_response_n_count"] = len(n_rows)

        if word_col:
            all_words = [r.get(word_col, "").strip().lower() for r in rows]
            result["conditions_has_lemon"] = "lemon" in all_words
            result["conditions_has_key"] = "key" in all_words
            result["conditions_has_ball"] = "ball" in all_words

    except Exception as e:
        result["conditions_parse_error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

echo "=== ace3_episodic_memory export complete: $RESULT_PATH ==="
