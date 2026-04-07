#!/usr/bin/env python3
"""
Verifier for claims_pipeline_reconciliation@1

Checks 5 categories of data fixes, PL/SQL package, trigger,
materialized view, and report file.

Scoring (100 points total):
  - Overpayments fixed (5 claims):              15 pts  (3 each)
  - Orphaned adjudications removed (4):         12 pts  (3 each)
  - Duplicate payments removed (4):             12 pts  (3 each)
  - Eligibility violations rejected (7):         14 pts  (2 each)
  - Payment mismatches fixed (5):               12 pts  (2.4 each)
  - PL/SQL package exists & valid:              15 pts
  - Trigger exists & blocks duplicates:          8 pts
  - Materialized view exists:                    5 pts
  - Report file exists with content:             7 pts

Pass threshold: 60 points
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_claims_pipeline_reconciliation(traj, env_info, task_info):
    """Verify claims pipeline reconciliation task completion."""

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})

    # --- Retrieve result JSON from VM ---
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found - export script may not have run"
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []
    subscores = {}

    # ------------------------------------------------------------------
    # Criterion 1: Overpayments fixed (15 pts)
    # 0 remaining overpayments among the planted claims = full points
    # ------------------------------------------------------------------
    overpay_remaining = result.get("overpayments_remaining_count", -1)
    planted_overpay = len(metadata.get("overpayment_claim_ids", [397, 398, 399, 401, 402]))
    if overpay_remaining == 0:
        pts = 15
    elif overpay_remaining >= 0:
        fixed = max(0, planted_overpay - overpay_remaining)
        pts = int((fixed / planted_overpay) * 15)
    else:
        pts = 0
    score += pts
    subscores["overpayments"] = pts
    feedback.append(f"Overpayments: {overpay_remaining} remaining (+{pts}pts)")

    # ------------------------------------------------------------------
    # Criterion 2: Orphaned adjudications removed (12 pts)
    # ------------------------------------------------------------------
    orphan_remaining = result.get("orphans_remaining_count", -1)
    planted_orphans = len(metadata.get("orphaned_adjudication_claim_ids", [9901, 9902, 9903, 9904]))
    if orphan_remaining == 0:
        pts = 12
    elif orphan_remaining >= 0:
        fixed = max(0, planted_orphans - orphan_remaining)
        pts = int((fixed / planted_orphans) * 12)
    else:
        pts = 0
    score += pts
    subscores["orphans"] = pts
    feedback.append(f"Orphans: {orphan_remaining} remaining (+{pts}pts)")

    # ------------------------------------------------------------------
    # Criterion 3: Duplicate payments removed (12 pts)
    # ------------------------------------------------------------------
    dup_remaining = result.get("duplicates_remaining_count", -1)
    planted_dups = len(metadata.get("duplicate_payment_claim_ids", [200, 250, 300, 350]))
    if dup_remaining == 0:
        pts = 12
    elif dup_remaining >= 0:
        fixed = max(0, planted_dups - dup_remaining)
        pts = int((fixed / planted_dups) * 12)
    else:
        pts = 0
    score += pts
    subscores["duplicates"] = pts
    feedback.append(f"Duplicates: {dup_remaining} remaining (+{pts}pts)")

    # ------------------------------------------------------------------
    # Criterion 4: Eligibility violations rejected (14 pts)
    # 4 terminated provider claims + 3 lapsed member claims = 7 total
    # ------------------------------------------------------------------
    term_remaining = result.get("eligibility_terminated_remaining", [])
    lapsed_remaining = result.get("eligibility_lapsed_remaining", [])
    total_elig = 7
    elig_fixed = total_elig - len(term_remaining) - len(lapsed_remaining)
    pts = int((max(0, elig_fixed) / total_elig) * 14)
    score += pts
    subscores["eligibility"] = pts
    unfixed = len(term_remaining) + len(lapsed_remaining)
    feedback.append(f"Eligibility: {unfixed} remaining (+{pts}pts)")

    # ------------------------------------------------------------------
    # Criterion 5: Payment mismatches fixed (12 pts)
    # ------------------------------------------------------------------
    mismatch_remaining = result.get("mismatches_remaining_count", -1)
    planted_mismatches = len(metadata.get("payment_mismatch_claim_ids", [150, 175, 225, 275, 325]))
    if mismatch_remaining == 0:
        pts = 12
    elif mismatch_remaining >= 0:
        fixed = max(0, planted_mismatches - mismatch_remaining)
        pts = int((fixed / planted_mismatches) * 12)
    else:
        pts = 0
    score += pts
    subscores["mismatches"] = pts
    feedback.append(f"Mismatches: {mismatch_remaining} remaining (+{pts}pts)")

    # ------------------------------------------------------------------
    # Criterion 6: PL/SQL Package (15 pts)
    # 5 pts for exists, 5 pts for valid, 5 pts for returns 0
    # ------------------------------------------------------------------
    pkg_pts = 0
    if result.get("package_exists"):
        pkg_pts += 5
        feedback.append("Package exists")
    if result.get("package_valid"):
        pkg_pts += 5
        feedback.append("Package valid")
    count_result = result.get("count_discrepancies_result")
    if count_result is not None and count_result == 0:
        pkg_pts += 5
        feedback.append("COUNT_DISCREPANCIES returns 0")
    elif count_result is not None:
        feedback.append(f"COUNT_DISCREPANCIES returns {count_result}")
    score += pkg_pts
    subscores["package"] = pkg_pts

    # ------------------------------------------------------------------
    # Criterion 7: Trigger (8 pts)
    # 5 pts for exists, 3 pts for functional test
    # ------------------------------------------------------------------
    trig_pts = 0
    if result.get("trigger_exists"):
        trig_pts += 5
        feedback.append("Trigger exists")
    if result.get("trigger_blocks_duplicates"):
        trig_pts += 3
        feedback.append("Trigger blocks duplicates")
    score += trig_pts
    subscores["trigger"] = trig_pts

    # ------------------------------------------------------------------
    # Criterion 8: Materialized View (5 pts)
    # ------------------------------------------------------------------
    mv_pts = 0
    if result.get("mview_exists"):
        mv_pts += 5
        feedback.append("MView RECONCILIATION_DASHBOARD exists")
    score += mv_pts
    subscores["mview"] = mv_pts

    # ------------------------------------------------------------------
    # Criterion 9: Report file (7 pts)
    # 4 pts for exists with content, 3 pts for mentioning categories
    # ------------------------------------------------------------------
    rpt_pts = 0
    if result.get("report_exists") and result.get("report_size", 0) > 50:
        rpt_pts += 4
        feedback.append("Report file exists")
        preview = result.get("report_content_preview", "").lower()
        category_keywords = ["overpayment", "orphan", "duplicate", "eligibility", "mismatch"]
        found = sum(1 for kw in category_keywords if kw in preview)
        if found >= 3:
            rpt_pts += 3
            feedback.append(f"Report mentions {found}/5 categories")
    else:
        feedback.append("Report file missing or empty")
    score += rpt_pts
    subscores["report"] = rpt_pts

    # ------------------------------------------------------------------
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": result.get("errors", [])
    }
