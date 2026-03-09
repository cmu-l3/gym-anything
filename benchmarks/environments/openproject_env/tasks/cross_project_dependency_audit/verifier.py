#!/usr/bin/env python3
"""
Verifier for cross_project_dependency_audit task.

Checks 5 independent criteria:
1. Comment added to biometric WP about cross-project dependency (20pts)
2. Biometric WP status changed from In progress (15pts)
3. New dashboard WP created in devops-automation (25pts)
4. Checkout bug priority changed to High (15pts)
5. Wiki page in mobile-banking-app with dependency documentation (25pts)

Total: 100pts. Pass threshold: 65.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_FILE = "/tmp/cross_project_result.json"


def verify_cross_project_dependency_audit(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(RESULT_FILE, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    # --- Anti-gaming: do-nothing gate ---
    biometric = result.get("biometric", {})
    dashboard = result.get("dashboard", {})
    if not biometric.get("found", False) and not dashboard.get("found", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Neither biometric WP modifications nor dashboard WP found. Agent likely did nothing.",
        }

    # --- Criterion 1: Comment on biometric WP (20pts) ---
    if biometric.get("found", False):
        notes = biometric.get("notes", [])
        all_notes = " ".join(str(n).lower() for n in notes)
        has_blocked = "blocked" in all_notes or "block" in all_notes
        has_ecommerce = "ecommerce" in all_notes or "e-commerce" in all_notes
        has_checkout = "checkout" in all_notes or "safari" in all_notes

        if has_blocked and (has_ecommerce or has_checkout):
            score += 20
            feedback.append("Comment about cross-project dependency added to biometric WP.")
        elif has_blocked or has_ecommerce or has_checkout:
            score += 10
            feedback.append("Partial comment found on biometric WP (missing some keywords).")
        elif len(all_notes.strip()) > 10:
            score += 5
            feedback.append("Comment exists on biometric WP but missing dependency keywords.")
        else:
            feedback.append("No relevant comment found on biometric WP.")
    else:
        feedback.append("Biometric WP not found.")

    # --- Criterion 2: Biometric WP status changed (15pts) ---
    if biometric.get("found", False):
        bio_status = (biometric.get("status") or "").lower()
        has_blocked_prefix = biometric.get("has_blocked_prefix", False)
        if bio_status in ("on hold", "rejected", "closed"):
            score += 15
            feedback.append(f"Biometric WP status changed to '{bio_status}'.")
        elif bio_status == "new" and has_blocked_prefix:
            score += 15
            feedback.append("Biometric WP status changed to 'New' with [BLOCKED] prefix.")
        elif bio_status == "new":
            score += 10
            feedback.append("Biometric WP status changed to 'New' (missing [BLOCKED] prefix).")
        elif bio_status != "in progress":
            score += 8
            feedback.append(f"Biometric WP status changed to '{bio_status}' (not the expected target).")
        else:
            feedback.append("Biometric WP status still 'In progress' (should have been changed).")

    # --- Criterion 3: Dashboard WP created in devops-automation (25pts) ---
    if dashboard.get("found", False):
        score += 8
        feedback.append("Dashboard WP 'Cross-project dependency tracking dashboard' created.")

        d_type = (dashboard.get("type_name") or "").lower()
        if d_type == "task":
            score += 4
            feedback.append("Dashboard WP type is 'Task'.")
        else:
            feedback.append(f"Dashboard WP type is '{d_type}', expected 'Task'.")

        d_assignee = (dashboard.get("assignee") or "").lower()
        if "carol" in d_assignee:
            score += 5
            feedback.append("Dashboard WP assigned to carol.williams.")
        else:
            feedback.append(f"Dashboard WP assigned to '{d_assignee}', expected 'carol.williams'.")

        d_version = (dashboard.get("version_name") or "").lower()
        if "sprint 3" in d_version or "monitoring" in d_version:
            score += 4
            feedback.append("Dashboard WP in Sprint 3 - Monitoring.")
        else:
            feedback.append(f"Dashboard WP version is '{d_version}', expected 'Sprint 3 - Monitoring'.")

        d_desc = (dashboard.get("description") or "").lower()
        if "dashboard" in d_desc or "depend" in d_desc or "cross-project" in d_desc:
            score += 4
            feedback.append("Dashboard WP has relevant description.")
        elif len(d_desc) > 10:
            score += 2
            feedback.append("Dashboard WP has description but missing key terms.")
        else:
            feedback.append("Dashboard WP missing description.")
    else:
        initial_count = result.get("initial_wp_count_devops", 0)
        current_count = result.get("current_wp_count_devops", 0)
        if current_count > initial_count:
            score += 3
            feedback.append("New WP created in devops-automation but with wrong subject.")
        else:
            feedback.append("Dashboard WP NOT created in devops-automation.")

    # --- Criterion 4: Checkout bug priority changed to High (15pts) ---
    priority_data = result.get("priority", {})
    if priority_data.get("found", False):
        p_name = (priority_data.get("priority") or "").lower()
        if p_name == "high":
            score += 15
            feedback.append("Checkout bug priority changed to 'High'.")
        elif p_name in ("urgent", "immediate"):
            score += 12
            feedback.append(f"Checkout bug priority changed to '{p_name}' (acceptable but not 'High').")
        elif p_name != "normal":
            score += 5
            feedback.append(f"Checkout bug priority is '{p_name}', expected 'High'.")
        else:
            feedback.append("Checkout bug priority still 'Normal'.")
    else:
        feedback.append("Checkout bug WP not found.")

    # --- Criterion 5: Wiki page with dependency docs (25pts) ---
    wiki = result.get("wiki", {})
    if wiki.get("exists", False):
        score += 7
        feedback.append("Wiki page 'Cross-Project Dependencies' exists.")

        content_length = wiki.get("content_length", 0)
        if content_length < 20:
            feedback.append("Wiki page content too short.")
        else:
            wiki_score = 0
            if wiki.get("has_biometric", False):
                wiki_score += 5
                feedback.append("Wiki mentions biometric login.")
            else:
                feedback.append("Wiki missing biometric reference.")

            if wiki.get("has_checkout", False):
                wiki_score += 5
                feedback.append("Wiki mentions checkout/Safari.")
            else:
                feedback.append("Wiki missing checkout/Safari reference.")

            if wiki.get("has_ecommerce", False):
                wiki_score += 4
                feedback.append("Wiki mentions ecommerce project.")
            else:
                feedback.append("Wiki missing ecommerce project reference.")

            if wiki.get("has_blocking", False):
                wiki_score += 4
                feedback.append("Wiki describes blocking relationship.")
            else:
                feedback.append("Wiki missing blocking/dependency language.")

            score += wiki_score
    else:
        feedback.append("Wiki page 'Cross-Project Dependencies' NOT found.")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
