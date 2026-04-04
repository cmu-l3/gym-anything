#!/usr/bin/env python3
"""Verifier for fix_resource_assignments task.

Checks that four tasks have been reassigned to the correct trade contractor:
1. Task 48 (Steel erection) → Steel Erection Contractor (UID=21)
2. Task 84 (Tile installation) → Tile Contractor (UID=25)
3. Task 90 (Roofing material) → Roofing Contractor (UID=26)
4. Task 127 (HVAC mechanical room) → HVAC Contractor (UID=17)

Scoring: 25 points per correctly reassigned task. Pass threshold: 60.
"""
import os
import tempfile
import xml.etree.ElementTree as ET

NS = "http://schemas.microsoft.com/project"
PROJECT_FILE = "/home/ga/Projects/current_task.xml"

# Expected correct assignments: task_uid -> correct_resource_uid
CORRECT_ASSIGNMENTS = {
    "48": "21",   # Steel Erection Contractor
    "84": "25",   # Tile Contractor
    "90": "26",   # Roofing Contractor
    "127": "17",  # HVAC Contractor
}

# Wrong assignments (injected by setup): task_uid -> wrong_resource_uid
WRONG_ASSIGNMENTS = {
    "48": "9",    # G.C. Labor Crew
    "84": "32",   # Painting Contractor
    "90": "29",   # Carpet Contractor
    "127": "19",  # Elevator Contractor
}

TASK_NAMES = {
    "48": "Erect steel columns",
    "84": "Install tile in toilet rooms",
    "90": "Install seamless roofing material",
    "127": "Set equipment in mechanical room (HVAC)",
}

RESOURCE_NAMES = {
    "21": "Steel Erection Contractor",
    "25": "Tile Contractor",
    "26": "Roofing Contractor",
    "17": "HVAC Contractor",
}


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


def _build_resource_name_map(root):
    """Build UID -> name map for resources."""
    name_map = {}
    resources_elem = root.find(f"{{{NS}}}Resources")
    if resources_elem is not None:
        for res in resources_elem.findall(f"{{{NS}}}Resource"):
            uid = res.findtext(f"{{{NS}}}UID", "")
            name = res.findtext(f"{{{NS}}}Name", "")
            name_map[uid] = name
    return name_map


def _get_task_resources(root, task_uid):
    """Get list of resource UIDs assigned to a task."""
    assignments_elem = root.find(f"{{{NS}}}Assignments")
    if assignments_elem is None:
        return []
    resources = []
    for assignment in assignments_elem.findall(f"{{{NS}}}Assignment"):
        if assignment.findtext(f"{{{NS}}}TaskUID", "") == task_uid:
            resource_uid = assignment.findtext(f"{{{NS}}}ResourceUID", "")
            resources.append(resource_uid)
    return resources


def verify_fix_resource_assignments(traj, env_info, task_info):
    """Verify all 4 resource assignments have been corrected."""
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

    resource_names = _build_resource_name_map(root)
    score = 0
    feedback_parts = []

    for i, (task_uid, correct_uid) in enumerate(CORRECT_ASSIGNMENTS.items(), 1):
        wrong_uid = WRONG_ASSIGNMENTS[task_uid]
        task_name = TASK_NAMES[task_uid]
        correct_name = RESOURCE_NAMES[correct_uid]

        assigned_resources = _get_task_resources(root, task_uid)

        if correct_uid in assigned_resources and wrong_uid not in assigned_resources:
            score += 25
            feedback_parts.append(
                f"C{i} PASS: {task_name} correctly assigned to {correct_name}"
            )
        elif correct_uid in assigned_resources:
            score += 15
            feedback_parts.append(
                f"C{i} PARTIAL: {task_name} has correct resource but wrong one also present"
            )
        else:
            assigned_names = [resource_names.get(r, f"UID={r}") for r in assigned_resources]
            feedback_parts.append(
                f"C{i} FAIL: {task_name} assigned to {assigned_names}, expected {correct_name}"
            )

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
