#!/usr/bin/env python3
"""Verifier for add_task_dependency task.

Checks that task 28 (Install storm drainage) has a Finish-to-Start
predecessor link from task 27 (Rough grade site) in the saved project file.
"""
import os
import tempfile
import xml.etree.ElementTree as ET

NS = "http://schemas.microsoft.com/project"
PROJECT_FILE = "/home/ga/Projects/current_task.xml"


def _read_project(copy_from_env):
    """Copy project file from VM and return parsed XML root, or None on failure."""
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


def verify_add_task_dependency(traj, env_info, task_info):
    """Verify task 28 has a FS predecessor link from task 27 in the saved XML."""
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
        if task.findtext(f"{{{NS}}}UID", "") != "28":
            continue
        for pl in task.findall(f"{{{NS}}}PredecessorLink"):
            pred_uid = pl.findtext(f"{{{NS}}}PredecessorUID", "")
            link_type = pl.findtext(f"{{{NS}}}Type", "1")  # default Type=1 means FS
            if pred_uid == "27" and link_type in ("1", ""):
                return {
                    "passed": True,
                    "score": 100,
                    "feedback": "Task 28 has a Finish-to-Start predecessor from task 27 (correct)",
                }
        existing = [pl.findtext(f"{{{NS}}}PredecessorUID", "?")
                    for pl in task.findall(f"{{{NS}}}PredecessorLink")]
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Task 28 found but no FS predecessor from task 27. "
                f"Predecessors present: {existing or 'none'}"
            ),
        }

    return {"passed": False, "score": 0, "feedback": "Task UID=28 not found in project file"}
