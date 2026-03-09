#!/usr/bin/env python3
"""Verifier for cross_project_workload_audit task.

The expected target issue is "Implement centralized log aggregation with OpenSearch"
in infra-devops, which is the only New-status, Normal-priority issue assigned to
carol.santos (the most-loaded developer with 6 open issues across all projects).

Checks:
1. Log aggregation issue reassigned away from Carol Santos      (25 pts)
2. New assignee is bob.walker or grace.lee                      (25 pts)
3. Issue has workload-rebalancing comment                       (25 pts)
4. Time entry of ~0.5h Design logged                           (25 pts)

Pass threshold: 50 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Acceptable reassignment targets (least-loaded developers)
ACCEPTABLE_REASSIGNEES = {'bob walker', 'grace lee', 'bob.walker', 'grace.lee',
                          'bob', 'grace'}
ORIGINAL_ASSIGNEE = 'carol santos'


def _any_comment_contains(comments: list, text: str) -> bool:
    text_lower = text.lower()
    for c in comments:
        if isinstance(c, str) and text_lower in c.lower():
            return True
    return False


def verify_cross_project_workload_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    result_path = task_info.get('metadata', {}).get(
        'result_file', '/tmp/cross_project_workload_audit_result.json')
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env(result_path, tmp.name)
        except FileNotFoundError:
            return {"passed": False, "score": 0,
                    "feedback": "Result file not found — export script may not have run"}
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"JSON parse error: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    score = 0
    feedback = []
    subscores = {}

    issue = result.get('log_aggregation_issue', {})
    baseline = result.get('baseline', {})
    time_entries = result.get('time_entries', [])
    design_hours = result.get('design_hours_logged', 0)

    current_assignee = issue.get('assignee_name', '').lower()
    baseline_assignee = baseline.get('assignee', '').lower()
    current_est_hours = float(issue.get('estimated_hours', 0))
    baseline_est_hours = float(baseline.get('estimated_hours', 0))
    comments = issue.get('comments', [])

    # --- Check 1: Reassigned away from Carol Santos (25 pts) ---
    was_carol = 'carol' in baseline_assignee or 'santos' in baseline_assignee
    is_still_carol = 'carol' in current_assignee or 'santos' in current_assignee

    if was_carol and not is_still_carol and current_assignee not in ('none', 'null', ''):
        score += 25
        subscores['reassigned_from_carol'] = True
        feedback.append(f"Issue reassigned from Carol Santos to '{issue.get('assignee_name', '')}'")
    elif not was_carol:
        # Baseline wasn't carol — maybe already reassigned before task, give credit if not carol
        if not is_still_carol and current_assignee not in ('none', 'null', ''):
            score += 25
            subscores['reassigned_from_carol'] = True
            feedback.append(
                f"Issue assignee is '{issue.get('assignee_name', '')}' (not Carol Santos)"
            )
        else:
            subscores['reassigned_from_carol'] = False
            feedback.append(
                f"Issue still assigned to '{issue.get('assignee_name', '')}' "
                f"(baseline: '{baseline.get('assignee', '')}')"
            )
    else:
        subscores['reassigned_from_carol'] = False
        feedback.append(
            f"Issue still assigned to Carol Santos (expected reassignment)"
        )

    # --- Check 2: Reassigned to bob.walker or grace.lee (25 pts) ---
    reassigned_to_correct = any(name in current_assignee for name in ACCEPTABLE_REASSIGNEES)
    if reassigned_to_correct:
        score += 25
        subscores['reassigned_to_correct_dev'] = True
        feedback.append(f"Correctly reassigned to least-loaded developer: '{issue.get('assignee_name', '')}'")
    else:
        subscores['reassigned_to_correct_dev'] = False
        if current_assignee not in ('none', 'null', ''):
            feedback.append(
                f"Issue assigned to '{issue.get('assignee_name', '')}' "
                f"(expected bob.walker or grace.lee)"
            )
        else:
            feedback.append("Issue has no assignee")

    # --- Check 3: Workload rebalancing comment added (25 pts) ---
    has_workload_comment = (
        _any_comment_contains(comments, 'workload') or
        _any_comment_contains(comments, 'rebalanc') or
        _any_comment_contains(comments, 'burnout') or
        _any_comment_contains(comments, 'capacity')
    )
    if has_workload_comment:
        score += 25
        subscores['workload_comment'] = True
        feedback.append("Issue has workload/rebalancing comment")
    else:
        subscores['workload_comment'] = False
        feedback.append(
            f"Issue missing workload rebalancing comment (found {len(comments)} comment(s))"
        )

    # --- Check 4: 0.5h Design time entry logged (25 pts) ---
    if design_hours >= 0.5:
        score += 25
        subscores['design_time_logged'] = True
        feedback.append(f"Design activity time logged: {design_hours}h")
    else:
        total = result.get('total_hours_logged', 0)
        if total >= 0.5:
            score += 10
            subscores['design_time_logged'] = 'partial'
            feedback.append(
                f"Time logged ({total}h total) but not as Design activity "
                f"(Design: {design_hours}h)"
            )
        else:
            subscores['design_time_logged'] = False
            feedback.append(
                f"No time entry logged (Design: {design_hours}h, total: {total}h)"
            )

    # Bonus: estimated hours updated (not scored separately, but noted)
    if current_est_hours >= baseline_est_hours + 2.0:
        feedback.append(f"Bonus: estimated hours updated from {baseline_est_hours}h to {current_est_hours}h")
    elif current_est_hours > baseline_est_hours:
        feedback.append(
            f"Note: estimated hours changed from {baseline_est_hours}h to {current_est_hours}h "
            f"(expected +2.0h minimum)"
        )

    passed = score >= 50
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "current_assignee": issue.get('assignee_name'),
            "baseline_assignee": baseline.get('assignee'),
            "current_est_hours": current_est_hours,
            "baseline_est_hours": baseline_est_hours,
            "comment_count": len(comments),
            "design_hours": design_hours,
        }
    }
