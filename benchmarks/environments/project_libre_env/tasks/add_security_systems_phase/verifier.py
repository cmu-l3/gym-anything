#!/usr/bin/env python3
"""Verifier for add_security_systems_phase task.

Checks that 4 new security-related tasks were added with correct:
1. Names (matching expected task descriptions)
2. Durations (matching specified working days)
3. Predecessor chains (sequential with external dependencies)
4. Resource assignments (Electric Contractor on all 4)

Scoring (100 points):
- C1: Conduit task exists with ~10-day duration (20 pts)
- C2: Cable task exists with ~5-day duration and chained to conduit (20 pts)
- C3: Panel task exists with ~8-day duration and chained to cable (20 pts)
- C4: Test task exists with ~3-day duration (15 pts)
- C5: All 4 tasks assigned to Electric Contractor (25 pts)

Pass threshold: 60.
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


def _find_task_by_keyword(tasks, keyword):
    """Find a task whose name contains the keyword (case-insensitive)."""
    for task in tasks:
        name = task.findtext(f"{{{NS}}}Name", "")
        if keyword.lower() in name.lower():
            return task
    return None


def _get_predecessors(task):
    preds = []
    for pl in task.findall(f"{{{NS}}}PredecessorLink"):
        pred_uid = pl.findtext(f"{{{NS}}}PredecessorUID", "")
        preds.append(pred_uid)
    return preds


def _get_task_resources(root, task_uid):
    assignments = root.find(f"{{{NS}}}Assignments")
    if assignments is None:
        return []
    result = []
    for a in assignments.findall(f"{{{NS}}}Assignment"):
        if a.findtext(f"{{{NS}}}TaskUID", "") == task_uid:
            result.append(a.findtext(f"{{{NS}}}ResourceUID", ""))
    return result


def _find_electric_contractor_uid(root):
    """Find the UID of the Electric Contractor resource."""
    resources = root.find(f"{{{NS}}}Resources")
    if resources is None:
        return "15"
    for res in resources.findall(f"{{{NS}}}Resource"):
        name = res.findtext(f"{{{NS}}}Name", "")
        if "electric contractor" in name.lower() and "management" not in name.lower():
            return res.findtext(f"{{{NS}}}UID", "15")
    return "15"


def verify_add_security_systems_phase(traj, env_info, task_info):
    """Verify 4 security tasks were added with correct properties."""
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

    all_tasks = tasks_elem.findall(f"{{{NS}}}Task")
    electric_uid = _find_electric_contractor_uid(root)

    score = 0
    feedback_parts = []
    found_uids = []

    # C1: Conduit task (~10 days = 80h, accept 64-96h range)
    conduit = _find_task_by_keyword(all_tasks, "security conduit") or \
              _find_task_by_keyword(all_tasks, "conduit and backbox")
    if conduit is not None:
        dur = _parse_duration_hours(conduit.findtext(f"{{{NS}}}Duration", ""))
        if 64 <= dur <= 96:
            score += 20
            feedback_parts.append(f"C1 PASS: Conduit task found ({dur:.0f}h)")
        else:
            score += 10
            feedback_parts.append(f"C1 PARTIAL: Conduit task found but duration {dur:.0f}h (expected ~80h)")
        found_uids.append(conduit.findtext(f"{{{NS}}}UID", ""))
    else:
        feedback_parts.append("C1 FAIL: No conduit task found")

    # C2: Cable task (~5 days = 40h, accept 32-48h, chained to conduit)
    cable = _find_task_by_keyword(all_tasks, "security") and \
            (_find_task_by_keyword(all_tasks, "cable") or
             _find_task_by_keyword(all_tasks, "low-voltage"))
    # More robust search
    cable = None
    for t in all_tasks:
        name = t.findtext(f"{{{NS}}}Name", "").lower()
        if ("cable" in name or "low-voltage" in name) and "security" in name:
            cable = t
            break
    if cable is None:
        cable = _find_task_by_keyword(all_tasks, "pull security")

    if cable is not None:
        dur = _parse_duration_hours(cable.findtext(f"{{{NS}}}Duration", ""))
        preds = _get_predecessors(cable)
        has_chain = len(found_uids) > 0 and found_uids[0] in preds
        if 32 <= dur <= 48 and has_chain:
            score += 20
            feedback_parts.append(f"C2 PASS: Cable task found ({dur:.0f}h, chained)")
        elif 32 <= dur <= 48:
            score += 12
            feedback_parts.append(f"C2 PARTIAL: Cable task found ({dur:.0f}h) but not chained to conduit")
        else:
            score += 8
            feedback_parts.append(f"C2 PARTIAL: Cable task found but duration {dur:.0f}h")
        found_uids.append(cable.findtext(f"{{{NS}}}UID", ""))
    else:
        feedback_parts.append("C2 FAIL: No cable/low-voltage task found")

    # C3: Panel task (~8 days = 64h, accept 48-80h, chained to cable)
    panel = None
    for t in all_tasks:
        name = t.findtext(f"{{{NS}}}Name", "").lower()
        if ("panel" in name or "camera" in name) and "security" in name:
            panel = t
            break
    if panel is None:
        panel = _find_task_by_keyword(all_tasks, "install security panel")

    if panel is not None:
        dur = _parse_duration_hours(panel.findtext(f"{{{NS}}}Duration", ""))
        preds = _get_predecessors(panel)
        has_chain = len(found_uids) > 1 and found_uids[1] in preds
        if 48 <= dur <= 80 and has_chain:
            score += 20
            feedback_parts.append(f"C3 PASS: Panel task found ({dur:.0f}h, chained)")
        elif 48 <= dur <= 80:
            score += 12
            feedback_parts.append(f"C3 PARTIAL: Panel task found ({dur:.0f}h) but not chained to cable")
        else:
            score += 8
            feedback_parts.append(f"C3 PARTIAL: Panel task found but duration {dur:.0f}h")
        found_uids.append(panel.findtext(f"{{{NS}}}UID", ""))
    else:
        feedback_parts.append("C3 FAIL: No panel/camera task found")

    # C4: Test task (~3 days = 24h, accept 16-32h)
    test = _find_task_by_keyword(all_tasks, "test and commission") or \
           _find_task_by_keyword(all_tasks, "commission security")
    if test is not None:
        dur = _parse_duration_hours(test.findtext(f"{{{NS}}}Duration", ""))
        if 16 <= dur <= 32:
            score += 15
            feedback_parts.append(f"C4 PASS: Test task found ({dur:.0f}h)")
        else:
            score += 8
            feedback_parts.append(f"C4 PARTIAL: Test task found but duration {dur:.0f}h")
        found_uids.append(test.findtext(f"{{{NS}}}UID", ""))
    else:
        feedback_parts.append("C4 FAIL: No test/commission task found")

    # C5: All found tasks assigned to Electric Contractor
    tasks_with_correct_resource = 0
    for uid in found_uids:
        resources = _get_task_resources(root, uid)
        if electric_uid in resources:
            tasks_with_correct_resource += 1

    if len(found_uids) > 0:
        ratio = tasks_with_correct_resource / len(found_uids)
        c5_score = int(25 * ratio)
        score += c5_score
        if ratio == 1.0:
            feedback_parts.append(f"C5 PASS: All {len(found_uids)} tasks assigned to Electric Contractor")
        else:
            feedback_parts.append(
                f"C5 PARTIAL: {tasks_with_correct_resource}/{len(found_uids)} tasks assigned to Electric Contractor"
            )
    else:
        feedback_parts.append("C5 FAIL: No security tasks found to check assignments")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
