#!/usr/bin/env python3
"""
Verifier for building_system_grouping task.

Requirements:
- File must be saved to /home/ga/BIMProjects/fzk_fm_groups.ifc
- >= 3 IfcGroup entities
- >= 3 IfcRelAssignsToGroup relationships
- >= 15 elements assigned to groups across all groups
- Group names should match keywords: envelope/external/fabric, door/access/egress, floor/slab/structural

Scoring (100 pts total, passing = 65):
- File saved during task (15 pts)
- Groups defined (max 25 pts)
- Relationships created (max 20 pts)
- Elements assigned (max 25 pts)
- Keywords matched (max 15 pts)
"""

import json
import os
import tempfile


def verify_building_system_grouping(traj, env_info, task_info):
    score = 0
    feedback_lines = []

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available in env_info."}

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        tmp_path = f.name

    try:
        copy_from_env("/tmp/group_result.json", tmp_path)
        with open(tmp_path, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export script may not have run."}
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Could not read result file: {e}"}
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    # ── Critical gate: output file must exist ─────────────────────────────
    if not result.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "FAIL: Output IFC file /home/ga/BIMProjects/fzk_fm_groups.ifc "
                "was not created. Score: 0/100."
            ),
        }

    # ── Check 1: File is newly created during this task session (15 pts) ──
    file_mtime = result.get("file_mtime", 0.0)
    task_start = result.get("task_start", 0.0)
    if task_start > 0 and file_mtime > task_start:
        score += 15
        feedback_lines.append("PASS: Output IFC was created/saved during this task session. (+15)")
    else:
        feedback_lines.append(
            f"FAIL: Output file not modified during task "
            f"(file_mtime={file_mtime:.1f}, task_start={task_start:.1f}). (+0)"
        )

    # ── Check 2: IfcGroup entities created (max 25 pts) ───────────────────
    n_groups = result.get("n_groups", 0)
    if n_groups >= 3:
        score += 25
        feedback_lines.append(f"PASS: {n_groups} IfcGroup entities found (>= 3 required). (+25)")
    elif n_groups == 2:
        score += 12
        feedback_lines.append(f"PARTIAL: {n_groups}/3 IfcGroup entities found. (+12)")
    elif n_groups == 1:
        score += 5
        feedback_lines.append(f"PARTIAL: {n_groups}/3 IfcGroup entities found. (+5)")
    else:
        feedback_lines.append("FAIL: No IfcGroup entities found. (+0)")

    # ── Check 3: IfcRelAssignsToGroup relationships (max 20 pts) ──────────
    n_rels = result.get("n_relationships", 0)
    if n_rels >= 3:
        score += 20
        feedback_lines.append(f"PASS: {n_rels} IfcRelAssignsToGroup relationships found (>= 3 required). (+20)")
    elif n_rels == 2:
        score += 10
        feedback_lines.append(f"PARTIAL: {n_rels}/3 group assignment relationships found. (+10)")
    elif n_rels == 1:
        score += 4
        feedback_lines.append(f"PARTIAL: {n_rels}/3 group assignment relationships found. (+4)")
    else:
        feedback_lines.append("FAIL: No group assignment relationships found. (+0)")

    # ── Check 4: Elements assigned (max 25 pts) ───────────────────────────
    n_elements = result.get("n_assigned_elements", 0)
    if n_elements >= 15:
        score += 25
        feedback_lines.append(f"PASS: {n_elements} distinct elements assigned to groups (>= 15 required). (+25)")
    elif n_elements >= 10:
        score += 18
        feedback_lines.append(f"PARTIAL: {n_elements}/15 elements assigned to groups. (+18)")
    elif n_elements >= 5:
        score += 10
        feedback_lines.append(f"PARTIAL: {n_elements}/15 elements assigned to groups. (+10)")
    elif n_elements >= 1:
        score += 4
        feedback_lines.append(f"PARTIAL: Only {n_elements} element(s) assigned to groups. (+4)")
    else:
        feedback_lines.append("FAIL: No elements assigned to any group. (+0)")

    # ── Check 5: Group Naming Keywords (max 15 pts) ───────────────────────
    group_names = result.get("group_names", [])
    
    metadata = task_info.get("metadata", {})
    keywords = metadata.get("keywords", {
        "envelope": ["envelope", "external", "fabric", "enclosure", "facade"],
        "access": ["door", "access", "egress", "opening"],
        "floor": ["floor", "slab", "structural", "horizontal"]
    })

    matched_categories = 0
    matched_names = set()

    # Check each category to see if ANY group matches its keywords
    for category, kws in keywords.items():
        category_matched = False
        for name in group_names:
            if any(k.lower() in name.lower() for k in kws):
                category_matched = True
                matched_names.add(name)
                break
        if category_matched:
            matched_categories += 1

    if matched_categories >= 3:
        score += 15
        feedback_lines.append(f"PASS: Group names matched all 3 expected system categories. (+15)")
    elif matched_categories == 2:
        score += 10
        feedback_lines.append(f"PARTIAL: Group names matched 2/3 expected system categories. (+10)")
    elif matched_categories == 1:
        score += 5
        feedback_lines.append(f"PARTIAL: Group names matched 1/3 expected system categories. (+5)")
    else:
        if group_names:
            feedback_lines.append(f"FAIL: Group names ({group_names}) did not match expected categories. (+0)")
        else:
            feedback_lines.append("FAIL: No group names to evaluate. (+0)")

    # ── Final Score Resolution ────────────────────────────────────────────
    passed = score >= 65
    feedback_lines.append(f"\nTotal score: {score}/100. {'PASSED' if passed else 'FAILED'} (threshold: 65).")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines),
    }