#!/usr/bin/env python3
"""
Verifier for coral_bleaching_thermal_stress task.

Occupation: Marine Biologist / Coral Reef Ecosystem Scientist (NOAA Coral Reef Watch)
Industry: Marine Conservation / Government Environmental Science
Difficulty: very_hard

Scoring criteria (100 pts total, pass threshold = 80):
  1. Global SST plot exported (25 pts): reef_stress_global_aug.png exists,
     was created after task start, and has size >= 20KB.
  2. Hotspot SST plot exported (25 pts): reef_stress_hotspot.png exists,
     was created after task start, and has size >= 15KB.
  3. Thermal stress report complete (25 pts): thermal_stress_report.txt exists,
     was created after task start, and contains all required fields.
  4. Scientific correctness (25 pts): PEAK_SST value is >= 28.0°C and
     BLEACHING_RISK is classified as HIGH (consistent with August warm pool SST).
"""

import json
import os
import tempfile


def verify_coral_bleaching_thermal_stress(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON from the VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/coral_bleaching_thermal_stress_result.json', tmp.name)
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
    # Criterion 1: Global SST plot exported (25 pts)
    # ----------------------------------------------------------------
    png1_exists = result.get('png1_exists', False)
    png1_mtime = int(result.get('png1_mtime', 0))
    png1_size = int(result.get('png1_size', 0))

    if png1_exists and png1_mtime >= task_start and png1_size >= 20000:
        score += 25
        feedback.append(f"Global SST plot exported ({png1_size} bytes)")
    elif png1_exists and png1_mtime >= task_start and png1_size >= 5000:
        score += 12
        feedback.append(f"Global SST plot present but small ({png1_size} bytes, expected >=20KB)")
    else:
        feedback.append(f"Global SST plot missing or not created during task "
                        f"(exists={png1_exists}, size={png1_size}, mtime={png1_mtime} vs start={task_start})")

    # ----------------------------------------------------------------
    # Criterion 2: Hotspot zoom plot exported (25 pts)
    # ----------------------------------------------------------------
    png2_exists = result.get('png2_exists', False)
    png2_mtime = int(result.get('png2_mtime', 0))
    png2_size = int(result.get('png2_size', 0))

    if png2_exists and png2_mtime >= task_start and png2_size >= 15000:
        score += 25
        feedback.append(f"Hotspot SST plot exported ({png2_size} bytes)")
    elif png2_exists and png2_mtime >= task_start and png2_size >= 5000:
        score += 12
        feedback.append(f"Hotspot plot present but small ({png2_size} bytes, expected >=15KB)")
    else:
        feedback.append(f"Hotspot SST plot missing or not created during task "
                        f"(exists={png2_exists}, size={png2_size})")

    # ----------------------------------------------------------------
    # Criterion 3: Thermal stress report complete (25 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    peak_sst_raw = result.get('peak_sst', '').strip()
    bleaching_risk_raw = result.get('bleaching_risk', '').strip()
    hotspot_region_raw = result.get('hotspot_region', '').strip()

    has_all_fields = bool(peak_sst_raw) and bool(bleaching_risk_raw) and bool(hotspot_region_raw)

    if report_exists and report_mtime >= task_start and has_all_fields:
        score += 25
        feedback.append(f"Thermal stress report complete "
                        f"(region='{hotspot_region_raw}', sst='{peak_sst_raw}', risk='{bleaching_risk_raw}')")
    elif report_exists and report_mtime >= task_start:
        score += 10
        missing = [f for f, v in [('PEAK_SST', peak_sst_raw),
                                   ('BLEACHING_RISK', bleaching_risk_raw),
                                   ('HOTSPOT_REGION', hotspot_region_raw)] if not v]
        feedback.append(f"Report present but missing fields: {missing}")
    else:
        feedback.append(f"Thermal stress report missing or not created during task "
                        f"(exists={report_exists})")

    # ----------------------------------------------------------------
    # Criterion 4: Scientific correctness — PEAK_SST >= 28.0°C and risk = HIGH (25 pts)
    # ----------------------------------------------------------------
    # The Indo-Pacific Warm Pool in August has SST 28–31°C (well above bleaching threshold).
    # Any region the agent correctly identifies as 'hottest' will have SST >= 28°C.
    try:
        # Strip units like °C, C, degrees, etc.
        raw = peak_sst_raw.replace('°', '').replace('C', '').replace('degrees', '').strip()
        peak_sst_val = float(raw)
        risk_upper = bleaching_risk_raw.upper()
        risk_is_high = 'HIGH' in risk_upper

        if peak_sst_val >= 28.0 and risk_is_high:
            score += 25
            feedback.append(f"Scientific assessment correct: PEAK_SST={peak_sst_val:.1f}°C, RISK=HIGH")
        elif peak_sst_val >= 27.0:
            # Reasonable SST but possibly wrong risk classification
            score += 10
            feedback.append(f"PEAK_SST={peak_sst_val:.1f}°C plausible but BLEACHING_RISK should be HIGH "
                            f"(got '{bleaching_risk_raw}')")
        else:
            feedback.append(f"PEAK_SST={peak_sst_val:.1f}°C is below expected warm pool range (>=28°C)")
    except (ValueError, AttributeError):
        feedback.append(f"Could not parse PEAK_SST numeric value from '{peak_sst_raw}'")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
