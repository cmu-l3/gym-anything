#!/usr/bin/env python3
"""Verifier for fix_dependency_chain_errors task.

Checks that four injected dependency errors have been corrected:
1. Task 48: predecessor restored from UID=43 back to UID=44
2. Task 57: predecessor 55 link type restored from SF(3) to FS(1)
3. Task 89: predecessor UID=88 restored
4. Task 111: spurious predecessor UID=109 removed

Scoring: 25 points per corrected error. Pass threshold: 60.
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


def _get_predecessors(task):
    """Return list of (predecessor_uid, link_type) tuples."""
    preds = []
    for pl in task.findall(f"{{{NS}}}PredecessorLink"):
        pred_uid = pl.findtext(f"{{{NS}}}PredecessorUID", "")
        link_type = pl.findtext(f"{{{NS}}}Type", "1")
        preds.append((pred_uid, link_type))
    return preds


def verify_fix_dependency_chain_errors(traj, env_info, task_info):
    """Verify all 4 dependency errors have been corrected."""
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

    # Build task lookup
    task_map = {}
    for task in tasks_elem.findall(f"{{{NS}}}Task"):
        uid = task.findtext(f"{{{NS}}}UID", "")
        task_map[uid] = task

    score = 0
    feedback_parts = []

    # Check 1: Task 48 should have predecessor UID=44 (not 43)
    t48 = task_map.get("48")
    if t48 is not None:
        preds = _get_predecessors(t48)
        pred_uids = [p[0] for p in preds]
        if "44" in pred_uids and "43" not in pred_uids:
            score += 25
            feedback_parts.append("C1 PASS: Task 48 correctly depends on UID=44 (Strip column piers)")
        elif "44" in pred_uids:
            score += 15
            feedback_parts.append("C1 PARTIAL: Task 48 has UID=44 but also retains UID=43")
        else:
            feedback_parts.append(f"C1 FAIL: Task 48 predecessors are {pred_uids}, expected UID=44")
    else:
        feedback_parts.append("C1 FAIL: Task 48 not found")

    # Check 2: Task 57 predecessor 55 should have type=1 (FS), not type=3 (SF)
    t57 = task_map.get("57")
    if t57 is not None:
        preds = _get_predecessors(t57)
        found_55 = False
        for pred_uid, link_type in preds:
            if pred_uid == "55":
                found_55 = True
                if link_type in ("1", ""):
                    score += 25
                    feedback_parts.append("C2 PASS: Task 57 predecessor 55 has FS link type")
                else:
                    feedback_parts.append(f"C2 FAIL: Task 57 predecessor 55 has link type {link_type}, expected FS(1)")
                break
        if not found_55:
            feedback_parts.append("C2 FAIL: Task 57 has no predecessor UID=55")
    else:
        feedback_parts.append("C2 FAIL: Task 57 not found")

    # Check 3: Task 89 should have predecessor UID=88
    t89 = task_map.get("89")
    if t89 is not None:
        preds = _get_predecessors(t89)
        pred_uids = [p[0] for p in preds]
        if "88" in pred_uids:
            score += 25
            feedback_parts.append("C3 PASS: Task 89 has predecessor UID=88 (Install flashing)")
        else:
            feedback_parts.append(f"C3 FAIL: Task 89 predecessors are {pred_uids}, missing UID=88")
    else:
        feedback_parts.append("C3 FAIL: Task 89 not found")

    # Check 4: Task 111 should NOT have predecessor UID=109
    t111 = task_map.get("111")
    if t111 is not None:
        preds = _get_predecessors(t111)
        pred_uids = [p[0] for p in preds]
        if "109" not in pred_uids:
            score += 25
            feedback_parts.append("C4 PASS: Task 111 does not have spurious predecessor UID=109")
        else:
            feedback_parts.append("C4 FAIL: Task 111 still has spurious predecessor UID=109 (Pave parking lot)")
    else:
        feedback_parts.append("C4 FAIL: Task 111 not found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
