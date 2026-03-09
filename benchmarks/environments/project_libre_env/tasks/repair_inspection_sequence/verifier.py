#!/usr/bin/env python3
"""Verifier for repair_inspection_sequence task.

Checks that the corrupted closeout/inspection phase has been repaired:
1. Task 138 (elevator inspection) has predecessors (e.g., 135 and/or 113)
2. Task 139 (architect's inspection) has predecessor 138
3. Task 140 (building agency inspection) has predecessor 139
4. Task 141 (Fire Marshal's inspection) has predecessor 140
5. Task 142 (punch list) has predecessor 141 (not just 135)
6. Substantial completion milestone exists in schedule

Scoring: C1-C4 (20 pts each), C5 (10 pts), C6 (10 pts). Pass threshold: 60.
"""
import os
import re
import tempfile
import xml.etree.ElementTree as ET

NS = "http://schemas.microsoft.com/project"
PROJECT_FILE = "/home/ga/Projects/current_task.xml"


def _read_project(copy_from_env):
    with tempfile.NamedTemporaryFile(suffix=".xml", delete=False) as tmp:
        tmp_path = tmp.name
    try:
        copy_from_env(PROJECT_FILE, tmp_path)
        tree = ET.parse(tmp_path)
        return tree.getroot()
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def _get_predecessors(task):
    preds = []
    for pl in task.findall(f"{{{NS}}}PredecessorLink"):
        pred_uid = pl.findtext(f"{{{NS}}}PredecessorUID", "")
        preds.append(pred_uid)
    return preds


def _parse_duration_hours(duration_str):
    if not duration_str:
        return -1.0
    m = re.match(r"PT(\d+(?:\.\d+)?)H", duration_str)
    if m:
        return float(m.group(1))
    return -1.0


def verify_repair_inspection_sequence(traj, env_info, task_info):
    """Verify the inspection sequence has been properly restored."""
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "env_info missing copy_from_env"}

    try:
        root = _read_project(copy_from_env)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": f"Project file not found: {PROJECT_FILE}"}
    except ET.ParseError as e:
        return {"passed": False, "score": 0, "feedback": f"XML parse error: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read project file: {e}"}

    tasks_elem = root.find(f"{{{NS}}}Tasks")
    if tasks_elem is None:
        return {"passed": False, "score": 0, "feedback": "No Tasks element"}

    # Build task map
    task_map = {}
    all_tasks = tasks_elem.findall(f"{{{NS}}}Task")
    for task in all_tasks:
        uid = task.findtext(f"{{{NS}}}UID", "")
        task_map[uid] = task

    score = 0
    feedback_parts = []

    # C1: Task 138 (elevator inspection) has at least one predecessor
    t138 = task_map.get("138")
    if t138 is not None:
        preds = _get_predecessors(t138)
        if len(preds) > 0:
            score += 20
            feedback_parts.append(f"C1 PASS: Task 138 (elevator inspection) has predecessors {preds}")
        else:
            feedback_parts.append("C1 FAIL: Task 138 has no predecessors")
    else:
        feedback_parts.append("C1 FAIL: Task 138 not found")

    # C2: Task 139 (architect's inspection) has predecessor 138
    t139 = task_map.get("139")
    if t139 is not None:
        preds = _get_predecessors(t139)
        if "138" in preds:
            score += 20
            feedback_parts.append("C2 PASS: Task 139 depends on 138 (elevator inspection first)")
        else:
            feedback_parts.append(f"C2 FAIL: Task 139 predecessors are {preds}, expected 138")
    else:
        feedback_parts.append("C2 FAIL: Task 139 not found")

    # C3: Task 140 (building agency) has predecessor 139
    t140 = task_map.get("140")
    if t140 is not None:
        preds = _get_predecessors(t140)
        if "139" in preds:
            score += 20
            feedback_parts.append("C3 PASS: Task 140 depends on 139 (architect's inspection first)")
        else:
            feedback_parts.append(f"C3 FAIL: Task 140 predecessors are {preds}, expected 139")
    else:
        feedback_parts.append("C3 FAIL: Task 140 not found")

    # C4: Task 141 (Fire Marshal) has predecessor 140
    t141 = task_map.get("141")
    if t141 is not None:
        preds = _get_predecessors(t141)
        if "140" in preds:
            score += 20
            feedback_parts.append("C4 PASS: Task 141 depends on 140 (building agency first)")
        else:
            feedback_parts.append(f"C4 FAIL: Task 141 predecessors are {preds}, expected 140")
    else:
        feedback_parts.append("C4 FAIL: Task 141 not found")

    # C5: Task 142 (punch list) has predecessor 141 (not just 135)
    t142 = task_map.get("142")
    if t142 is not None:
        preds = _get_predecessors(t142)
        if "141" in preds:
            score += 10
            feedback_parts.append("C5 PASS: Task 142 (punch list) depends on 141 (Fire Marshal)")
        elif len(preds) > 0 and "135" in preds:
            feedback_parts.append("C5 FAIL: Task 142 still depends on 135 (cleanup) instead of 141 (Fire Marshal)")
        else:
            feedback_parts.append(f"C5 FAIL: Task 142 predecessors are {preds}")
    else:
        feedback_parts.append("C5 FAIL: Task 142 not found")

    # C6: Substantial completion milestone exists
    found_milestone = False
    for task in all_tasks:
        name = task.findtext(f"{{{NS}}}Name", "").lower()
        if "substantial completion" in name:
            dur = _parse_duration_hours(task.findtext(f"{{{NS}}}Duration", ""))
            milestone_flag = task.findtext(f"{{{NS}}}Milestone", "0")
            if milestone_flag == "1" or dur == 0.0:
                found_milestone = True
                score += 10
                feedback_parts.append("C6 PASS: Substantial completion milestone found")
            else:
                score += 5
                feedback_parts.append("C6 PARTIAL: Substantial completion task found but not a milestone")
            break
    if not found_milestone and score < 10:
        feedback_parts.append("C6 FAIL: No substantial completion milestone found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
