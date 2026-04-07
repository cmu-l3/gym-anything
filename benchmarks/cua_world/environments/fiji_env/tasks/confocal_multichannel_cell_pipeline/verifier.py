#!/usr/bin/env python3
"""
Verifier for Multi-Channel Cell Pipeline task.

This is a stub verifier for framework compatibility.
Primary verification will be done via vlm_checklist_verifier.

Points Breakdown (100 total):
- 15 pts: Output files exist and created during task
- 15 pts: CSV has required structure (columns + rows)
- 10 pts: Nuclear count plausible
- 10 pts: Branch/junction data present and positive
- 10 pts: Actin feature data present and plausible
- 15 pts: Figure is multi-panel (file size heuristic)
- 10 pts: Report contains metric keywords with numbers
- 15 pts: Trajectory length (basic anti-gaming)

Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_multichannel_pipeline(traj, env_info, task_info):
    """Verify the multi-channel confocal cell analysis pipeline task."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy capability missing"}

    # Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/multichannel_pipeline_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # --- Criterion 1: File Existence + Timing (15 pts) ---
    files_ok = 0
    for key in ["csv", "figure", "report"]:
        if result.get(f"{key}_exists") and result.get(f"{key}_modified"):
            files_ok += 1

    file_pts = files_ok * 5
    score += file_pts
    feedback.append(f"File existence: {files_ok}/3 files created during task (+{file_pts})")

    # Anti-gaming: if NO files were modified after task start, zero everything
    if files_ok == 0:
        feedback.append("WARNING: No output files created during task")
        return {
            "passed": False,
            "score": 0,
            "feedback": "; ".join(feedback)
        }

    # --- Criterion 2: CSV Structure (15 pts) ---
    if result.get("csv_exists"):
        cols = result.get("csv_cols", [])
        rows = result.get("csv_rows", 0)

        # Check for expected column structure (Channel, Metric_Name, Value)
        has_value_col = any("value" in c for c in cols)
        has_name_col = any("metric" in c or "name" in c for c in cols)

        if has_name_col and has_value_col:
            score += 5
            feedback.append("CSV has metric name + value columns (+5)")
        elif rows > 0:
            score += 2
            feedback.append("CSV exists with data but non-standard columns (+2)")

        if rows >= 6:
            score += 10
            feedback.append(f"CSV has sufficient rows ({rows} >= 6) (+10)")
        elif rows >= 3:
            score += 5
            feedback.append(f"CSV has partial data ({rows} rows) (+5)")
        else:
            feedback.append(f"CSV has too few rows ({rows})")
    else:
        feedback.append("CSV file not found")

    # --- Criterion 3: Nuclear Count Plausible (10 pts) ---
    metrics = result.get("csv_metrics", {})

    nuclear_count = None
    for key in metrics:
        if "nuclear" in key and "count" in key:
            nuclear_count = metrics[key]
            break
        if "cell" in key and "count" in key:
            nuclear_count = metrics[key]
            break

    if nuclear_count is not None and 5 <= nuclear_count <= 500:
        score += 10
        feedback.append(f"Nuclear count plausible ({nuclear_count:.0f}) (+10)")
    elif nuclear_count is not None:
        score += 3
        feedback.append(f"Nuclear count present but out of range ({nuclear_count:.0f}) (+3)")
    else:
        feedback.append("Nuclear count metric not found in CSV")

    # --- Criterion 4: Branch/Junction Data (10 pts) ---
    branch_count = None
    junction_count = None
    for key in metrics:
        if "branch" in key:
            branch_count = metrics[key]
        if "junction" in key:
            junction_count = metrics[key]

    branch_pts = 0
    if branch_count is not None and branch_count > 0:
        branch_pts += 5
        feedback.append(f"Branch count present and positive ({branch_count:.0f}) (+5)")
    if junction_count is not None and junction_count > 0:
        branch_pts += 5
        feedback.append(f"Junction count present and positive ({junction_count:.0f}) (+5)")
    score += branch_pts

    if branch_count is None and junction_count is None:
        feedback.append("No skeleton metrics found in CSV")

    # --- Criterion 5: Actin Feature Data (10 pts) ---
    actin_count = None
    actin_area = None
    for key in metrics:
        if ("actin" in key or "feature" in key) and "count" in key:
            actin_count = metrics[key]
        if ("actin" in key or "feature" in key) and "area" in key:
            actin_area = metrics[key]

    actin_pts = 0
    if actin_count is not None and 10 <= actin_count <= 5000:
        actin_pts += 5
        feedback.append(f"Actin feature count plausible ({actin_count:.0f}) (+5)")
    elif actin_count is not None:
        actin_pts += 2
        feedback.append(f"Actin feature count present but unusual ({actin_count:.0f}) (+2)")

    if actin_area is not None and actin_area > 0:
        actin_pts += 5
        feedback.append(f"Mean actin feature area present ({actin_area:.2f}) (+5)")
    score += actin_pts

    if actin_count is None and actin_area is None:
        feedback.append("No actin feature metrics found in CSV")

    # --- Criterion 6: Figure Multi-Panel (15 pts) ---
    fig_size = result.get("figure_size", 0)
    if result.get("figure_exists"):
        # A 2x3 montage of 512x512 images as PNG should be >100KB
        if fig_size > 100000:
            score += 15
            feedback.append(f"Figure large enough for multi-panel ({fig_size} bytes) (+15)")
        elif fig_size > 20000:
            score += 8
            feedback.append(f"Figure exists but may be single-panel ({fig_size} bytes) (+8)")
        else:
            score += 3
            feedback.append(f"Figure exists but very small ({fig_size} bytes) (+3)")
    else:
        feedback.append("Figure file not found")

    # --- Criterion 7: Report Content (10 pts) ---
    if result.get("report_exists") and result.get("report_has_metrics"):
        score += 10
        feedback.append("Report contains required metric keywords with numbers (+10)")
    elif result.get("report_exists"):
        score += 3
        feedback.append("Report exists but missing key metrics (+3)")
    else:
        feedback.append("Report file not found")

    # --- Criterion 8: Trajectory Length (15 pts) ---
    if len(traj) > 5:
        score += 15
        feedback.append(f"Trajectory recorded ({len(traj)} steps) (+15)")
    elif len(traj) > 2:
        score += 8
        feedback.append(f"Short trajectory ({len(traj)} steps) (+8)")
    else:
        feedback.append("Trajectory too short")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }
