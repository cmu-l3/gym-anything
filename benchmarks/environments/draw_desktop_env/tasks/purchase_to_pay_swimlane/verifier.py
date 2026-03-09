#!/usr/bin/env python3
"""
Verifier for purchase_to_pay_swimlane task.

Scoring (100 points total):
- File saved after task start: 10 pts
- 18+ shapes (process steps, decisions, data objects): 15 pts   (partial: 10+ = 6 pts)
- 12+ edges (flow connections): 10 pts                          (partial: 6+ = 4 pts)
- Swim lane structure present (≥4 lanes): 20 pts               (partial: 2+ lanes = 8 pts)
- ≥3 decision diamonds/gateways: 15 pts                        (partial: 1+ = 6 pts)
- Document/data-object shapes present: 10 pts
- Multi-page (process + KPI page): 10 pts
- PDF exported: 10 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

LANE_TERMS = ["requester", "procurement", "accounts payable", "ap", "supplier", "finance", "treasury"]


def verify_purchase_to_pay_swimlane(traj, env_info, task_info):
    """Verify P2P swimlane process diagram creation."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    min_shapes = metadata.get('min_shapes', 18)
    min_edges = metadata.get('min_edges', 12)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    subscores = {}

    # --- Criterion 1: File saved (10 pts) ---
    if not result.get('file_exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "p2p_process.drawio not found. No diagram was saved.",
            "subscores": {}
        }

    if result.get('file_modified_after_start'):
        score += 10
        subscores["file_saved"] = True
        feedback.append("Diagram file saved")
    else:
        subscores["file_saved"] = False
        feedback.append("WARN: File exists but not modified after task start")

    if result.get('file_size', 0) < 800:
        return {
            "passed": False,
            "score": score,
            "feedback": f"File too small ({result.get('file_size', 0)} bytes) — minimal diagram",
            "subscores": subscores
        }

    # --- Criterion 2: Shape count (15 pts full, 6 partial) ---
    num_shapes = result.get('num_shapes', 0)
    subscores["num_shapes"] = num_shapes
    if num_shapes >= min_shapes:
        score += 15
        feedback.append(f"Shapes: {num_shapes} (comprehensive process diagram)")
    elif num_shapes >= 10:
        score += 6
        feedback.append(f"Shapes: {num_shapes} (partial, need ≥{min_shapes})")
    elif num_shapes >= 5:
        score += 2
        feedback.append(f"Shapes: {num_shapes} (too few steps)")
    else:
        feedback.append(f"Shapes: only {num_shapes}")

    # --- Criterion 3: Edge count (10 pts full, 4 partial) ---
    num_edges = result.get('num_edges', 0)
    subscores["num_edges"] = num_edges
    if num_edges >= min_edges:
        score += 10
        feedback.append(f"Flow connections: {num_edges}")
    elif num_edges >= 6:
        score += 4
        feedback.append(f"Flow connections: {num_edges} (partial)")
    else:
        feedback.append(f"Flow connections: only {num_edges}")

    # --- Criterion 4: Swim lanes (20 pts full, 8 partial) ---
    has_swimlanes = result.get('has_swimlanes', False)
    num_lanes = result.get('num_lanes', 0)
    lane_names = result.get('lane_names', '')
    subscores["swim_lanes"] = num_lanes

    # Count how many of the 5 required departments are present in lane names
    lanes_found = [ln for ln in LANE_TERMS if ln in lane_names.lower()]
    unique_depts = set()
    if "requester" in lane_names.lower(): unique_depts.add("requester")
    if "procurement" in lane_names.lower(): unique_depts.add("procurement")
    if "accounts payable" in lane_names.lower() or "ap" in lane_names.lower(): unique_depts.add("ap")
    if "supplier" in lane_names.lower(): unique_depts.add("supplier")
    if "finance" in lane_names.lower() or "treasury" in lane_names.lower(): unique_depts.add("finance")

    if has_swimlanes and len(unique_depts) >= 4:
        score += 20
        feedback.append(f"Swim lanes: {len(unique_depts)}/5 departments in lanes (excellent)")
    elif has_swimlanes and len(unique_depts) >= 2:
        score += 8
        feedback.append(f"Swim lanes: {len(unique_depts)}/5 department lanes (partial)")
    elif has_swimlanes or num_lanes >= 2:
        score += 4
        feedback.append(f"Swim lanes: present ({num_lanes} lanes) but missing department labels")
    else:
        feedback.append("Swim lanes: NOT found — create 5 horizontal lanes for each department")

    # --- Criterion 5: Decision diamonds (15 pts full, 6 partial) ---
    has_decision = result.get('has_decision_diamond', False)
    num_decisions = result.get('num_decisions', 0)
    subscores["decisions"] = num_decisions
    if num_decisions >= 3:
        score += 15
        feedback.append(f"Decision gateways: {num_decisions} (≥3 required)")
    elif num_decisions >= 1 or has_decision:
        score += 6
        feedback.append(f"Decision gateways: {num_decisions} (need ≥3 diamonds)")
    else:
        feedback.append("Decision gateways: NONE found (need ≥3 decision diamonds)")

    # --- Criterion 6: Document/data objects (10 pts) ---
    if result.get('has_data_objects') or result.get('process_keywords_count', 0) >= 4:
        score += 10
        subscores["data_objects"] = True
        feedback.append("Document shapes / process keywords present")
    else:
        subscores["data_objects"] = False
        feedback.append("Document shapes: missing (add folded-page shapes for PR, PO, Invoice, GR)")

    # --- Criterion 7: Multiple pages (10 pts) ---
    num_pages = result.get('num_pages', 0)
    has_kpi = result.get('has_kpi_page', False)
    subscores["multi_page"] = num_pages
    if num_pages >= 2:
        score += 10
        kpi_note = " (includes KPI page)" if has_kpi else " (no KPI page detected)"
        feedback.append(f"Pages: {num_pages}{kpi_note}")
    else:
        feedback.append(f"Pages: {num_pages} (need ≥2: process diagram + KPI dashboard)")

    # --- Criterion 8: PDF exported (10 pts) ---
    pdf_size = result.get('pdf_size', 0)
    subscores["pdf_exported"] = result.get('pdf_exists', False)
    if result.get('pdf_exists') and pdf_size >= 1000:
        score += 10
        feedback.append(f"PDF exported: {pdf_size} bytes")
    elif result.get('pdf_exists'):
        score += 4
        feedback.append(f"PDF present but very small: {pdf_size} bytes")
    else:
        feedback.append("PDF not exported (need ~/Desktop/p2p_process.pdf)")

    passed = score >= 60
    feedback.append(f"{'PASSED' if passed else 'FAILED'} (score={score}/100)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores
    }
