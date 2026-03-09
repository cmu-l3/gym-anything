#!/usr/bin/env python3
"""Verifier for assign_resource_to_task task.

Checks that resource UID 7 (G.C. Survey Crew) is assigned to
task UID 22 (Set line and grade benchmarks) in the saved project file.
"""
import os
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


def verify_assign_resource_to_task(traj, env_info, task_info):
    """Verify G.C. Survey Crew (UID=7) is assigned to task 22 in the saved XML."""
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

    assignments_elem = root.find(f"{{{NS}}}Assignments")
    if assignments_elem is None:
        return {"passed": False, "score": 0, "feedback": "No Assignments element in project file"}

    # Also accept resource named "G.C. Survey Crew" identified via Resources section
    # (in case ProjectLibre renumbered resource UIDs on save)
    resource_uid_for_survey_crew = "7"
    resources_elem = root.find(f"{{{NS}}}Resources")
    if resources_elem is not None:
        for res in resources_elem.findall(f"{{{NS}}}Resource"):
            name = res.findtext(f"{{{NS}}}Name", "")
            if "survey crew" in name.lower():
                resource_uid_for_survey_crew = res.findtext(f"{{{NS}}}UID", "7")
                break

    for assignment in assignments_elem.findall(f"{{{NS}}}Assignment"):
        task_uid = assignment.findtext(f"{{{NS}}}TaskUID", "")
        resource_uid = assignment.findtext(f"{{{NS}}}ResourceUID", "")
        if task_uid == "22" and resource_uid == resource_uid_for_survey_crew:
            return {
                "passed": True,
                "score": 100,
                "feedback": (
                    f"G.C. Survey Crew (resource UID={resource_uid_for_survey_crew}) "
                    "is correctly assigned to task 22 (Set line and grade benchmarks)"
                ),
            }

    # Check how many resources are assigned to task 22
    assigned_resources = [
        a.findtext(f"{{{NS}}}ResourceUID", "?")
        for a in assignments_elem.findall(f"{{{NS}}}Assignment")
        if a.findtext(f"{{{NS}}}TaskUID", "") == "22"
    ]
    return {
        "passed": False,
        "score": 0,
        "feedback": (
            f"G.C. Survey Crew not found assigned to task 22. "
            f"Resources currently assigned to task 22: {assigned_resources or 'none'}"
        ),
    }
