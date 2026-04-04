#!/usr/bin/env python3
"""
Verifier for sheet_title_block task.

A project architect must add a professional permit-submission title block to a real
architectural floor plan drawing. The task requires creating dedicated title block
layers, drawing a structured border/grid, and populating required fields.

Scoring (100 points):
  - GATE: Output file exists and was created after task start (else score=0)
  - Title block border/frame layer present with line entities:   20 pts
  - Title information/project layer present:                     15 pts
  - Project info text (title, address, project name):            15 pts
  - Drawing number or sheet designation text:                    15 pts
  - Scale annotation present:                                    10 pts
  - Seal/approval/permit text designation:                       15 pts
  - Revision section text (rev table entries):                   10 pts

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_sheet_title_block(traj, env_info, task_info):
    """Verify title block creation task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})

    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_json.close()
        copy_from_env("/tmp/sheet_title_block_result.json", tmp_json.name)
        with open(tmp_json.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result JSON not found — export script did not run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result JSON: {e}"}
    finally:
        try:
            os.unlink(tmp_json.name)
        except Exception:
            pass

    score = 0
    feedback_parts = []
    subscores = {}

    # ---- GATE: Output file must exist and be newer than task start ----
    if not result.get("output_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file '/home/ga/Documents/LibreCAD/floorplan_sheet.dxf' not found",
        }

    if not result.get("file_modified_after_start", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file exists but predates task start — not created by agent",
        }

    # ---- Criterion 1: Title block border/frame layer with line entities (20 pts) ----
    has_border_layer = result.get("title_block_border_layer_present", False)
    new_lines = result.get("new_line_count", 0)
    if has_border_layer and new_lines >= 8:
        score += 20
        subscores["border_layer"] = True
        feedback_parts.append(f"Title block border layer found with {new_lines} line entities (+20)")
    elif has_border_layer and new_lines >= 3:
        score += 10
        subscores["border_layer"] = "partial"
        feedback_parts.append(f"Title block border layer present but only {new_lines} lines (10/20)")
    elif new_lines >= 8:
        score += 10
        subscores["border_layer"] = "partial"
        feedback_parts.append(f"{new_lines} new lines found but no dedicated border layer (10/20)")
    else:
        subscores["border_layer"] = False
        feedback_parts.append(f"No title block border layer found, only {new_lines} new lines (0/20)")

    # ---- Criterion 2: Title information/project layer (15 pts) ----
    if result.get("title_info_layer_present", False):
        score += 15
        subscores["info_layer"] = True
        feedback_parts.append("Title information layer present (+15)")
    else:
        subscores["info_layer"] = False
        feedback_parts.append("No title information layer found (0/15)")

    # ---- Criterion 3: Project info text (15 pts) ----
    if result.get("has_project_info_text", False):
        score += 15
        subscores["project_info"] = True
        feedback_parts.append("Project information text found (+15)")
    else:
        subscores["project_info"] = False
        feedback_parts.append("No project information text found (0/15) — expected project title, address, or owner info")

    # ---- Criterion 4: Drawing number or sheet designation (15 pts) ----
    if result.get("has_drawing_number_text", False):
        score += 15
        subscores["drawing_number"] = True
        feedback_parts.append("Drawing number/sheet designation text found (+15)")
    else:
        subscores["drawing_number"] = False
        feedback_parts.append("No drawing number or sheet designation found (0/15)")

    # ---- Criterion 5: Scale annotation (10 pts) ----
    if result.get("has_scale_text", False):
        score += 10
        subscores["scale"] = True
        feedback_parts.append("Scale annotation present (+10)")
    else:
        subscores["scale"] = False
        feedback_parts.append("No scale annotation found (0/10)")

    # ---- Criterion 6: Seal/approval/permit text (15 pts) ----
    if result.get("has_seal_or_approval_text", False):
        score += 15
        subscores["seal_text"] = True
        feedback_parts.append("Seal/approval/permit area text present (+15)")
    else:
        subscores["seal_text"] = False
        feedback_parts.append("No seal or permit text found (0/15)")

    # ---- Criterion 7: Revision section text (10 pts) ----
    if result.get("has_revision_text", False):
        score += 10
        subscores["revision"] = True
        feedback_parts.append("Revision history section text found (+10)")
    else:
        subscores["revision"] = False
        feedback_parts.append("No revision history text found (0/10)")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
