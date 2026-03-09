#!/usr/bin/env bash
# Export results for fear_conditioning_coder task.
# Analyzes the Python Coder script via AST and regex to check:
#   - Correct imports (psychopy.core, visual, data, event)
#   - StairHandler usage with required parameters
#   - ExperimentHandler / data saving
#   - Habituation and acquisition phase definitions
#   - CS/US timing parameters
#   - Rating scale component
#   - Counterbalancing logic

set -euo pipefail
source /workspace/scripts/task_utils.sh

RESULT_PATH="/tmp/fear_conditioning_coder_result.json"
SCRIPT_PATH="/home/ga/PsychoPyExperiments/fear_conditioning.py"

file_exists="false"
file_modified="false"

if [[ -f "$SCRIPT_PATH" ]]; then
    file_exists="true"
    if was_modified_after_start "$SCRIPT_PATH"; then
        file_modified="true"
    fi
fi

python3 - <<PYEOF > "$RESULT_PATH"
import json, os, re, ast, sys

script_path = "$SCRIPT_PATH"

result = {
    "file_exists": $file_exists,
    "file_modified": $file_modified,
    "line_count": 0,
    "is_valid_python": False,
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
    "has_white_noise": False,
    "cs_duration_present": False,
    "us_onset_present": False,
    "us_duration_present": False,
    "has_data_directory": False,
    "has_participant_var": False,
    "has_date_in_filename": False,
    "has_visual_square": False,
}

if not os.path.isfile(script_path):
    print(json.dumps(result))
    sys.exit(0)

with open(script_path) as f:
    source = f.read()

result["line_count"] = source.count("\n") + 1

# Check Python validity
try:
    ast.parse(source)
    result["is_valid_python"] = True
except SyntaxError as e:
    result["syntax_error"] = str(e)

src_lower = source.lower()

# ---- Imports ----
result["imports_core"] = bool(re.search(r"from\s+psychopy\s+import.*\bcore\b|import\s+psychopy\.core", source))
result["imports_visual"] = bool(re.search(r"from\s+psychopy\s+import.*\bvisual\b|import\s+psychopy\.visual", source))
result["imports_data"] = bool(re.search(r"from\s+psychopy\s+import.*\bdata\b|import\s+psychopy\.data", source))
result["imports_event"] = bool(re.search(r"from\s+psychopy\s+import.*\bevent\b|import\s+psychopy\.event", source))

# ---- StairHandler ----
result["has_stairhandler"] = bool(re.search(r"StairHandler", source))

if result["has_stairhandler"]:
    # Extract startVal
    m = re.search(r"startVal\s*=\s*([\d.]+)", source)
    if m:
        result["stair_startval"] = float(m.group(1))

    # Extract stepSizes
    m = re.search(r"stepSizes\s*=\s*\[([^\]]+)\]", source)
    if m:
        try:
            result["stair_stepsizes"] = [float(x.strip()) for x in m.group(1).split(",")]
        except Exception:
            pass

    # Extract nReversals
    m = re.search(r"nReversals\s*=\s*(\d+)", source)
    if m:
        result["stair_nreversals"] = int(m.group(1))

    # Extract stepType
    m = re.search(r"stepType\s*=\s*['\"](\w+)['\"]", source)
    if m:
        result["stair_steptype"] = m.group(1)

    # Check parameter correctness
    sv_ok = result["stair_startval"] == 0.8
    ss_ok = result["stair_stepsizes"] in ([0.1, 0.05], [0.1, 0.05, 0.025])
    nr_ok = result["stair_nreversals"] is not None and result["stair_nreversals"] >= 4
    st_ok = result["stair_steptype"] == "lin"
    result["stairhandler_params_correct"] = sv_ok and (ss_ok or result["stair_stepsizes"] is not None) and nr_ok

# ---- ExperimentHandler / data saving ----
result["has_experiment_handler"] = bool(re.search(r"ExperimentHandler", source))
result["has_data_save"] = bool(re.search(r"\.save[Csv]|saveAsWideText|saveAsText|\.addData|experiment\.close", source, re.IGNORECASE))

# ---- Phase structure ----
result["has_habituation_phase"] = bool(re.search(r"habitu", src_lower))
result["has_acquisition_phase"] = bool(re.search(r"acqui", src_lower))
result["has_cs_plus"] = bool(re.search(r"cs[\s_+]*\+|cs_?plus|csplus", src_lower))
result["has_cs_minus"] = bool(re.search(r"cs[\s_]*-|cs_?minus|csminus", src_lower))
result["has_us"] = bool(re.search(r"\bus\b|unconditioned|white.?noise|sound.*us|us.*sound", src_lower))

# ---- Rating scale ----
result["has_rating_scale"] = bool(re.search(r"RatingScale|ratingscale|rating_scale|Slider|slider", source))
result["has_rating_logic"] = bool(re.search(r"rating\s*[><=!]+\s*[3-9]|aversive|subjective", src_lower))

# ---- Counterbalancing ----
result["has_counterbalancing"] = bool(re.search(r"modulo|%\s*2|participant.*%|counterbal", src_lower))

# ---- White noise / sound ----
result["has_white_noise"] = bool(re.search(r"white.?noise|WhiteNoise|noise.*sound|sound.*noise|Sound.*noise|psychopy.*sound", src_lower))

# ---- Timing ----
result["cs_duration_present"] = bool(re.search(r"\b4\.0\b|\bcs.*4\b|\bduration.*4\b|4\.0\s*#.*cs", source))
result["us_onset_present"] = bool(re.search(r"3\.5|us.*onset|onset.*us|us.*delay", src_lower))
result["us_duration_present"] = bool(re.search(r"\b1\.0\b|\bus.*1\b|\bduration.*us.*1\b", src_lower))

# ---- Data directory and filename ----
result["has_data_directory"] = bool(re.search(r"PsychoPyExperiments/data|/home/ga.*data", source))
result["has_participant_var"] = bool(re.search(r"participant|expInfo\[.participant.\]|info\[.participant.\]", src_lower))
result["has_date_in_filename"] = bool(re.search(r"date|strftime|datetime", src_lower))

# ---- Visual squares for CS ----
result["has_visual_square"] = bool(re.search(r"Rect|rect|square|ShapeStim.*square|fillColor.*blue|fillColor.*yellow", source))

print(json.dumps(result, indent=2))
PYEOF

echo "=== fear_conditioning_coder export complete: $RESULT_PATH ==="
