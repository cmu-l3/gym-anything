#!/usr/bin/env python3
"""
Verifier for project_information_authoring task.

Scoring rubric (100 points total, pass threshold = 65):
  - output_exists_and_valid : 15 pts (must have walls to prove not an empty project)
  - project_name            : 15 pts ("Riverside" in name)
  - project_description     : 10 pts (Non-empty, changed from default "FZK"; partial 5)
  - organization_name       : 15 pts ("Thornton" in org name)
  - person_name             : 10 pts ("Okafor" in family name)
  - site_name               : 10 pts ("Riverside" in site name)
  - building_name           : 10 pts ("Community" or "Hub" in building name)
  - postal_address_town     : 15 pts ("Bristol" in town)
"""

import json
import os
import tempfile

def verify_project_information_authoring(traj, env_info, task_info):
    score = 0
    feedback_lines = []

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available in env_info."}

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        tmp_path = f.name

    try:
        copy_from_env("/tmp/project_info_result.json", tmp_path)
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

    # ── Critical gate: output file must exist and contain geometry ────────
    if not result.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "FAIL: Output IFC file /home/ga/BIMProjects/riverside_hub.ifc "
                "was not created. Score: 0/100."
            ),
        }

    n_walls = result.get("n_walls", 0)
    if n_walls == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "FAIL: Output IFC file contains 0 walls. You must edit the "
                "existing FZK-Haus model's metadata, not create an empty project. Score: 0/100."
            )
        }

    # ── Criterion 1: File created during task ─────────────────────────────
    file_mtime = result.get("file_mtime", 0.0)
    task_start = result.get("task_start", 0.0)
    if task_start > 0 and file_mtime > task_start:
        score += 15
        feedback_lines.append("PASS: Output IFC was saved during this task session. (+15)")
    else:
        feedback_lines.append(
            f"FAIL: Output file not modified during task "
            f"(file_mtime={file_mtime:.1f}, task_start={task_start:.1f}). (+0)"
        )

    # ── Criterion 2: Project Name ─────────────────────────────────────────
    project_name = result.get("project_name", "").lower()
    if "riverside" in project_name:
        score += 15
        feedback_lines.append(f"PASS: Project Name '{project_name}' contains 'Riverside'. (+15)")
    else:
        feedback_lines.append(f"FAIL: Project Name '{project_name}' missing expected 'Riverside'. (+0)")

    # ── Criterion 3: Project Description ──────────────────────────────────
    project_desc = result.get("project_desc", "").lower()
    if project_desc and "fzk" not in project_desc and "community" in project_desc:
        score += 10
        feedback_lines.append("PASS: Project Description updated fully. (+10)")
    elif project_desc and "fzk" not in project_desc:
        score += 5
        feedback_lines.append("PARTIAL: Project Description changed from default but might lack detail. (+5)")
    else:
        feedback_lines.append("FAIL: Project Description is empty or still default FZK text. (+0)")

    # ── Criterion 4: Organization Name ────────────────────────────────────
    org_names = [o.lower() for o in result.get("org_names", [])]
    if any("thornton" in o for o in org_names):
        score += 15
        feedback_lines.append(f"PASS: Organization matching 'Thornton' found in {org_names}. (+15)")
    else:
        feedback_lines.append(f"FAIL: No organization matching 'Thornton' found. Found: {org_names}. (+0)")

    # ── Criterion 5: Person Name ──────────────────────────────────────────
    person_family_names = [p.lower() for p in result.get("person_family_names", [])]
    if any("okafor" in p for p in person_family_names):
        score += 10
        feedback_lines.append(f"PASS: Person FamilyName matching 'Okafor' found in {person_family_names}. (+10)")
    else:
        feedback_lines.append(f"FAIL: No person FamilyName matching 'Okafor' found. Found: {person_family_names}. (+0)")

    # ── Criterion 6: Site Name ────────────────────────────────────────────
    site_names = [s.lower() for s in result.get("site_names", [])]
    if any("riverside" in s for s in site_names):
        score += 10
        feedback_lines.append(f"PASS: Site Name matching 'Riverside' found in {site_names}. (+10)")
    else:
        feedback_lines.append(f"FAIL: No Site Name matching 'Riverside' found. Found: {site_names}. (+0)")

    # ── Criterion 7: Building Name ────────────────────────────────────────
    building_names = [b.lower() for b in result.get("building_names", [])]
    if any("community" in b or "hub" in b for b in building_names):
        score += 10
        feedback_lines.append(f"PASS: Building Name matching 'Community' or 'Hub' found in {building_names}. (+10)")
    else:
        feedback_lines.append(f"FAIL: No Building Name matching 'Community'/'Hub' found. Found: {building_names}. (+0)")

    # ── Criterion 8: Postal Address Town ──────────────────────────────────
    towns = [t.lower() for t in result.get("towns", [])]
    if any("bristol" in t for t in towns):
        score += 15
        feedback_lines.append(f"PASS: Postal Address Town matching 'Bristol' found in {towns}. (+15)")
    else:
        feedback_lines.append(f"FAIL: No Postal Address Town matching 'Bristol' found. Found: {towns}. (+0)")

    passed = score >= 65
    feedback_lines.append(f"\nTotal score: {score}/100. {'PASSED' if passed else 'FAILED'} (threshold: 65).")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }