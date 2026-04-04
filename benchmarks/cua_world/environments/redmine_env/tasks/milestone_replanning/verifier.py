#!/usr/bin/env python3
"""Verifier for milestone_replanning task.

Checks that the project manager correctly performed sprint replanning:
1. Log aggregation moved to Q1 2025 Goals milestone     (20 pts)
2. Log aggregation priority changed to High             (20 pts)
3. K8s issue priority changed to Immediate              (20 pts)
4. K8s issue has REPRIORITIZED comment                  (20 pts)
5. Scope change notification issue created (alice.chen) (20 pts)

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _any_comment_contains(comments: list, text: str) -> bool:
    text_lower = text.lower()
    for c in comments:
        if isinstance(c, str) and text_lower in c.lower():
            return True
    return False


def verify_milestone_replanning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    result_path = task_info.get('metadata', {}).get(
        'result_file', '/tmp/milestone_replanning_result.json')
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

    log_agg = result.get('log_aggregation_issue', {})
    k8s = result.get('kubernetes_issue', {})
    scope = result.get('scope_change_issue')

    # --- Check 1: Log aggregation moved to Q1 2025 Goals (20 pts) ---
    log_version = log_agg.get('current_version', '')
    baseline_version = log_agg.get('baseline', {}).get('version', 'none')
    if 'q1' in log_version.lower() or ('2025' in log_version and 'q1' in log_version.lower()):
        score += 20
        subscores['log_agg_q1_milestone'] = True
        feedback.append(f"Log aggregation moved to '{log_version}' (Q1 2025 Goals)")
    elif log_version.lower() in ('q1 2025 goals', 'q1 2025'):
        score += 20
        subscores['log_agg_q1_milestone'] = True
        feedback.append(f"Log aggregation milestone is '{log_version}'")
    else:
        subscores['log_agg_q1_milestone'] = False
        feedback.append(
            f"Log aggregation still in '{log_version}' "
            f"(was '{baseline_version}', expected Q1 2025 Goals)"
        )

    # --- Check 2: Log aggregation priority = High (20 pts) ---
    log_priority = log_agg.get('current_priority', '')
    baseline_priority = log_agg.get('baseline', {}).get('priority', 'unknown')
    if log_priority.lower() == 'high':
        score += 20
        subscores['log_agg_priority_high'] = True
        feedback.append(f"Log aggregation priority changed to High")
    else:
        subscores['log_agg_priority_high'] = False
        feedback.append(
            f"Log aggregation priority is '{log_priority}' "
            f"(was '{baseline_priority}', expected High)"
        )

    # --- Check 3: K8s priority = Immediate (20 pts) ---
    k8s_priority = k8s.get('current_priority', '')
    k8s_baseline_priority = k8s.get('baseline', {}).get('priority', 'unknown')
    if k8s_priority.lower() == 'immediate':
        score += 20
        subscores['k8s_priority_immediate'] = True
        feedback.append(f"K8s issue priority changed to Immediate")
    else:
        subscores['k8s_priority_immediate'] = False
        feedback.append(
            f"K8s issue priority is '{k8s_priority}' "
            f"(was '{k8s_baseline_priority}', expected Immediate)"
        )

    # --- Check 4: K8s has REPRIORITIZED comment (20 pts) ---
    k8s_comments = k8s.get('comments', [])
    has_reprioritized = _any_comment_contains(k8s_comments, 'REPRIORITIZED')
    if has_reprioritized:
        score += 20
        subscores['k8s_reprioritized_comment'] = True
        feedback.append("K8s issue has REPRIORITIZED comment")
    else:
        subscores['k8s_reprioritized_comment'] = False
        feedback.append(
            f"K8s issue missing REPRIORITIZED comment "
            f"(found {len(k8s_comments)} comment(s))"
        )

    # --- Check 5: Scope change notification issue created (alice.chen) (20 pts) ---
    if scope and scope != 'null':
        scope_assignee = scope.get('assigned_to', '')
        is_alice = 'alice' in scope_assignee.lower() or 'chen' in scope_assignee.lower()
        has_correct_subject = (
            'scope' in scope.get('subject', '').lower() or
            'q1' in scope.get('subject', '').lower() or
            'sprint' in scope.get('subject', '').lower()
        )
        if is_alice and has_correct_subject:
            score += 20
            subscores['scope_change_issue_created'] = True
            feedback.append(
                f"Scope change issue created: '{scope.get('subject', '')}', "
                f"assigned to '{scope_assignee}'"
            )
        elif is_alice:
            score += 15
            subscores['scope_change_issue_created'] = 'partial'
            feedback.append(
                f"Scope change issue created and assigned to alice.chen "
                f"but subject may not match: '{scope.get('subject', '')}'"
            )
        elif has_correct_subject:
            score += 10
            subscores['scope_change_issue_created'] = 'partial'
            feedback.append(
                f"Scope change issue found but assigned to '{scope_assignee}' "
                f"instead of alice.chen"
            )
        else:
            score += 5
            subscores['scope_change_issue_created'] = 'partial'
            feedback.append(
                f"Issue found but wrong subject and assignee: "
                f"'{scope.get('subject', '')}' / '{scope_assignee}'"
            )
    else:
        subscores['scope_change_issue_created'] = False
        feedback.append("No scope change notification issue found in infra-devops")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "log_agg_version": log_version,
            "log_agg_priority": log_priority,
            "k8s_priority": k8s_priority,
            "k8s_comment_count": len(k8s_comments),
            "scope_change_issue": scope,
        }
    }
