#!/usr/bin/env python3
"""
Verifier for Remediate Analytics Audit task.

Task: Fix a partially broken Matomo analytics setup for 'FreshCart Online Grocery'
based on a remediation report covering goals, segments, dashboard, and custom dimensions.

Scoring (105 points, capped at 100):
  - Goal "Add to Cart" pattern fixed (/cart/add):     12 pts
  - Goal "Begin Checkout" type fixed (contains):       12 pts
  - Goals edited in place (same idgoal values):         6 pts
  - Correct goals (1, 4) unchanged:                     5 pts
  - Segment "Returning Customers" definition fixed:    15 pts
  - Segment "Mobile Shoppers" created correctly:       15 pts
  - Mobile Shoppers visible to all users:               5 pts
  - Dashboard: Goals module present:                   10 pts
  - Dashboard: DevicesDetection module present:        10 pts
  - Dashboard: correct widgets preserved:               5 pts
  - Custom dimension "Customer Tier" created:          10 pts

Anti-gaming gate: If zero changes detected from initial state -> score=0.
Pass threshold: >= 70 points.
"""

import json
import logging
import os
import tempfile
from typing import Any, Dict

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _is_found(data: Dict) -> bool:
    return str(data.get("found", "false")).lower() == "true"


def _str(val) -> str:
    return str(val).strip() if val is not None else ""


def _check_dashboard_modules(layout_parsed, expected_modules):
    """Check which modules are present in a parsed dashboard layout."""
    found_modules = set()
    if not layout_parsed or not isinstance(layout_parsed, list):
        return found_modules
    for column in layout_parsed:
        if not isinstance(column, list):
            continue
        for widget in column:
            if not isinstance(widget, dict):
                continue
            params = widget.get("parameters", {})
            if isinstance(params, dict):
                module = params.get("module", "")
                if module:
                    found_modules.add(module)
    return found_modules


def verify_remediate_analytics_audit(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that the analytics audit remediation was completed correctly."""

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result JSON from environment
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        try:
            copy_from_env("/tmp/remediate_analytics_audit_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may not have run",
        }
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid result JSON: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    metadata = task_info.get("metadata", {})
    weights = metadata.get("scoring_weights", {})

    goals = result.get("goals", {})
    segments = result.get("segments", {})
    dashboard = result.get("dashboard", {})
    custom_dims = result.get("custom_dimensions", {})
    initial_goal_ids = result.get("initial_goal_ids", "")
    current_goal_ids = result.get("current_goal_ids", "")

    score = 0
    feedback = []
    subscores: Dict[str, bool] = {}

    # ── ANTI-GAMING GATE ──────────────────────────────────────────────────
    # Check that SOMETHING changed (goals, segments, dashboard, or dimensions)
    any_change = False

    # Check goal changes
    g2 = goals.get("add_to_cart", {})
    g3 = goals.get("begin_checkout", {})
    if _is_found(g2) and _str(g2.get("pattern")) != "/cart":
        any_change = True
    if _is_found(g3) and _str(g3.get("pattern_type")) != "exact":
        any_change = True

    # Check segment changes
    s1 = segments.get("returning_customers", {})
    s2 = segments.get("mobile_shoppers", {})
    if _is_found(s1) and "visitorType" in _str(s1.get("definition")):
        any_change = True
    if _is_found(s2):
        any_change = True

    # Check dimension changes
    dim = custom_dims.get("customer_tier", {})
    if _is_found(dim):
        any_change = True

    if not any_change:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No changes detected from initial state. Anti-gaming gate triggered.",
            "subscores": {},
        }

    # ── GOAL SCORING ──────────────────────────────────────────────────────

    # Goal "Add to Cart" pattern fixed to /cart/add
    g2 = goals.get("add_to_cart", {})
    if _is_found(g2) and _str(g2.get("pattern")) == "/cart/add":
        pts = weights.get("goal_add_to_cart_pattern", 12)
        score += pts
        subscores["goal_add_to_cart_pattern"] = True
        feedback.append(f"Add to Cart pattern fixed to /cart/add [+{pts}]")
    else:
        subscores["goal_add_to_cart_pattern"] = False
        actual = _str(g2.get("pattern")) if _is_found(g2) else "NOT FOUND"
        feedback.append(f"Add to Cart pattern not fixed (got: {actual})")

    # Goal "Begin Checkout" type fixed to contains
    g3 = goals.get("begin_checkout", {})
    if _is_found(g3) and _str(g3.get("pattern_type")) == "contains":
        pts = weights.get("goal_begin_checkout_type", 12)
        score += pts
        subscores["goal_begin_checkout_type"] = True
        feedback.append(f"Begin Checkout type fixed to contains [+{pts}]")
    else:
        subscores["goal_begin_checkout_type"] = False
        actual = _str(g3.get("pattern_type")) if _is_found(g3) else "NOT FOUND"
        feedback.append(f"Begin Checkout type not fixed (got: {actual})")

    # Goals edited in place (same idgoal values, not deleted and recreated)
    initial_ids = set(initial_goal_ids.split(",")) if initial_goal_ids else set()
    current_ids = set(current_goal_ids.split(",")) if current_goal_ids else set()
    if initial_ids and initial_ids.issubset(current_ids):
        pts = weights.get("goals_not_recreated", 6)
        score += pts
        subscores["goals_not_recreated"] = True
        feedback.append(f"Original goal IDs preserved [+{pts}]")
    else:
        subscores["goals_not_recreated"] = False
        feedback.append("Goal IDs changed (may have been deleted and recreated)")

    # Correct goals unchanged
    g1 = goals.get("product_page_view", {})
    g4 = goals.get("purchase_complete", {})
    g1_ok = _is_found(g1) and _str(g1.get("pattern")) == "/products/" and _str(g1.get("pattern_type")) == "contains"
    g4_ok = _is_found(g4) and _str(g4.get("pattern")) == "/order/thank-you" and _str(g4.get("pattern_type")) == "exact"
    if g1_ok and g4_ok:
        pts = weights.get("correct_goals_unchanged", 5)
        score += pts
        subscores["correct_goals_unchanged"] = True
        feedback.append(f"Correct goals preserved [+{pts}]")
    else:
        subscores["correct_goals_unchanged"] = False
        feedback.append("One or both correct goals were modified")

    # ── SEGMENT SCORING ───────────────────────────────────────────────────

    # Segment "Returning Customers" definition fixed
    s1 = segments.get("returning_customers", {})
    if _is_found(s1):
        defn = _str(s1.get("definition"))
        if "visitorType" in defn and "returning" in defn.lower():
            pts = weights.get("segment_returning_fixed", 15)
            score += pts
            subscores["segment_returning_fixed"] = True
            feedback.append(f"Returning Customers segment fixed [+{pts}]")
        else:
            subscores["segment_returning_fixed"] = False
            feedback.append(f"Returning Customers has wrong definition: {defn}")
    else:
        subscores["segment_returning_fixed"] = False
        feedback.append("Returning Customers segment not found")

    # Segment "Mobile Shoppers" created
    s2 = segments.get("mobile_shoppers", {})
    if _is_found(s2):
        defn = _str(s2.get("definition"))
        if "deviceType" in defn and "smartphone" in defn.lower():
            pts = weights.get("segment_mobile_created", 15)
            score += pts
            subscores["segment_mobile_created"] = True
            feedback.append(f"Mobile Shoppers segment created [+{pts}]")
        else:
            subscores["segment_mobile_created"] = False
            feedback.append(f"Mobile Shoppers has wrong definition: {defn}")

        # Visibility check
        enable_all = _str(s2.get("enable_all_users"))
        if enable_all == "1":
            pts = weights.get("segment_mobile_visibility", 5)
            score += pts
            subscores["segment_mobile_visibility"] = True
            feedback.append(f"Mobile Shoppers visible to all users [+{pts}]")
        else:
            subscores["segment_mobile_visibility"] = False
            feedback.append("Mobile Shoppers not visible to all users")
    else:
        subscores["segment_mobile_created"] = False
        subscores["segment_mobile_visibility"] = False
        feedback.append("Mobile Shoppers segment not found")

    # ── DASHBOARD SCORING ─────────────────────────────────────────────────

    layout_parsed = dashboard.get("layout_parsed")
    if layout_parsed is None:
        # Try parsing layout_raw
        try:
            layout_parsed = json.loads(dashboard.get("layout_raw", ""))
        except (json.JSONDecodeError, TypeError):
            layout_parsed = None

    if layout_parsed:
        modules = _check_dashboard_modules(layout_parsed, [])

        # Goals module present (replacing Actions)
        if "Goals" in modules:
            pts = weights.get("dashboard_goals_widget", 10)
            score += pts
            subscores["dashboard_goals_widget"] = True
            feedback.append(f"Dashboard has Goals widget [+{pts}]")
        else:
            subscores["dashboard_goals_widget"] = False
            feedback.append("Dashboard missing Goals widget")

        # DevicesDetection module present (replacing Resolution)
        if "DevicesDetection" in modules:
            pts = weights.get("dashboard_devices_widget", 10)
            score += pts
            subscores["dashboard_devices_widget"] = True
            feedback.append(f"Dashboard has DevicesDetection widget [+{pts}]")
        else:
            subscores["dashboard_devices_widget"] = False
            feedback.append("Dashboard missing DevicesDetection widget")

        # Correct widgets preserved
        if "VisitsSummary" in modules and "Referrers" in modules:
            pts = weights.get("dashboard_correct_preserved", 5)
            score += pts
            subscores["dashboard_correct_preserved"] = True
            feedback.append(f"Dashboard correct widgets preserved [+{pts}]")
        else:
            subscores["dashboard_correct_preserved"] = False
            feedback.append("Dashboard correct widgets (VisitsSummary/Referrers) missing")
    else:
        subscores["dashboard_goals_widget"] = False
        subscores["dashboard_devices_widget"] = False
        subscores["dashboard_correct_preserved"] = False
        feedback.append("Dashboard layout could not be parsed")

    # ── CUSTOM DIMENSION SCORING ──────────────────────────────────────────

    dim = custom_dims.get("customer_tier", {})
    if _is_found(dim):
        scope_ok = _str(dim.get("scope")).lower() == "visit"
        active_ok = _str(dim.get("active")) == "1"
        if scope_ok and active_ok:
            pts = weights.get("custom_dimension_created", 10)
            score += pts
            subscores["custom_dimension_created"] = True
            feedback.append(f"Custom dimension 'Customer Tier' created (visit, active) [+{pts}]")
        elif scope_ok:
            score += 5  # partial: right scope but not active
            subscores["custom_dimension_created"] = False
            feedback.append("Custom dimension 'Customer Tier' found but not active [+5 partial]")
        else:
            score += 3  # minimal: exists but wrong scope
            subscores["custom_dimension_created"] = False
            feedback.append(f"Custom dimension 'Customer Tier' found but wrong scope ({_str(dim.get('scope'))}) [+3 partial]")
    else:
        subscores["custom_dimension_created"] = False
        feedback.append("Custom dimension 'Customer Tier' not found")

    # ── FINAL RESULT ──────────────────────────────────────────────────────
    final_score = min(score, 100)
    passed = final_score >= 70

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "goals": goals,
            "segments": segments,
            "dashboard_modules": list(_check_dashboard_modules(layout_parsed, [])) if layout_parsed else [],
            "custom_dimension": custom_dims.get("customer_tier", {}),
            "initial_goal_ids": initial_goal_ids,
            "current_goal_ids": current_goal_ids,
        },
    }
