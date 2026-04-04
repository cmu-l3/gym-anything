#!/usr/bin/env python3
"""Verifier for add_new_task task.

Checks that a task named 'Pre-Inspection Walkthrough' was added with
~2 days duration, positioned before task UID 137 (Complete Final Inspections).
"""
import os
import re
import tempfile
import xml.etree.ElementTree as ET

NS = "http://schemas.microsoft.com/project"
PROJECT_FILE = "/home/ga/Projects/current_task.xml"
NEW_TASK_NAME = "Pre-Inspection Walkthrough"
ANCHOR_UID = "137"       # Complete Final Inspections
TARGET_DAYS = 2
TARGET_HOURS = TARGET_DAYS * 8  # 16h


def _parse_duration_hours(duration_str: str) -> float:
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


def verify_add_new_task(traj, env_info, task_info):
    """Verify 'Pre-Inspection Walkthrough' (2 days) added before task 137."""
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
        return {"passed": False, "score": 0, "feedback": "No Tasks element in project file"}

    all_tasks = tasks_elem.findall(f"{{{NS}}}Task")
    anchor_idx = None
    new_task = None
    new_task_idx = None

    for idx, task in enumerate(all_tasks):
        uid = task.findtext(f"{{{NS}}}UID", "")
        name = task.findtext(f"{{{NS}}}Name", "")
        if uid == ANCHOR_UID:
            anchor_idx = idx
        if NEW_TASK_NAME.lower() in name.lower():
            new_task = task
            new_task_idx = idx

    if new_task is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"No task named '{NEW_TASK_NAME}' found in project",
        }

    # Check duration (~2 days = 16h; allow 8–24h range for calendar variations)
    duration_str = new_task.findtext(f"{{{NS}}}Duration", "")
    hours = _parse_duration_hours(duration_str)
    if hours < 8 or hours > 24:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Task '{NEW_TASK_NAME}' found but duration is {duration_str} ({hours:.0f}h). "
                f"Expected ~{TARGET_HOURS}h (2 days)."
            ),
        }

    # Check position (must be before anchor task UID 137)
    if anchor_idx is not None and new_task_idx is not None and new_task_idx >= anchor_idx:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"'{NEW_TASK_NAME}' was added but appears AFTER 'Complete Final Inspections' (row 137). "
                "It must be inserted before row 137."
            ),
        }

    return {
        "passed": True,
        "score": 100,
        "feedback": (
            f"Task '{NEW_TASK_NAME}' correctly added with duration {duration_str} ({hours:.0f}h ≈ 2 days) "
            f"before 'Complete Final Inspections' (task 137)"
        ),
    }
