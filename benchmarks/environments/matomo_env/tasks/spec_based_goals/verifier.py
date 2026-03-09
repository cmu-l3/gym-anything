#!/usr/bin/env python3
"""
Verifier for Spec-Based Goals task.

Occupation: Online Merchant
Task: Read funnel_spec.txt and implement 4 conversion goals for SportsFit Shop.

Scoring (100 points):
- 'Product Page View' goal (contains /products/):         22 pts
- 'Add to Cart' goal (contains /cart/add):                22 pts
- 'Checkout Started' goal (contains /checkout):           22 pts
- 'Purchase Confirmation' goal (exact /order/thank-you):  22 pts
- All 4 created during task (anti-gaming):                12 pts

Anti-gaming gate: If no new goals were created → score=0.
Pass threshold: >= 70 points AND at least 1 new goal created.
"""

import json
import logging
import os
import tempfile
from typing import Any, Dict, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

EXPECTED_GOALS = {
    "product_page_view": {
        "name": "Product Page View",
        "pattern_type": "contains",
        "pattern": "/products/",
        "match_attribute": "url",
        "points": 22,
    },
    "add_to_cart": {
        "name": "Add to Cart",
        "pattern_type": "contains",
        "pattern": "/cart/add",
        "match_attribute": "url",
        "points": 22,
    },
    "checkout_started": {
        "name": "Checkout Started",
        "pattern_type": "contains",
        "pattern": "/checkout",
        "match_attribute": "url",
        "points": 22,
    },
    "purchase_confirmation": {
        "name": "Purchase Confirmation",
        "pattern_type": "exact",
        "pattern": "/order/thank-you",
        "match_attribute": "url",
        "points": 22,
    },
}

# For "contains" goals: the expected pattern must appear in the actual pattern (or match exactly)
# For "exact" goals: the patterns must match exactly


def _normalize_pattern(p: str) -> str:
    """Strip leading slash and lowercase for comparison."""
    return p.strip().lower().lstrip("/")


def _pattern_type_match(actual: str, expected: str) -> bool:
    """Match pattern types, accepting 'exact' synonyms."""
    a = actual.strip().lower()
    e = expected.strip().lower()
    if e == "exact":
        return a in ("exact", "exact_url", "exact match", "exact_match")
    return a == e


def _pattern_match(actual: str, expected: str, pattern_type: str) -> bool:
    """Check if the actual URL pattern satisfies the spec requirement."""
    a = _normalize_pattern(actual)
    e = _normalize_pattern(expected)
    if pattern_type == "contains":
        # The spec pattern must appear somewhere in what was entered,
        # OR be an exact match (agent might add trailing slash etc.)
        return e in a or a == e or a.startswith(e) or a.endswith(e)
    elif pattern_type == "exact":
        return a == e
    return a == e


def _is_found(goal_data: Dict) -> bool:
    return str(goal_data.get("found", "false")).lower() == "true"


def verify_spec_based_goals(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that 4 conversion goals were created per the spec document."""

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        try:
            copy_from_env("/tmp/spec_based_goals_result.json", tmp.name)
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

    initial_count = int(result.get("initial_goal_count", 0))
    current_count = int(result.get("current_goal_count", 0))
    goals = result.get("goals", {})
    initial_ids = result.get("initial_goal_ids", "")

    logger.info("Goals initial=%d current=%d", initial_count, current_count)

    # ── GATE: at least one new goal must have been created ────────────────
    any_new = current_count > initial_count
    if not any_new:
        for key in EXPECTED_GOALS:
            g = goals.get(key, {})
            if _is_found(g):
                gid = str(g.get("idgoal", "")).strip()
                if gid and (not initial_ids or f",{gid}," not in f",{initial_ids},"):
                    any_new = True
                    break

    if not any_new:
        return {
            "passed": False, "score": 0,
            "feedback": (
                "No new conversion goals were created during this task. "
                "Anti-gaming gate triggered → score=0."
            ),
            "subscores": {},
        }

    score = 0
    feedback = []
    subscores: Dict[str, bool] = {}
    all_correct = True
    new_goal_count = 0

    for key, exp in EXPECTED_GOALS.items():
        g = goals.get(key, {})
        found = _is_found(g)
        pts = exp["points"]

        logger.info("Checking %s: %s", key, g)

        if not found:
            subscores[key] = False
            all_correct = False
            feedback.append(
                f"'{exp['name']}' goal NOT found in database [-{pts}]"
            )
            continue

        # Check if this is a new goal
        gid = str(g.get("idgoal", "")).strip()
        is_new = not initial_ids or f",{gid}," not in f",{initial_ids},"
        if is_new:
            new_goal_count += 1

        actual_ptype = str(g.get("pattern_type", "")).strip()
        actual_pattern = str(g.get("pattern", "")).strip()
        actual_match_attr = str(g.get("match_attribute", "")).strip()

        ptype_ok = _pattern_type_match(actual_ptype, exp["pattern_type"])
        pattern_ok = _pattern_match(actual_pattern, exp["pattern"], exp["pattern_type"])
        # Match attribute: url is expected; Matomo stores this as 'url'
        match_attr_ok = actual_match_attr.lower() in ("url", "destination", "")

        if ptype_ok and pattern_ok:
            score += pts
            subscores[key] = True
            feedback.append(
                f"'{exp['name']}': {exp['pattern_type']} '{exp['pattern']}' ✓ [+{pts}]"
            )
        elif pattern_ok and not ptype_ok:
            # Pattern correct but wrong match type — partial credit
            partial = pts // 2
            score += partial
            subscores[key] = False
            all_correct = False
            feedback.append(
                f"'{exp['name']}': pattern correct but match type wrong "
                f"(got '{actual_ptype}', expected '{exp['pattern_type']}') [+{partial} partial]"
            )
        elif ptype_ok and not pattern_ok:
            # Match type correct but wrong pattern — partial credit
            partial = pts // 2
            score += partial
            subscores[key] = False
            all_correct = False
            feedback.append(
                f"'{exp['name']}': match type correct but pattern wrong "
                f"(got '{actual_pattern}', expected '{exp['pattern']}') [+{partial} partial]"
            )
        else:
            subscores[key] = False
            all_correct = False
            feedback.append(
                f"'{exp['name']}': both pattern type and pattern incorrect "
                f"(got type='{actual_ptype}' pattern='{actual_pattern}') [-{pts}]"
            )

    # ── Anti-gaming bonus (12 pts) ────────────────────────────────────────
    if new_goal_count >= 4:
        score += 12
        subscores["all_created_during_task"] = True
        feedback.append("All 4 goals newly created during task [+12]")
    elif new_goal_count >= 1:
        partial = 12 * new_goal_count // 4
        score += partial
        subscores["all_created_during_task"] = False
        feedback.append(f"{new_goal_count}/4 goals newly created [+{partial} partial]")
    else:
        subscores["all_created_during_task"] = False
        feedback.append("No goals confirmed as new during task [-12]")

    passed = score >= 70 and any_new

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "expected": {k: {kk: vv for kk, vv in v.items() if kk != "points"}
                        for k, v in EXPECTED_GOALS.items()},
            "actual": {k: goals.get(k, {}) for k in EXPECTED_GOALS},
            "initial_count": initial_count,
            "current_count": current_count,
            "new_goal_count": new_goal_count,
        },
    }
