#!/usr/bin/env python3
"""
Verifier for microservices_dependency_audit task.

Scoring (100 points total):
- File saved (new file, not copy of partial): 10 pts
- 7+ of 9 services present in diagram: 25 pts              (partial: 5+ = 12 pts, 3+ = 4 pts)
- 10+ dependency edges with protocol labels: 20 pts         (partial: 5+ = 8 pts)
- Domain grouping (3 domains visible): 15 pts               (partial: 1+ = 5 pts)
- Errors fixed (correct tech stacks, wrong edges removed): 15 pts
- 2+ pages (architecture + dependency matrix): 10 pts
- SVG exported: 5 pts

Pass threshold: 60 points
Mandatory condition: file must be new (not a copy of partial diagram) AND modified after task start
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

ALL_SERVICES = [
    "api-gateway", "customer-service", "notification-service",
    "payment-service", "fraud-detection-service", "ledger-service",
    "checkout-service", "order-service", "reporting-service"
]
MISSING_IN_PARTIAL = [
    "notification-service", "fraud-detection-service", "ledger-service",
    "checkout-service", "order-service", "reporting-service"
]


def verify_microservices_dependency_audit(traj, env_info, task_info):
    """Verify microservices dependency audit diagram."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    min_services = metadata.get('min_services', 7)
    min_edges = metadata.get('min_edges', 10)

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

    # --- Mandatory check: file must exist and not be a copy ---
    if not result.get('file_exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "microservices_architecture.drawio not found. Save corrected diagram to ~/Desktop/.",
            "subscores": {}
        }

    if result.get('is_copy_of_partial'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output is identical to the partial diagram. The diagram must be corrected and expanded.",
            "subscores": {"is_copy": True}
        }

    # --- Criterion 1: File saved after task start (10 pts) ---
    if result.get('file_modified_after_start'):
        score += 10
        subscores["file_saved"] = True
        feedback.append("Corrected diagram saved")
    else:
        subscores["file_saved"] = False
        feedback.append("WARN: File not modified after task start")

    if result.get('file_size', 0) < 800:
        return {
            "passed": False,
            "score": score,
            "feedback": f"File too small ({result.get('file_size', 0)} bytes)",
            "subscores": subscores
        }

    # --- Criterion 2: Services present (25 pts full, 12 partial, 4 minimal) ---
    services_found = result.get('services_found', 0)
    subscores["services_found"] = services_found

    # Check if missing services were added
    services_list = result.get('services_list', '')
    missing_added = sum(1 for svc in MISSING_IN_PARTIAL
                        if svc.split('-')[0] in services_list.lower())

    if services_found >= min_services:
        score += 25
        feedback.append(f"Services: {services_found}/9 found (comprehensive)")
    elif services_found >= 5:
        score += 12
        feedback.append(f"Services: {services_found}/9 (partial — {9-services_found} missing)")
    elif services_found >= 3:
        score += 4
        feedback.append(f"Services: {services_found}/9 (too few)")
    else:
        feedback.append(f"Services: only {services_found}/9 identified")

    missing_from_partial = [s for s in MISSING_IN_PARTIAL
                             if s.split('-')[0] not in services_list.lower()]
    if missing_from_partial:
        feedback.append(f"Still missing: {', '.join(missing_from_partial[:3])}")

    # --- Criterion 3: Dependency edges with protocol labels (20 pts full, 8 partial) ---
    num_edges = result.get('num_edges', 0)
    protocol_count = result.get('protocol_labels_count', 0)
    subscores["edges_with_protocols"] = num_edges

    if num_edges >= min_edges and protocol_count >= 2:
        score += 20
        feedback.append(f"Edges: {num_edges} connections, {protocol_count} protocol types labeled")
    elif num_edges >= 5:
        score += 8
        protocol_note = f" ({protocol_count} protocols)" if protocol_count > 0 else " (no protocol labels)"
        feedback.append(f"Edges: {num_edges}{protocol_note} (partial)")
    elif num_edges >= 2:
        score += 3
        feedback.append(f"Edges: only {num_edges}")
    else:
        feedback.append("Edges: no dependency connections drawn")

    # --- Criterion 4: Domain grouping (15 pts full, 5 pts partial) ---
    has_grouping = result.get('has_grouping', False)
    domains_found = result.get('domains_found', 0)
    subscores["domain_grouping"] = domains_found

    if has_grouping and domains_found >= 3:
        score += 15
        feedback.append(f"Domain grouping: all 3 domains present with group shapes")
    elif has_grouping or domains_found >= 2:
        score += 5
        feedback.append(f"Domain grouping: partial ({domains_found} domains, need 3)")
    else:
        feedback.append("Domain grouping: missing — use groups/swimlanes for Customer/Payment/Operations domains")

    # --- Criterion 5: Errors fixed (15 pts) ---
    # Partial credit: wrong edges removed (8 pts) + correct tech stacks (7 pts)
    errors_fixed = result.get('errors_fixed', False)
    wrong_removed = result.get('wrong_edges_removed', False)
    tech_ok = result.get('tech_stacks_count', 0) >= 2
    subscores["errors_fixed"] = errors_fixed

    if errors_fixed:
        score += 15
        feedback.append("Errors fixed: wrong connections removed, correct tech stacks shown")
    elif wrong_removed and tech_ok:
        score += 12
        feedback.append("Errors partially fixed: wrong edges removed and stacks corrected")
    elif wrong_removed:
        score += 8
        feedback.append("Wrong edges removed (but tech stacks may still be incorrect)")
    elif tech_ok:
        score += 4
        feedback.append("Tech stacks corrected (but wrong connections may remain)")
    else:
        feedback.append("Errors not fixed: wrong connections (red 'WRONG' edges) still present in output")

    # --- Criterion 6: Multiple pages (10 pts) ---
    num_pages = result.get('num_pages', 0)
    has_matrix = result.get('has_dependency_matrix', False)
    subscores["multi_page"] = num_pages
    if num_pages >= 2:
        matrix_note = " (includes Dependency Matrix)" if has_matrix else " (no Dependency Matrix found)"
        score += 10
        feedback.append(f"Pages: {num_pages}{matrix_note}")
    else:
        feedback.append(f"Pages: {num_pages} (need ≥2: Architecture + Dependency Matrix)")

    # --- Criterion 7: SVG exported (5 pts) ---
    svg_size = result.get('svg_size', 0)
    subscores["svg_exported"] = result.get('svg_exists', False)
    if result.get('svg_exists') and svg_size >= 1000:
        score += 5
        feedback.append(f"SVG exported: {svg_size} bytes")
    elif result.get('svg_exists'):
        score += 2
        feedback.append(f"SVG present but small: {svg_size} bytes")
    else:
        feedback.append("SVG not exported (need ~/Desktop/microservices_architecture.svg)")

    passed = score >= 60
    feedback.append(f"{'PASSED' if passed else 'FAILED'} (score={score}/100)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores
    }
