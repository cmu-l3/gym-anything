#!/usr/bin/env python3
"""Verifier for schedule_recovery_rebaseline task.

Checks that the agent performed a complete schedule recovery workflow:
1. Status date set to Feb 15, 2000
2. Task 42 marked 100% complete
3. Task 44 duration reduced to 3 days
4. Task 48 has Start No Earlier Than constraint (March 1, 2000)
5. New milestone "Foundation Remediation Inspection" inserted
6. Milestone has Finish-to-Start predecessor from task 46
7. Resource "G.C. Project Management" assigned to milestone
8. Baseline data exists on tasks

Scoring (100 points):
- C1: Output file exists and created during task (10 pts)
- C2: Status date is Feb 15, 2000 (10 pts)
- C3: Task 42 at 100% complete (10 pts)
- C4: Task 44 duration ~3 days / ~24h (15 pts)
- C5: Task 48 SNET constraint with March 1, 2000 (15 pts)
- C6: Milestone exists with 0 duration (15 pts)
- C7: Milestone has predecessor from task 46 (10 pts)
- C8: G.C. Project Management assigned to milestone (5 pts)
- C9: Baseline data present on tasks (10 pts)

Pass threshold: 60.
"""
import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET

NS = "http://schemas.microsoft.com/project"


def _parse_duration_hours(duration_str):
    """Parse MSPDI duration string to hours."""
    if not duration_str:
        return -1.0
    m = re.match(r"PT(\d+(?:\.\d+)?)H", duration_str)
    if m:
        return float(m.group(1))
    m = re.match(r"P(\d+(?:\.\d+)?)D", duration_str)
    if m:
        return float(m.group(1)) * 8.0
    # Handle PT0H0M0S (zero duration for milestones)
    m = re.match(r"PT(\d+)H(\d+)M(\d+)S", duration_str)
    if m:
        return float(m.group(1)) + float(m.group(2)) / 60.0 + float(m.group(3)) / 3600.0
    return -1.0


def _find_task_by_uid(tasks, uid_str):
    """Find a task element by UID."""
    for task in tasks:
        if task.findtext(f"{{{NS}}}UID", "") == str(uid_str):
            return task
    return None


def _find_task_by_keyword(tasks, keyword):
    """Find a task whose name contains the keyword (case-insensitive)."""
    for task in tasks:
        name = task.findtext(f"{{{NS}}}Name", "")
        if keyword.lower() in name.lower():
            return task
    return None


def _get_predecessors(task):
    """Get list of predecessor UIDs for a task."""
    preds = []
    for pl in task.findall(f"{{{NS}}}PredecessorLink"):
        pred_uid = pl.findtext(f"{{{NS}}}PredecessorUID", "")
        if pred_uid:
            preds.append(pred_uid)
    return preds


def _get_task_resources(root, task_uid):
    """Get resource UIDs assigned to a task."""
    assignments = root.find(f"{{{NS}}}Assignments")
    if assignments is None:
        return []
    result = []
    for a in assignments.findall(f"{{{NS}}}Assignment"):
        if a.findtext(f"{{{NS}}}TaskUID", "") == str(task_uid):
            res_uid = a.findtext(f"{{{NS}}}ResourceUID", "")
            if res_uid:
                result.append(res_uid)
    return result


def verify_schedule_recovery_rebaseline(traj, env_info, task_info):
    """Verify the complete schedule recovery workflow."""
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "env_info missing copy_from_env"}

    metadata = task_info.get("metadata", {})

    # Retrieve result JSON
    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, "r") as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        try:
            os.unlink(tmp_json.name)
        except OSError:
            pass

    score = 0
    feedback_parts = []

    # C1: Output file exists and created during task (10 pts)
    file_exists = result_data.get("output_exists", False)
    file_during_task = result_data.get("file_created_during_task", False)
    working_modified = result_data.get("working_file_modified", False)

    if file_exists and file_during_task:
        score += 10
        feedback_parts.append("C1 PASS: Output file created during task")
    elif working_modified:
        score += 5
        feedback_parts.append("C1 PARTIAL: Working file modified but not saved to output path")
    else:
        feedback_parts.append("C1 FAIL: No output file found")

    # Try to parse the XML
    try:
        tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix=".xml")
        copy_from_env("/tmp/result_project.xml", tmp_xml.name)
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
    except FileNotFoundError:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | Could not find result XML",
        }
    except ET.ParseError as e:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + f" | XML parse error: {e}",
        }
    except Exception as e:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + f" | Error reading XML: {e}",
        }
    finally:
        try:
            os.unlink(tmp_xml.name)
        except OSError:
            pass

    tasks_elem = root.find(f"{{{NS}}}Tasks")
    if tasks_elem is None:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | No Tasks element in XML",
        }

    all_tasks = tasks_elem.findall(f"{{{NS}}}Task")

    # C2: Status date is Feb 15, 2000 (10 pts)
    expected_status = metadata.get("expected_status_date", "2000-02-15")
    status_elem = root.find(f"{{{NS}}}StatusDate")
    if status_elem is not None and status_elem.text:
        if expected_status in status_elem.text:
            score += 10
            feedback_parts.append(f"C2 PASS: Status date set to {expected_status}")
        else:
            feedback_parts.append(f"C2 FAIL: Status date is {status_elem.text}, expected {expected_status}")
    else:
        feedback_parts.append("C2 FAIL: Status date not set")

    # C3: Task 42 at 100% complete (10 pts)
    task_42 = _find_task_by_uid(all_tasks, 42)
    if task_42 is not None:
        pct = task_42.findtext(f"{{{NS}}}PercentComplete", "0")
        try:
            pct_val = int(pct)
        except ValueError:
            pct_val = 0
        if pct_val == 100:
            score += 10
            feedback_parts.append("C3 PASS: Task 42 at 100% complete")
        elif pct_val > 0:
            score += 5
            feedback_parts.append(f"C3 PARTIAL: Task 42 at {pct_val}%, expected 100%")
        else:
            feedback_parts.append("C3 FAIL: Task 42 not marked complete")
    else:
        feedback_parts.append("C3 FAIL: Task 42 not found")

    # C4: Task 44 duration ~3 days / ~24h (15 pts)
    # Accept 20-28h range (2.5 to 3.5 days)
    task_44 = _find_task_by_uid(all_tasks, 44)
    if task_44 is not None:
        dur_str = task_44.findtext(f"{{{NS}}}Duration", "")
        dur_h = _parse_duration_hours(dur_str)
        if 20 <= dur_h <= 28:
            score += 15
            feedback_parts.append(f"C4 PASS: Task 44 duration {dur_h:.0f}h (~3 days)")
        elif 0 < dur_h <= 40:
            score += 8
            feedback_parts.append(f"C4 PARTIAL: Task 44 duration {dur_h:.0f}h (expected ~24h)")
        else:
            feedback_parts.append(f"C4 FAIL: Task 44 duration {dur_h:.0f}h, expected ~24h (3 days)")
    else:
        feedback_parts.append("C4 FAIL: Task 44 not found")

    # C5: Task 48 has SNET constraint with March 1, 2000 (15 pts)
    # MSPDI ConstraintType: 4 = Start No Earlier Than
    task_48 = _find_task_by_uid(all_tasks, 48)
    if task_48 is not None:
        constraint_type = task_48.findtext(f"{{{NS}}}ConstraintType", "0")
        constraint_date = task_48.findtext(f"{{{NS}}}ConstraintDate", "")
        expected_cdate = metadata.get("constraint_task", {}).get("constraint_date", "2000-03-01")

        has_snet = constraint_type == "4"
        has_date = expected_cdate in constraint_date if constraint_date else False

        if has_snet and has_date:
            score += 15
            feedback_parts.append("C5 PASS: Task 48 SNET constraint March 1, 2000")
        elif has_snet:
            score += 8
            feedback_parts.append(f"C5 PARTIAL: Task 48 has SNET but date is {constraint_date}")
        elif has_date:
            score += 5
            feedback_parts.append(f"C5 PARTIAL: Task 48 has date but constraint type is {constraint_type}")
        else:
            feedback_parts.append(
                f"C5 FAIL: Task 48 constraint_type={constraint_type}, date={constraint_date}"
            )
    else:
        feedback_parts.append("C5 FAIL: Task 48 not found")

    # C6: Milestone "Foundation Remediation Inspection" exists with 0 duration (15 pts)
    milestone = _find_task_by_keyword(all_tasks, "foundation remediation") or \
                _find_task_by_keyword(all_tasks, "remediation inspection")
    milestone_uid = None
    if milestone is not None:
        milestone_uid = milestone.findtext(f"{{{NS}}}UID", "")
        dur_h = _parse_duration_hours(milestone.findtext(f"{{{NS}}}Duration", ""))
        is_milestone_flag = milestone.findtext(f"{{{NS}}}Milestone", "0")
        if dur_h == 0 or is_milestone_flag == "1":
            score += 15
            feedback_parts.append("C6 PASS: Milestone found with 0 duration")
        else:
            score += 8
            feedback_parts.append(f"C6 PARTIAL: Task found but duration={dur_h:.0f}h (expected 0)")
    else:
        feedback_parts.append("C6 FAIL: Milestone 'Foundation Remediation Inspection' not found")

    # C7: Milestone has predecessor from task 46 (10 pts)
    if milestone is not None:
        preds = _get_predecessors(milestone)
        if "46" in preds:
            score += 10
            feedback_parts.append("C7 PASS: Milestone has predecessor from task 46")
        elif len(preds) > 0:
            score += 5
            feedback_parts.append(f"C7 PARTIAL: Milestone has predecessors {preds} but not 46")
        else:
            feedback_parts.append("C7 FAIL: Milestone has no predecessors")
    else:
        feedback_parts.append("C7 FAIL: No milestone to check predecessors")

    # C8: G.C. Project Management (UID 2) assigned to milestone (5 pts)
    if milestone is not None and milestone_uid:
        resources = _get_task_resources(root, milestone_uid)
        expected_res = str(metadata.get("resource_assignment", {}).get("resource_uid", 2))
        if expected_res in resources:
            score += 5
            feedback_parts.append("C8 PASS: G.C. Project Management assigned to milestone")
        elif len(resources) > 0:
            score += 2
            feedback_parts.append(f"C8 PARTIAL: Milestone has resources {resources} but not UID {expected_res}")
        else:
            feedback_parts.append("C8 FAIL: No resource assigned to milestone")
    else:
        feedback_parts.append("C8 FAIL: No milestone to check resource assignment")

    # C9: Baseline data present on tasks (10 pts)
    baseline_count = 0
    for t in all_tasks:
        baselines = t.findall(f"{{{NS}}}Baseline")
        if baselines:
            baseline_count += 1
    if baseline_count > 5:
        score += 10
        feedback_parts.append(f"C9 PASS: Baseline set on {baseline_count} tasks")
    elif baseline_count > 0:
        score += 5
        feedback_parts.append(f"C9 PARTIAL: Baseline on only {baseline_count} tasks")
    else:
        feedback_parts.append("C9 FAIL: No baseline data found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
