#!/usr/bin/env python3
"""
Verifier for typhoon_basin_cat_model_calibration task.

Occupation: Catastrophe Modeler / Natural Hazard Analyst
Industry: Reinsurance / Insurance-Linked Securities (ILS)
Difficulty: very_hard

Scoring criteria (100 pts total, pass threshold = 80):
  1. SST plot exported (20 pts): wp_sst_august.png exists, >= 15KB, created during task.
  2. SLP plot exported (20 pts): wp_slp_august.png exists, >= 15KB, created during task.
  3. Report populated (20 pts): calibration_report.txt exists with all fields.
  4. SST Scientific Correctness (20 pts): MDR_PEAK_SST_C >= 28.0 and GENESIS_THRESHOLD_MET = YES.
  5. SLP Scientific Correctness (20 pts): TROUGH_MIN_SLP_HPA in [990, 1015] and BASIN_ANNUAL_RISK in [HIGH, EXTREME].
"""

import json
import os
import tempfile


def verify_typhoon_basin_cat_model_calibration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/typhoon_basin_cat_model_calibration_result.json', tmp.name)
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
    # Criterion 1: SST plot exported (20 pts)
    # ----------------------------------------------------------------
    sst_exists = result.get('sst_plot_exists', False)
    sst_mtime = int(result.get('sst_plot_mtime', 0))
    sst_size = int(result.get('sst_plot_size', 0))

    if sst_exists and sst_mtime >= task_start and sst_size >= 15000:
        score += 20
        feedback.append(f"SST plot exported ({sst_size} bytes)")
    elif sst_exists and sst_mtime >= task_start and sst_size >= 5000:
        score += 10
        feedback.append(f"SST plot present but small ({sst_size} bytes, expected >=15KB)")
    else:
        feedback.append(f"SST plot missing or not created during task "
                        f"(exists={sst_exists}, size={sst_size}, mtime={sst_mtime} vs start={task_start})")

    # ----------------------------------------------------------------
    # Criterion 2: SLP plot exported (20 pts)
    # ----------------------------------------------------------------
    slp_exists = result.get('slp_plot_exists', False)
    slp_mtime = int(result.get('slp_plot_mtime', 0))
    slp_size = int(result.get('slp_plot_size', 0))

    if slp_exists and slp_mtime >= task_start and slp_size >= 15000:
        score += 20
        feedback.append(f"SLP plot exported ({slp_size} bytes)")
    elif slp_exists and slp_mtime >= task_start and slp_size >= 5000:
        score += 10
        feedback.append(f"SLP plot present but small ({slp_size} bytes, expected >=15KB)")
    else:
        feedback.append(f"SLP plot missing or not created during task "
                        f"(exists={slp_exists}, size={slp_size})")

    # ----------------------------------------------------------------
    # Criterion 3: Calibration report complete (20 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    
    basin = result.get('calibration_basin', '').strip()
    month = result.get('calibration_month', '').strip()
    sst_raw = result.get('mdr_peak_sst', '').strip()
    genesis_met = result.get('genesis_threshold_met', '').strip()
    trough_present = result.get('monsoon_trough_present', '').strip()
    slp_raw = result.get('trough_min_slp', '').strip()
    risk = result.get('basin_annual_risk', '').strip()
    season = result.get('peak_season', '').strip()
    sources = result.get('data_sources', '').strip()

    all_fields_populated = all([
        basin, month, sst_raw, genesis_met, trough_present, slp_raw, risk, season, sources
    ])

    if report_exists and report_mtime >= task_start and all_fields_populated:
        score += 20
        feedback.append(f"Calibration report fully populated")
    elif report_exists and report_mtime >= task_start:
        score += 10
        feedback.append(f"Calibration report present but missing fields")
    else:
        feedback.append(f"Calibration report missing or not created during task")

    # ----------------------------------------------------------------
    # Criterion 4: SST Scientific Correctness (20 pts)
    # MDR_PEAK_SST_C >= 28.0 (August warm pool easily exceeds 28, often 29-30)
    # GENESIS_THRESHOLD_MET = YES
    # ----------------------------------------------------------------
    sst_val = 0.0
    try:
        # Handle "30 C", "30", etc.
        raw_val = sst_raw.lower().replace('c', '').replace('°', '').replace(',', '').strip()
        sst_val = float(raw_val)
        if sst_val > 200:  # Agent may have reported in Kelvin
            sst_val -= 273.15
    except ValueError:
        pass

    genesis_ok = genesis_met.upper() == 'YES'
    
    if sst_val >= 28.0 and genesis_ok:
        score += 20
        feedback.append(f"SST Correctness verified (SST={sst_val:.1f}°C, Genesis Met=YES)")
    elif sst_val >= 26.5 and genesis_ok:
        score += 15
        feedback.append(f"SST Correctness partially verified (SST={sst_val:.1f}°C, expected >=28.0°C)")
    else:
        feedback.append(f"SST Correctness failed (SST={sst_val:.1f}°C, Genesis Met={genesis_met})")

    # ----------------------------------------------------------------
    # Criterion 5: SLP Scientific Correctness (20 pts)
    # TROUGH_MIN_SLP_HPA in [990, 1015]
    # BASIN_ANNUAL_RISK in [HIGH, EXTREME]
    # ----------------------------------------------------------------
    slp_val = 0.0
    try:
        # Handle "1005 hPa", "100500 Pa", "1005", etc.
        raw_slp = slp_raw.lower().replace('hpa', '').replace('pa', '').replace('mb', '').replace(',', '').strip()
        slp_val = float(raw_slp)
        if slp_val > 90000:  # Agent reported in Pascals directly from NCEP dataset
            slp_val /= 100.0
    except ValueError:
        pass

    risk_upper = risk.upper()
    risk_ok = risk_upper in ['HIGH', 'EXTREME']
    
    slp_ok = 990.0 <= slp_val <= 1015.0
    
    if slp_ok and risk_ok:
        score += 20
        feedback.append(f"SLP/Risk Correctness verified (SLP={slp_val:.1f} hPa, Risk={risk_upper})")
    elif slp_ok or risk_ok:
        score += 10
        feedback.append(f"SLP/Risk partially verified (SLP={slp_val:.1f} hPa, Risk={risk_upper})")
    else:
        feedback.append(f"SLP/Risk Correctness failed (SLP={slp_val:.1f} hPa, Risk={risk_upper})")

    # Final grading
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }