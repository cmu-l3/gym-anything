#!/usr/bin/env python3
"""Verifier for sugar_codebase_metrics task."""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sugar_codebase_metrics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/sugar_codebase_metrics_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Script exists and is executable (10 pts)
    script_exists = result.get("script_exists", False)
    script_executable = result.get("script_executable", False)
    if script_exists and script_executable:
        score += 10
        feedback.append("analyze_activities.sh exists and is executable")
    elif script_exists:
        score += 5
        feedback.append("analyze_activities.sh exists but is NOT executable")
    else:
        feedback.append("analyze_activities.sh not found")

    # Criterion 2: CSV exists and has exact header (15 pts)
    csv_exists = result.get("csv_exists", False)
    csv_content = result.get("csv_content", "").strip()
    
    if not csv_exists:
        feedback.append("sugar_metrics.csv not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    lines = [l.strip() for l in csv_content.split("\n") if l.strip()]
    if not lines:
        feedback.append("sugar_metrics.csv is empty")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    header = lines[0]
    expected_header = "Activity,Python_Files,Total_LOC"
    
    if header == expected_header:
        score += 15
        feedback.append("CSV header matches exactly")
    elif header.replace(" ", "").replace('"', '') == expected_header:
        score += 10
        feedback.append("CSV header matches (with minor formatting differences)")
    else:
        feedback.append(f"CSV header incorrect: {header[:30]}...")

    # Parse CSV data rows
    agent_data = []
    for i, line in enumerate(lines[1:]):
        parts = line.split(',')
        if len(parts) >= 3:
            act = parts[0].strip().replace('"', '')
            try:
                pf = int(parts[1].strip().replace('"', ''))
                loc = int(parts[2].strip().replace('"', ''))
                agent_data.append({'act': act, 'pf': pf, 'loc': loc, 'row': i+2})
            except ValueError:
                pass

    if not agent_data:
        feedback.append("No valid data rows found in CSV")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    ground_truth = result.get("ground_truth", {})

    # Criterion 3: Mystery Activity correct (30 pts)
    mystery_act = "Mystery.activity"
    mystery_gt = ground_truth.get(mystery_act)
    mystery_agent = next((item for item in agent_data if item['act'] == mystery_act), None)
    
    mystery_correct = False
    if mystery_gt and mystery_agent:
        if mystery_agent['pf'] == mystery_gt['py_files'] and mystery_agent['loc'] == mystery_gt['total_loc']:
            score += 30
            mystery_correct = True
            feedback.append(f"Mystery.activity correct ({mystery_gt['py_files']} files, {mystery_gt['total_loc']} lines)")
        else:
            feedback.append(f"Mystery.activity incorrect: got {mystery_agent['pf']}f/{mystery_agent['loc']}l, expected {mystery_gt['py_files']}f/{mystery_gt['total_loc']}l")
    else:
        feedback.append("Mystery.activity missing from CSV (anti-gaming check failed)")

    # Criterion 4: Standard Activities correct (20 pts)
    # Give 4 points per correct standard activity up to 5
    standard_correct = 0
    for item in agent_data:
        act = item['act']
        if act == mystery_act:
            continue
        gt = ground_truth.get(act)
        if gt and item['pf'] == gt['py_files'] and item['loc'] == gt['total_loc']:
            standard_correct += 1

    std_pts = min(20, standard_correct * 4)
    score += std_pts
    if std_pts > 0:
        feedback.append(f"{standard_correct} standard activities correct (+{std_pts} pts)")
    else:
        feedback.append("No standard activities match ground truth perfectly")

    # Criterion 5: Correct sorting (25 pts)
    # Check if agent_data is sorted by loc descending
    locs = [item['loc'] for item in agent_data]
    is_sorted = all(locs[i] >= locs[i+1] for i in range(len(locs)-1))
    
    sorting_correct = False
    if len(agent_data) >= 5 and is_sorted:
        score += 25
        sorting_correct = True
        feedback.append("CSV rows are correctly sorted by Total_LOC descending")
    elif len(agent_data) < 5:
        feedback.append(f"Too few valid rows ({len(agent_data)}) to verify sorting reliably")
    else:
        feedback.append("CSV rows are NOT sorted correctly by Total_LOC descending")

    passed = score >= 75 and mystery_correct and sorting_correct

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "script_ready": script_exists and script_executable,
            "header_correct": header == expected_header,
            "mystery_correct": mystery_correct,
            "sorting_correct": sorting_correct,
            "standard_correct_count": standard_correct
        }
    }