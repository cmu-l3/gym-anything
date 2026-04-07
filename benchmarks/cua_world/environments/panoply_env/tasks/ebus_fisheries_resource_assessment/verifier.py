#!/usr/bin/env python3
"""
Verifier for ebus_fisheries_resource_assessment task.

Occupation: Fisheries Resource Scientist / Marine Ecosystem Analyst
Industry: International Fisheries Management / FAO
Difficulty: hard

Scoring criteria (100 pts total, pass threshold = 80):
  1. Global SST plot exported (25 pts): global_sst_july.png exists,
     was created after task start, size >= 20KB.
  2. Humboldt SST plot exported (25 pts): humboldt_upwelling_july.png exists,
     was created after task start, size >= 15KB.
  3. Upwelling assessment report complete (25 pts): upwelling_report.txt exists,
     was created after task start, and contains all 7 required fields.
  4. Scientific correctness (25 pts):
     - PRODUCTIVITY_CORRELATION == POSITIVE (Upwelling fuels high productivity)
     - SST_ANOMALY_SIGN == NEGATIVE (Upwelling water is colder)
     - UPWELLING_SST_C < ADJACENT_OCEAN_SST_C (Numeric check)
     - NUM_EBUS_IDENTIFIED >= 2
"""

import json
import os
import tempfile


def verify_ebus_fisheries_resource_assessment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON from the VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/ebus_fisheries_resource_assessment_result.json', tmp.name)
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
    global_exists = result.get('png_global_exists', False)
    global_mtime = int(result.get('png_global_mtime', 0))
    global_size = int(result.get('png_global_size', 0))

    if global_exists and global_mtime >= task_start and global_size >= 20000:
        score += 25
        feedback.append(f"Global SST plot exported ({global_size} bytes)")
    elif global_exists and global_mtime >= task_start and global_size >= 5000:
        score += 12
        feedback.append(f"Global SST plot present but small ({global_size} bytes, expected >=20KB)")
    else:
        feedback.append(f"Global SST plot missing or not created during task "
                        f"(exists={global_exists}, size={global_size}, mtime={global_mtime} vs start={task_start})")

    # ----------------------------------------------------------------
    # Criterion 2: Humboldt zoom plot exported (25 pts)
    # ----------------------------------------------------------------
    humboldt_exists = result.get('png_humboldt_exists', False)
    humboldt_mtime = int(result.get('png_humboldt_mtime', 0))
    humboldt_size = int(result.get('png_humboldt_size', 0))

    if humboldt_exists and humboldt_mtime >= task_start and humboldt_size >= 15000:
        score += 25
        feedback.append(f"Humboldt SST plot exported ({humboldt_size} bytes)")
    elif humboldt_exists and humboldt_mtime >= task_start and humboldt_size >= 5000:
        score += 12
        feedback.append(f"Humboldt SST plot present but small ({humboldt_size} bytes, expected >=15KB)")
    else:
        feedback.append(f"Humboldt SST plot missing or not created during task "
                        f"(exists={humboldt_exists}, size={humboldt_size})")

    # ----------------------------------------------------------------
    # Criterion 3: Upwelling report completeness (25 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    
    fields = [
        result.get('assessment_month', ''),
        result.get('primary_ebus', ''),
        result.get('upwelling_sst_c', ''),
        result.get('adjacent_ocean_sst_c', ''),
        result.get('sst_anomaly_sign', ''),
        result.get('productivity_correlation', ''),
        result.get('num_ebus_identified', '')
    ]
    
    has_all_fields = all(bool(f.strip()) for f in fields)

    if report_exists and report_mtime >= task_start and has_all_fields:
        score += 25
        feedback.append("Upwelling assessment report is complete with all 7 fields.")
    elif report_exists and report_mtime >= task_start:
        score += 10
        feedback.append("Report present but missing one or more required fields.")
    else:
        feedback.append(f"Report missing or not created during task (exists={report_exists})")

    # ----------------------------------------------------------------
    # Criterion 4: Scientific correctness (25 pts)
    # ----------------------------------------------------------------
    sci_correct = True
    sci_feedback = []

    # Parse numerical values safely
    up_sst = 0.0
    adj_sst = 0.0
    num_ebus = 0
    try:
        raw_up = result.get('upwelling_sst_c', '').replace('C', '').replace('°', '').strip()
        up_sst = float(raw_up)
    except ValueError:
        sci_correct = False
        sci_feedback.append("Could not parse UPWELLING_SST_C as a number")

    try:
        raw_adj = result.get('adjacent_ocean_sst_c', '').replace('C', '').replace('°', '').strip()
        adj_sst = float(raw_adj)
    except ValueError:
        sci_correct = False
        sci_feedback.append("Could not parse ADJACENT_OCEAN_SST_C as a number")

    try:
        raw_num = result.get('num_ebus_identified', '').strip()
        num_ebus = int(raw_num)
    except ValueError:
        sci_correct = False
        sci_feedback.append("Could not parse NUM_EBUS_IDENTIFIED as an integer")

    # Domain logic checks
    anomaly_sign = result.get('sst_anomaly_sign', '').strip().upper()
    prod_corr = result.get('productivity_correlation', '').strip().upper()

    if anomaly_sign != 'NEGATIVE':
        sci_correct = False
        sci_feedback.append(f"SST_ANOMALY_SIGN expected 'NEGATIVE', got '{anomaly_sign}'")
        
    if prod_corr != 'POSITIVE':
        sci_correct = False
        sci_feedback.append(f"PRODUCTIVITY_CORRELATION expected 'POSITIVE' (upwelling fuels life), got '{prod_corr}'")

    if up_sst >= adj_sst:
        sci_correct = False
        sci_feedback.append(f"Upwelling SST ({up_sst}) should be colder than Adjacent Ocean ({adj_sst})")
        
    if not (10.0 <= up_sst <= 22.0):
        sci_correct = False
        sci_feedback.append(f"UPWELLING_SST_C ({up_sst}) is outside plausible range [10.0, 22.0] for EBUS")

    if num_ebus < 2:
        sci_correct = False
        sci_feedback.append(f"NUM_EBUS_IDENTIFIED ({num_ebus}) is less than 2")

    if sci_correct and has_all_fields:
        score += 25
        feedback.append("Scientific reasoning is correct: Upwelling is a cold anomaly that drives HIGH productivity.")
    elif not sci_correct and has_all_fields:
        feedback.append("Scientific correctness failed: " + "; ".join(sci_feedback))
    else:
        feedback.append("Scientific correctness skipped due to missing/unparseable fields.")

    # ----------------------------------------------------------------
    # Final Evaluation
    # ----------------------------------------------------------------
    passed = (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "global_plot_exists": global_exists,
            "humboldt_plot_exists": humboldt_exists,
            "report_exists": report_exists,
            "sci_correct": sci_correct
        }
    }