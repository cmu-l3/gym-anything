#!/bin/bash
echo "=== Exporting nback_adaptive_experiment result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import json, os, sys, datetime, csv
import xml.etree.ElementTree as ET

PSYEXP_FILE = "/home/ga/PsychoPyExperiments/nback_experiment.psyexp"
CONDITIONS_FILE = "/home/ga/PsychoPyExperiments/conditions/nback_conditions.csv"
RESULT_FILE = "/tmp/nback_adaptive_experiment_result.json"

results = {
    "file_exists": False,
    "file_modified": False,
    "is_valid_xml": False,
    "conditions_exists": False,
    "conditions_modified": False,
    "result_nonce": "",
    "task_start_time": 0,
    "timestamp": datetime.datetime.now().isoformat(),
    # Experiment structure
    "routine_count": 0,
    "routine_names": [],
    "has_fixation_component": False,
    "has_letter_text_component": False,
    "has_blank_isi_component": False,
    "has_keyboard_response": False,
    "has_code_component": False,
    "has_block_summary": False,
    "loop_count": 0,
    "has_conditions_ref": False,
    "param_count": 0,
    "line_count": 0,
    # Code component content
    "code_has_nback_logic": False,
    "code_has_accuracy_tracking": False,
    "code_has_adaptive_logic": False,
    "code_content_snippet": "",
    # Timing checks
    "fixation_duration_ms": 0.0,
    "letter_duration_ms": 0.0,
    "isi_duration_ms": 0.0,
    # Conditions file
    "conditions_row_count": 0,
    "conditions_has_letter_col": False,
    "conditions_has_target_col": False,
    "conditions_target_rate": 0.0,
    "conditions_uses_consonants": False,
}

try:
    with open("/home/ga/.task_start_time") as f:
        results["task_start_time"] = int(f.read().strip())
except:
    pass
try:
    with open("/home/ga/.task_nonce") as f:
        results["result_nonce"] = f.read().strip()
except:
    pass

# ---- Analyze conditions file ----
if os.path.isfile(CONDITIONS_FILE):
    results["conditions_exists"] = True
    cond_mtime = int(os.path.getmtime(CONDITIONS_FILE))
    if cond_mtime > results["task_start_time"]:
        results["conditions_modified"] = True

    try:
        with open(CONDITIONS_FILE, newline="") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            fieldnames = reader.fieldnames or []

        results["conditions_row_count"] = len(rows)
        results["conditions_has_letter_col"] = any("letter" in fn.lower() for fn in fieldnames)
        results["conditions_has_target_col"] = any(
            "target" in fn.lower() or "is_target" in fn.lower() for fn in fieldnames
        )

        # Determine target rate
        target_col = next(
            (fn for fn in fieldnames if "target" in fn.lower() or "is_target" in fn.lower()), None
        )
        letter_col = next((fn for fn in fieldnames if "letter" in fn.lower()), None)
        if target_col and rows:
            try:
                target_vals = [float(r[target_col]) for r in rows if r.get(target_col, "").strip()]
                if target_vals:
                    results["conditions_target_rate"] = sum(target_vals) / len(target_vals)
            except:
                pass

        # Check consonants only
        vowels = set("aeiouAEIOU")
        if letter_col:
            letters = [r.get(letter_col, "").strip() for r in rows if r.get(letter_col, "").strip()]
            if letters and not any(l[0] in vowels for l in letters if l):
                results["conditions_uses_consonants"] = True

    except Exception as e:
        print(f"Conditions analysis error: {e}", file=sys.stderr)

# ---- Analyze psyexp file ----
if os.path.isfile(PSYEXP_FILE):
    results["file_exists"] = True
    with open(PSYEXP_FILE) as f:
        results["line_count"] = sum(1 for _ in f)
    mtime = int(os.path.getmtime(PSYEXP_FILE))
    if mtime > results["task_start_time"]:
        results["file_modified"] = True

    try:
        tree = ET.parse(PSYEXP_FILE)
        root = tree.getroot()
        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["is_valid_xml"] = True
        results["param_count"] = len(root.findall(".//*[@name]"))

        routines = root.find("Routines") or root.find(".//Routines")
        if routines is not None:
            rnames = []
            all_code_text = []
            for routine in routines:
                rname = routine.get("name", routine.tag)
                rnames.append(rname)
                rl = rname.lower()

                if "summary" in rl or "break" in rl or "between" in rl or "block_info" in rl or "feedback" in rl:
                    results["has_block_summary"] = True

                for comp in routine:
                    ctag = comp.tag
                    cname = comp.get("name", "").lower()

                    if "Text" in ctag or "text" in ctag:
                        for param in comp:
                            pn = param.get("name", "")
                            pv = param.get("val", "")
                            if pn == "stopVal":
                                try:
                                    dur = float(pv)
                                    if abs(dur - 0.2) < 0.05:
                                        results["fixation_duration_ms"] = dur * 1000
                                        results["has_fixation_component"] = True
                                    elif abs(dur - 0.5) < 0.1:
                                        results["letter_duration_ms"] = dur * 1000
                                        results["has_letter_text_component"] = True
                                    elif abs(dur - 0.3) < 0.1:
                                        results["isi_duration_ms"] = dur * 1000
                                        results["has_blank_isi_component"] = True
                                except:
                                    pass
                            if pn == "text" and ("+" in pv or "fixat" in pv.lower()):
                                results["has_fixation_component"] = True

                    if "Keyboard" in ctag or "keyboard" in cname:
                        results["has_keyboard_response"] = True

                    if "Code" in ctag or "code" in cname:
                        results["has_code_component"] = True
                        for param in comp:
                            pv = param.get("val", "")
                            if pv:
                                all_code_text.append(pv)

            results["routine_count"] = len(rnames)
            results["routine_names"] = rnames

            # Analyze code component content
            combined_code = "\n".join(all_code_text)
            results["code_content_snippet"] = combined_code[:500]
            code_lower = combined_code.lower()
            results["code_has_nback_logic"] = (
                "n_back" in code_lower or "nback" in code_lower or
                "n-back" in code_lower or "back_n" in code_lower or
                "n_level" in code_lower or "nlevel" in code_lower
            )
            results["code_has_accuracy_tracking"] = (
                "accuracy" in code_lower or "correct" in code_lower or "acc" in code_lower
            )
            results["code_has_adaptive_logic"] = (
                ("85" in combined_code or "0.85" in combined_code) and
                ("55" in combined_code or "0.55" in combined_code) and
                ("n_level" in code_lower or "nlevel" in code_lower or "nback" in code_lower)
            )

        # Flow: count loops and conditions ref
        flow = root.find("Flow") or root.find(".//Flow")
        if flow is not None:
            loop_count = sum(1 for e in flow if "LoopInitiator" in e.tag)
            results["loop_count"] = loop_count
            for elem in flow:
                if "Loop" in elem.tag:
                    for param in elem:
                        if param.get("name") == "conditionsFile" and param.get("val", "").strip():
                            results["has_conditions_ref"] = True

    except Exception as e:
        print(f"psyexp analysis error: {e}", file=sys.stderr)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)
os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/nback_adaptive_experiment_result.json
echo "=== Export complete ==="
