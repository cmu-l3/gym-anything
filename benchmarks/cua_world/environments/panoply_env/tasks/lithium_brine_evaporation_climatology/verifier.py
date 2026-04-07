#!/usr/bin/env python3
"""
Verifier for lithium_brine_evaporation_climatology task.

Evaluates spatial data extraction, unit conversion, and applied geophysical reasoning.
"""

import json
import os
import tempfile
import re


def extract_float(s):
    """Safely extract the first floating point number from a string."""
    match = re.search(r'-?\d+(\.\d+)?', s)
    if match:
        return float(match.group(0))
    return None


def verify_lithium_brine_evaporation_climatology(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON from the VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/lithium_brine_evaporation_climatology_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = int(result.get('task_start', 0))

    # ----------------------------------------------------------------
    # Criterion 1: Tibet Plot Exported (20 pts)
    # ----------------------------------------------------------------
    tibet_exists = result.get('tibet_png_exists', False)
    tibet_mtime = int(result.get('tibet_png_mtime', 0))
    tibet_size = int(result.get('tibet_png_size', 0))

    if tibet_exists and tibet_mtime >= task_start and tibet_size >= 15000:
        score += 20
        feedback.append(f"Tibet plot exported ({tibet_size} bytes)")
    elif tibet_exists and tibet_mtime >= task_start and tibet_size >= 5000:
        score += 10
        feedback.append(f"Tibet plot present but small ({tibet_size} bytes, expected >=15KB)")
    else:
        feedback.append(f"Tibet plot missing or not created during task "
                        f"(exists={tibet_exists}, size={tibet_size})")

    # ----------------------------------------------------------------
    # Criterion 2: Andes Plot Exported (20 pts)
    # ----------------------------------------------------------------
    andes_exists = result.get('andes_png_exists', False)
    andes_mtime = int(result.get('andes_png_mtime', 0))
    andes_size = int(result.get('andes_png_size', 0))

    if andes_exists and andes_mtime >= task_start and andes_size >= 15000:
        score += 20
        feedback.append(f"Andes plot exported ({andes_size} bytes)")
    elif andes_exists and andes_mtime >= task_start and andes_size >= 5000:
        score += 10
        feedback.append(f"Andes plot present but small ({andes_size} bytes, expected >=15KB)")
    else:
        feedback.append(f"Andes plot missing or not created during task "
                        f"(exists={andes_exists}, size={andes_size})")

    # ----------------------------------------------------------------
    # Criterion 3: Report Format Correct (20 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    tibet_temp_raw = result.get('tibet_temp', '').strip()
    andes_temp_raw = result.get('andes_temp', '').strip()
    feasibility_raw = result.get('feasibility', '').strip()

    has_all_fields = bool(tibet_temp_raw) and bool(andes_temp_raw) and bool(feasibility_raw)

    if report_exists and report_mtime >= task_start and has_all_fields:
        score += 20
        feedback.append(f"Report format correct (Tibet: '{tibet_temp_raw}', Andes: '{andes_temp_raw}', Feasible: '{feasibility_raw}')")
    elif report_exists and report_mtime >= task_start:
        score += 10
        missing = [f for f, v in [('TIBET_JAN_TEMP_C', tibet_temp_raw),
                                   ('ANDES_JAN_TEMP_C', andes_temp_raw),
                                   ('WINTER_EVAPORATION_FEASIBLE_TIBET', feasibility_raw)] if not v]
        feedback.append(f"Report present but missing fields: {missing}")
    else:
        feedback.append(f"Report missing or not created during task (exists={report_exists})")

    # ----------------------------------------------------------------
    # Criterion 4: Quantitative Accuracy (20 pts)
    # ----------------------------------------------------------------
    t_val = extract_float(tibet_temp_raw)
    a_val = extract_float(andes_temp_raw)
    quant_verified = False

    if t_val is not None and a_val is not None:
        # Tibetan Plateau in January is extremely cold (typically -10°C to -25°C)
        # Atacama/Andes in January (Southern summer) is warm (typically 5°C to 20°C)
        if t_val < 0.0 and a_val > 0.0:
            score += 20
            quant_verified = True
            feedback.append(f"Quantitative accuracy passed: Tibet {t_val}°C (<0), Andes {a_val}°C (>0)")
        else:
            feedback.append(f"Quantitative accuracy failed: Tibet {t_val}°C, Andes {a_val}°C. Did agent forget Kelvin->Celsius conversion?")
    else:
        feedback.append(f"Could not parse temperature values (Tibet parsed: {t_val}, Andes parsed: {a_val})")

    # ----------------------------------------------------------------
    # Criterion 5: Feasibility Conclusion (20 pts)
    # ----------------------------------------------------------------
    f_val = feasibility_raw.upper()
    if 'NO' in f_val or 'FALSE' in f_val:
        score += 20
        feedback.append("Feasibility conclusion correct (NO - brine freezes)")
    elif 'YES' in f_val or 'TRUE' in f_val:
        feedback.append("Feasibility conclusion incorrect (Agent answered YES)")
    else:
        if f_val:
            feedback.append(f"Feasibility conclusion unclear ('{f_val}')")
        else:
            feedback.append("Feasibility conclusion missing")

    # Final logic
    passed = (score >= 80) and quant_verified

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }