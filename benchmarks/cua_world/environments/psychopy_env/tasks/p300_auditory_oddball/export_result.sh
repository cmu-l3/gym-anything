#!/bin/bash
echo "=== Exporting p300_auditory_oddball result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import json, os, sys, datetime, csv
import xml.etree.ElementTree as ET

PSYEXP_FILE = "/home/ga/PsychoPyExperiments/p300_oddball.psyexp"
CONDITIONS_FILE = "/home/ga/PsychoPyExperiments/conditions/p300_conditions.csv"
RESULT_FILE = "/tmp/p300_auditory_oddball_result.json"

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
    "has_sound_component": False,
    "has_keyboard_response": False,
    "has_code_component": False,
    "has_rest_screen": False,
    "has_feedback_screen": False,
    "loop_count": 0,
    "has_conditions_ref": False,
    "param_count": 0,
    "line_count": 0,
    # Sound parameters found
    "sound_hz_values": [],
    "has_1000hz": False,
    "has_2000hz": False,
    "sound_duration_ms": 0.0,
    # Code component content
    "code_has_trigger": False,
    "code_has_parallel": False,
    "code_content_snippet": "",
    # Conditions file
    "conditions_total_rows": 0,
    "conditions_standard_rows": 0,
    "conditions_deviant_rows": 0,
    "conditions_has_tone_col": False,
    "conditions_has_trigger_col": False,
    "conditions_has_target_col": False,
    "conditions_standard_hz_correct": False,
    "conditions_deviant_hz_correct": False,
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

        results["conditions_total_rows"] = len(rows)

        # Identify columns
        tone_col = next((fn for fn in fieldnames if "tone" in fn.lower() or "hz" in fn.lower() or "freq" in fn.lower()), None)
        trigger_col = next((fn for fn in fieldnames if "trigger" in fn.lower() or "code" in fn.lower() or "marker" in fn.lower()), None)
        target_col = next((fn for fn in fieldnames if "target" in fn.lower() or "deviant" in fn.lower()), None)

        results["conditions_has_tone_col"] = tone_col is not None
        results["conditions_has_trigger_col"] = trigger_col is not None
        results["conditions_has_target_col"] = target_col is not None

        if tone_col:
            standard_rows = [r for r in rows if r.get(tone_col, "").strip() == "1000"]
            deviant_rows = [r for r in rows if r.get(tone_col, "").strip() == "2000"]
            results["conditions_standard_rows"] = len(standard_rows)
            results["conditions_deviant_rows"] = len(deviant_rows)
            results["conditions_standard_hz_correct"] = len(standard_rows) == 240
            results["conditions_deviant_hz_correct"] = len(deviant_rows) == 60

        if trigger_col:
            standard_trigs = [r for r in rows if r.get(trigger_col, "").strip() == "1"]
            deviant_trigs = [r for r in rows if r.get(trigger_col, "").strip() == "2"]
            if len(standard_trigs) == 240:
                results["conditions_standard_rows"] = max(results["conditions_standard_rows"], 240)
                results["conditions_standard_hz_correct"] = True
            if len(deviant_trigs) == 60:
                results["conditions_deviant_rows"] = max(results["conditions_deviant_rows"], 60)
                results["conditions_deviant_hz_correct"] = True

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
        all_code = []
        if routines is not None:
            rnames = []
            hz_values = set()
            for routine in routines:
                rname = routine.get("name", routine.tag)
                rnames.append(rname)
                rl = rname.lower()
                if any(kw in rl for kw in ["rest", "break", "between", "pause"]):
                    results["has_rest_screen"] = True
                if any(kw in rl for kw in ["feedback", "result", "summary", "score", "end"]):
                    results["has_feedback_screen"] = True

                for comp in routine:
                    ctag = comp.tag
                    cname = comp.get("name", "").lower()
                    if "Sound" in ctag or "sound" in cname:
                        results["has_sound_component"] = True
                        for param in comp:
                            pn = param.get("name", "")
                            pv = param.get("val", "").strip()
                            if pn in ("sound", "value", "hz", "freq", "frequency"):
                                try:
                                    hz_val = float(pv)
                                    hz_values.add(hz_val)
                                except:
                                    if pv.startswith("$"):
                                        hz_values.add(-1)  # dynamic
                            if pn == "stopVal":
                                try:
                                    dur = float(pv)
                                    if dur <= 0.05:
                                        results["sound_duration_ms"] = dur * 1000
                                except:
                                    pass
                    if "Keyboard" in ctag or "keyboard" in cname:
                        results["has_keyboard_response"] = True
                    if "Code" in ctag or "code" in cname:
                        results["has_code_component"] = True
                        for param in comp:
                            val = param.get("val", "")
                            if val:
                                all_code.append(val)

            results["routine_count"] = len(rnames)
            results["routine_names"] = rnames
            results["sound_hz_values"] = list(hz_values)
            results["has_1000hz"] = 1000.0 in hz_values or -1 in hz_values
            results["has_2000hz"] = 2000.0 in hz_values or -1 in hz_values

            combined_code = "\n".join(all_code)
            results["code_content_snippet"] = combined_code[:500]
            cl = combined_code.lower()
            results["code_has_trigger"] = any(kw in cl for kw in [
                "trigger", "trigger_code", "parallel", "port", "marker", "send", "code"
            ])
            results["code_has_parallel"] = "parallel" in cl or "lpt" in cl

        flow = root.find("Flow") or root.find(".//Flow")
        if flow is not None:
            results["loop_count"] = sum(1 for e in flow if "LoopInitiator" in e.tag)
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

cat /tmp/p300_auditory_oddball_result.json
echo "=== Export complete ==="
