#!/usr/bin/env python3
"""
Verifier for crm_opportunity_management task.

Scoring (100 points total):
- Stale opportunity marked as lost/inactive: 25 points
- Active opportunity advanced to Proposition stage: 20 points
- Active opportunity revenue set to 65000: 15 points
- Activity scheduled on active opportunity: 20 points
- Internal note added to active opportunity: 20 points

Pass threshold: 65 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_crm_opportunity_management(traj, env_info, task_info):
    """Verify CRM pipeline cleanup actions for Horizon Technologies Ltd."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        try:
            copy_from_env('/tmp/crm_opportunity_management_result.json', temp_file.name)
        except FileNotFoundError:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found — export script may not have run",
            }
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Error copying result: {e}"}

        try:
            with open(temp_file.name) as f:
                result = json.load(f)
        except json.JSONDecodeError as e:
            return {"passed": False, "score": 0, "feedback": f"Result file is not valid JSON: {e}"}
    finally:
        os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result.get('error')}"}

    metadata = task_info.get('metadata', {})
    company_name = metadata.get('company_name', result.get('company_name', 'Horizon Technologies Ltd'))
    target_revenue = float(metadata.get('target_expected_revenue', 65000))

    score = 0
    feedback_parts = []
    subscores = {}

    # ─── Criterion 1: Stale opportunity marked as lost/archived (25 pts) ─────
    stale_inactive = result.get('stale_is_inactive', False)
    stale_has_reason = result.get('stale_has_lost_reason', False)
    stale_marked = result.get('stale_marked_lost', False)

    if stale_inactive and stale_has_reason:
        score += 25
        subscores['stale_archived'] = True
        feedback_parts.append("Stale opportunity archived with lost reason (25/25)")
    elif stale_inactive:
        score += 18
        subscores['stale_archived'] = 'no_reason'
        feedback_parts.append("Stale opportunity archived but no lost reason specified (18/25)")
    elif stale_marked:
        score += 10
        subscores['stale_archived'] = 'partial'
        feedback_parts.append("Stale opportunity partially marked (no lost reason, still active) (10/25)")
    else:
        subscores['stale_archived'] = False
        feedback_parts.append(
            "Stale opportunity NOT archived/lost — should be marked Lost with reason (0/25)"
        )

    # ─── Criterion 2: Active opportunity stage advanced to Proposition (20 pts) ─
    stage_advanced = result.get('stage_advanced_to_proposition', False)
    stage_name = result.get('active_stage_name', 'unknown')

    if stage_advanced:
        score += 20
        subscores['stage_advanced'] = True
        feedback_parts.append(f"Opportunity advanced to '{stage_name}' (Proposition) (20/20)")
    else:
        subscores['stage_advanced'] = False
        feedback_parts.append(
            f"Opportunity stage is '{stage_name}' — should be 'Proposition' (0/20)"
        )

    # ─── Criterion 3: Expected revenue set to 65000 (15 pts) ─────────────────
    revenue_correct = result.get('revenue_correct', False)
    active_revenue = result.get('active_revenue', 0)

    if revenue_correct:
        score += 15
        subscores['revenue_set'] = True
        feedback_parts.append(f"Expected revenue set to ${active_revenue:.0f} ✓ (15/15)")
    elif abs(active_revenue - target_revenue) / max(target_revenue, 1) < 0.10:
        score += 8
        subscores['revenue_set'] = 'close'
        feedback_parts.append(
            f"Revenue ${active_revenue:.0f} close to target ${target_revenue:.0f} but not exact (8/15)"
        )
    else:
        subscores['revenue_set'] = False
        feedback_parts.append(
            f"Revenue ${active_revenue:.0f} does not match target ${target_revenue:.0f} (0/15)"
        )

    # ─── Criterion 4: Activity scheduled on active opportunity (20 pts) ───────
    has_activity = result.get('has_any_activity', False)
    has_phone = result.get('has_phone_activity', False)
    near_deadline = result.get('has_activity_near_deadline', False)
    title_correct = result.get('activity_title_correct', False)

    if has_phone and near_deadline:
        score += 20
        subscores['activity_scheduled'] = True
        feedback_parts.append("Phone call activity scheduled for ~7 days from now (20/20)")
    elif has_phone:
        score += 14
        subscores['activity_scheduled'] = 'phone_wrong_date'
        feedback_parts.append("Phone call activity scheduled but deadline not ~7 days out (14/20)")
    elif has_activity and near_deadline:
        score += 14
        subscores['activity_scheduled'] = 'activity_near_deadline'
        feedback_parts.append("Activity scheduled for ~7 days out (but not a phone call type) (14/20)")
    elif has_activity:
        score += 8
        subscores['activity_scheduled'] = 'activity_any'
        feedback_parts.append("An activity was scheduled but not a phone call or wrong deadline (8/20)")
    else:
        subscores['activity_scheduled'] = False
        feedback_parts.append("No activity scheduled on the active opportunity (0/20)")

    # ─── Criterion 5: Internal note added (20 pts) ───────────────────────────
    has_note = result.get('has_internal_note', False)

    if has_note:
        score += 20
        subscores['note_added'] = True
        feedback_parts.append("Internal note added to active opportunity (20/20)")
    else:
        subscores['note_added'] = False
        feedback_parts.append(
            "No internal note found mentioning pipeline cleanup on active opportunity (0/20)"
        )

    passed = score >= 65

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores,
        "debug": {
            "company": company_name,
            "stale_inactive": result.get('stale_is_inactive'),
            "stage_advanced": stage_advanced,
            "revenue": active_revenue,
            "activities": len(result.get('activities', [])),
        },
    }
