#!/usr/bin/env python3
"""
Verifier for Custom Dimensions Setup task.

Occupation: Market Research Analyst
Task: Create 5 custom dimensions (3 visit-scope, 2 action-scope) for Research Platform site.

Scoring (100 points):
- 'Subscription Tier' (visit-scope, active):     18 pts
- 'User Cohort' (visit-scope, active):            18 pts
- 'Traffic Source Detail' (visit-scope, active):  18 pts
- 'Page Category' (action-scope, active):         18 pts
- 'Form Interaction' (action-scope, active):      18 pts
- All 5 active (bonus):                           10 pts

Anti-gaming gate: If no new dimensions were created → score=0.
Pass threshold: >= 70 points AND at least 1 new dimension created.
"""

import json
import logging
import os
import tempfile
from typing import Any, Dict

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

EXPECTED_DIMENSIONS = {
    "subscription_tier": {"name": "Subscription Tier", "scope": "visit"},
    "user_cohort": {"name": "User Cohort", "scope": "visit"},
    "traffic_source_detail": {"name": "Traffic Source Detail", "scope": "visit"},
    "page_category": {"name": "Page Category", "scope": "action"},
    "form_interaction": {"name": "Form Interaction", "scope": "action"},
}


def _is_found(dim_data: Dict) -> bool:
    return str(dim_data.get("found", "false")).lower() == "true"


def _is_active(dim_data: Dict) -> bool:
    try:
        return int(dim_data.get("active", 0)) == 1
    except (TypeError, ValueError):
        return str(dim_data.get("active", "")).strip() == "1"


def _scope_matches(dim_data: Dict, expected_scope: str) -> bool:
    return str(dim_data.get("scope", "")).lower().strip() == expected_scope.lower()


def verify_custom_dimensions_setup(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that 5 custom dimensions were configured for Research Platform."""

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        try:
            copy_from_env("/tmp/custom_dimensions_setup_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found — export script may not have run",
        }
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid result JSON: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    initial_count = int(result.get("initial_dimension_count", 0))
    current_count = int(result.get("current_dimension_count", 0))
    dims = result.get("dimensions", {})
    initial_ids = result.get("initial_dimension_ids", "")

    logger.info("Dimensions initial=%d current=%d", initial_count, current_count)
    logger.info("Dimension data: %s", dims)

    # ── GATE: at least one new dimension must exist ───────────────────────
    any_new = current_count > initial_count
    # Also check if any found dimension has an ID not in initial_ids
    for key, exp in EXPECTED_DIMENSIONS.items():
        dim = dims.get(key, {})
        if _is_found(dim):
            dim_id = str(dim.get("idcustomdimension", "")).strip()
            if dim_id and (not initial_ids or f",{dim_id}," not in f",{initial_ids},"):
                any_new = True
                break

    if not any_new:
        return {
            "passed": False, "score": 0,
            "feedback": (
                "No new custom dimensions were created during this task. "
                "Anti-gaming gate triggered → score=0."
            ),
            "subscores": {},
        }

    score = 0
    feedback = []
    subscores: Dict[str, bool] = {}
    all_found_and_active = True

    for key, exp in EXPECTED_DIMENSIONS.items():
        dim = dims.get(key, {})
        found = _is_found(dim)
        active = _is_active(dim) if found else False
        scope_ok = _scope_matches(dim, exp["scope"]) if found else False
        dim_name = exp["name"]
        exp_scope = exp["scope"]

        if found and active:
            score += 18
            subscores[key] = True
            scope_note = "" if scope_ok else f" (⚠ scope={dim.get('scope')} expected={exp_scope})"
            feedback.append(
                f"'{dim_name}' ({exp_scope}-scope) found and active{scope_note} [+18]"
            )
        elif found and not active:
            score += 9  # partial: exists but not active
            subscores[key] = False
            all_found_and_active = False
            feedback.append(
                f"'{dim_name}' found but NOT active [+9 partial]"
            )
        else:
            subscores[key] = False
            all_found_and_active = False
            feedback.append(
                f"'{dim_name}' ({exp_scope}-scope) NOT found in database [-18]"
            )

    # Bonus: all 5 found and active
    if all_found_and_active:
        score += 10
        subscores["all_active"] = True
        feedback.append("All 5 custom dimensions found and active [+10 bonus]")
    else:
        subscores["all_active"] = False

    passed = score >= 70 and any_new

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "expected": EXPECTED_DIMENSIONS,
            "found": {k: dims.get(k, {}) for k in EXPECTED_DIMENSIONS},
            "initial_count": initial_count,
            "current_count": current_count,
        },
    }
