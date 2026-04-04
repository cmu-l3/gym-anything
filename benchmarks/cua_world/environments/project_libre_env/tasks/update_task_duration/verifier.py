#!/usr/bin/env python3
"""Verifier for update_task_duration task.

Checks that task UID 7 (Obtain building permits) has its duration
changed to 6 working days (≥ 48 hours) in the saved project file.
"""
import os
import re
import tempfile
import xml.etree.ElementTree as ET

NS = "http://schemas.microsoft.com/project"
PROJECT_FILE = "/home/ga/Projects/current_task.xml"
ORIGINAL_HOURS = 32  # 4 days × 8h
TARGET_HOURS = 48    # 6 days × 8h


def _parse_duration_hours(duration_str: str) -> float:
    """Parse ISO 8601 duration string (e.g. PT48H0M0S or P6D) to total hours."""
    if not duration_str:
        return 0.0
    # Match PT{H}H{M}M{S}S
    m = re.match(r"PT(\d+(?:\.\d+)?)H(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?", duration_str)
    if m:
        hours = float(m.group(1) or 0)
        minutes = float(m.group(2) or 0)
        return hours + minutes / 60.0
    # Match P{D}D (days only, assume 8h/day)
    m = re.match(r"P(\d+(?:\.\d+)?)D", duration_str)
    if m:
        return float(m.group(1)) * 8.0
    return 0.0


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


def verify_update_task_duration(traj, env_info, task_info):
    """Verify task 7 duration was changed to 6 days (≥48h) in the saved XML."""
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

    for task in tasks_elem.findall(f"{{{NS}}}Task"):
        if task.findtext(f"{{{NS}}}UID", "") != "7":
            continue
        name = task.findtext(f"{{{NS}}}Name", "")
        duration_str = task.findtext(f"{{{NS}}}Duration", "")
        hours = _parse_duration_hours(duration_str)

        if hours >= TARGET_HOURS - 0.5:  # allow small floating-point tolerance
            return {
                "passed": True,
                "score": 100,
                "feedback": (
                    f"Task 7 ({name}) duration correctly updated to {hours:.0f}h "
                    f"(≥{TARGET_HOURS}h = 6 days)"
                ),
            }
        elif hours <= ORIGINAL_HOURS + 0.5:
            return {
                "passed": False,
                "score": 0,
                "feedback": (
                    f"Task 7 ({name}) duration unchanged: {duration_str} ({hours:.0f}h = 4 days). "
                    f"Expected ≥{TARGET_HOURS}h (6 days)."
                ),
            }
        else:
            return {
                "passed": False,
                "score": 0,
                "feedback": (
                    f"Task 7 ({name}) duration partially changed: {duration_str} ({hours:.0f}h). "
                    f"Expected exactly {TARGET_HOURS}h (6 days)."
                ),
            }

    return {"passed": False, "score": 0, "feedback": "Task UID=7 not found in project file"}
