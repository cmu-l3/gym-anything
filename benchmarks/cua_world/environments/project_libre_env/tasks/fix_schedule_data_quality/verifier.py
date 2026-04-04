#!/usr/bin/env python3
"""Verifier for fix_schedule_data_quality task.

Checks that five injected data quality errors have been corrected:
1. Task 17 (steel fab): duration restored to >= 400h (was corrupted to 40h)
2. Task 8 (shop drawings): duration restored to <= 160h (was corrupted to 800h)
3. Task 55 (form 2nd floor): predecessors restored (were removed)
4. Task 39 (pour foundations): predecessor 38 lag is >= 0 (was set to -480h)
5. Task 82 (exterior masonry): duration restored to >= 120h (was corrupted to 16h)

Scoring: 20 points per corrected error. Pass threshold: 60.
Uses range-based checks since the agent must determine correct values via domain knowledge.
"""
import os
import re
import tempfile
import xml.etree.ElementTree as ET

NS = "http://schemas.microsoft.com/project"
PROJECT_FILE = "/home/ga/Projects/current_task.xml"


def _parse_duration_hours(duration_str):
    if not duration_str:
        return -1.0
    m = re.match(r"PT(\d+(?:\.\d+)?)H", duration_str)
    if m:
        return float(m.group(1))
    m = re.match(r"P(\d+(?:\.\d+)?)D", duration_str)
    if m:
        return float(m.group(1)) * 8.0
    return -1.0


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


def _get_lag_for_predecessor(task, pred_uid_target):
    """Get the lag value for a specific predecessor link. Returns lag in tenths of minutes."""
    for pl in task.findall(f"{{{NS}}}PredecessorLink"):
        pred_uid = pl.findtext(f"{{{NS}}}PredecessorUID", "")
        if pred_uid == pred_uid_target:
            lag_text = pl.findtext(f"{{{NS}}}LinkLag", "0")
            try:
                return int(lag_text)
            except (ValueError, TypeError):
                return 0
    return None  # predecessor not found


def verify_fix_schedule_data_quality(traj, env_info, task_info):
    """Verify all 5 data quality errors have been corrected."""
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

    task_map = {}
    for task in tasks_elem.findall(f"{{{NS}}}Task"):
        uid = task.findtext(f"{{{NS}}}UID", "")
        task_map[uid] = task

    score = 0
    feedback_parts = []

    # C1: Task 17 (steel fabrication) duration >= 400h (was 40h, originally 480h)
    t17 = task_map.get("17")
    if t17 is not None:
        dur = _parse_duration_hours(t17.findtext(f"{{{NS}}}Duration", ""))
        if dur >= 400:
            score += 20
            feedback_parts.append(f"C1 PASS: Task 17 (steel fab) duration {dur:.0f}h (>= 400h)")
        elif dur > 40:
            score += 10
            feedback_parts.append(f"C1 PARTIAL: Task 17 duration {dur:.0f}h (improved from 40h but < 400h)")
        else:
            feedback_parts.append(f"C1 FAIL: Task 17 duration still {dur:.0f}h (corrupted value, expected >= 400h)")
    else:
        feedback_parts.append("C1 FAIL: Task 17 not found")

    # C2: Task 8 (shop drawings) duration <= 160h (was 800h, originally 80h)
    t8 = task_map.get("8")
    if t8 is not None:
        dur = _parse_duration_hours(t8.findtext(f"{{{NS}}}Duration", ""))
        if dur <= 160:
            score += 20
            feedback_parts.append(f"C2 PASS: Task 8 (shop drawings) duration {dur:.0f}h (<= 160h)")
        elif dur < 800:
            score += 10
            feedback_parts.append(f"C2 PARTIAL: Task 8 duration {dur:.0f}h (improved from 800h but > 160h)")
        else:
            feedback_parts.append(f"C2 FAIL: Task 8 duration still {dur:.0f}h (corrupted value, expected <= 160h)")
    else:
        feedback_parts.append("C2 FAIL: Task 8 not found")

    # C3: Task 55 (form 2nd floor) has at least one predecessor (were all removed)
    t55 = task_map.get("55")
    if t55 is not None:
        preds = _get_predecessors(t55)
        if len(preds) >= 1:
            score += 20
            feedback_parts.append(f"C3 PASS: Task 55 (form 2nd floor) has predecessors {preds}")
        else:
            feedback_parts.append("C3 FAIL: Task 55 still has no predecessors")
    else:
        feedback_parts.append("C3 FAIL: Task 55 not found")

    # C4: Task 39 predecessor 38 has lag >= 0 (was -2880000 tenths of minutes)
    t39 = task_map.get("39")
    if t39 is not None:
        lag = _get_lag_for_predecessor(t39, "38")
        if lag is not None:
            if lag >= 0:
                score += 20
                feedback_parts.append(f"C4 PASS: Task 39 predecessor 38 has non-negative lag ({lag})")
            else:
                feedback_parts.append(f"C4 FAIL: Task 39 predecessor 38 still has negative lag ({lag})")
        else:
            # Predecessor 38 not found — check if the predecessor was removed entirely
            preds = _get_predecessors(t39)
            if "38" not in preds:
                feedback_parts.append(f"C4 FAIL: Task 39 has no predecessor 38 (predecessors: {preds})")
            else:
                score += 20
                feedback_parts.append("C4 PASS: Task 39 predecessor 38 has no explicit lag (defaults to 0)")
    else:
        feedback_parts.append("C4 FAIL: Task 39 not found")

    # C5: Task 82 (exterior masonry) duration >= 120h (was 16h, originally 200h)
    t82 = task_map.get("82")
    if t82 is not None:
        dur = _parse_duration_hours(t82.findtext(f"{{{NS}}}Duration", ""))
        if dur >= 120:
            score += 20
            feedback_parts.append(f"C5 PASS: Task 82 (masonry) duration {dur:.0f}h (>= 120h)")
        elif dur > 16:
            score += 10
            feedback_parts.append(f"C5 PARTIAL: Task 82 duration {dur:.0f}h (improved from 16h but < 120h)")
        else:
            feedback_parts.append(f"C5 FAIL: Task 82 duration still {dur:.0f}h (corrupted value, expected >= 120h)")
    else:
        feedback_parts.append("C5 FAIL: Task 82 not found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
