#!/usr/bin/env python3
"""Verifier for create_milestone task.

Checks that a task named 'Foundation Work Complete' was added to the project
with Milestone=1 or Duration=0, positioned after task UID 44.
"""
import os
import re
import tempfile
import xml.etree.ElementTree as ET

NS = "http://schemas.microsoft.com/project"
PROJECT_FILE = "/home/ga/Projects/current_task.xml"
MILESTONE_NAME = "Foundation Work Complete"
ANCHOR_UID = "44"  # Strip column piers and foundation forms


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


def verify_create_milestone(traj, env_info, task_info):
    """Verify 'Foundation Work Complete' milestone was added after task 44."""
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
    milestone_task = None
    milestone_idx = None

    for idx, task in enumerate(all_tasks):
        uid = task.findtext(f"{{{NS}}}UID", "")
        name = task.findtext(f"{{{NS}}}Name", "")
        if uid == ANCHOR_UID:
            anchor_idx = idx
        if MILESTONE_NAME.lower() in name.lower():
            milestone_task = task
            milestone_idx = idx

    if milestone_task is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"No task named '{MILESTONE_NAME}' found in project",
        }

    # Check milestone flag or zero duration
    milestone_flag = milestone_task.findtext(f"{{{NS}}}Milestone", "0")
    duration_str = milestone_task.findtext(f"{{{NS}}}Duration", "")
    hours = _parse_duration_hours(duration_str)
    is_milestone = milestone_flag == "1" or hours == 0.0

    if not is_milestone:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Task '{MILESTONE_NAME}' found but not a milestone "
                f"(Milestone={milestone_flag}, Duration={duration_str}). "
                "Set duration to 0 or check the Milestone flag."
            ),
        }

    # Check position (should be after anchor task UID 44)
    if anchor_idx is not None and milestone_idx is not None and milestone_idx <= anchor_idx:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"'{MILESTONE_NAME}' is a milestone but appears BEFORE task 44 "
                "(Strip column piers). Move it to after row 44."
            ),
        }

    return {
        "passed": True,
        "score": 100,
        "feedback": (
            f"Milestone '{MILESTONE_NAME}' correctly added "
            f"(Milestone={milestone_flag}, Duration={duration_str}) "
            f"after task 44 (Strip column piers and foundation forms)"
        ),
    }
