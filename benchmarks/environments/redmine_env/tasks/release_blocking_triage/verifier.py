#!/usr/bin/env python3
"""Verifier for release_blocking_triage task.

Checks that the engineering manager correctly triaged v1.0 Launch issues:
1. Payment gateway issue (Urgent priority): has RELEASE BLOCKER comment     (25 pts)
2. Login button issue: has reassignment comment (carol/reassigned/due date)  (25 pts)
3. Login button issue: reassigned to Carol Santos                           (25 pts)
4. Login button issue: due_date matches v1.0 Launch milestone due date      (25 pts)

Pass threshold: 60 points (at least 3 of 4 criteria)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _any_comment_contains(comments: list, text: str) -> bool:
    """Return True if any comment (case-insensitive) contains the given text."""
    text_lower = text.lower()
    for c in comments:
        if isinstance(c, str) and text_lower in c.lower():
            return True
    return False


def verify_release_blocking_triage(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    result_path = task_info.get('metadata', {}).get('result_file',
                                                     '/tmp/release_blocking_triage_result.json')
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

    pg = result.get('payment_gateway', {})
    lb = result.get('login_button', {})
    v1_due = result.get('v1_launch_due_date', 'none')

    # --- Check 1: Payment gateway has RELEASE BLOCKER comment (25 pts) ---
    pg_comments = pg.get('comments', [])
    has_release_blocker = _any_comment_contains(pg_comments, 'RELEASE BLOCKER')
    if has_release_blocker:
        score += 25
        subscores['payment_gateway_release_blocker_comment'] = True
        feedback.append("Payment gateway issue has RELEASE BLOCKER comment")
    else:
        subscores['payment_gateway_release_blocker_comment'] = False
        feedback.append(
            f"Payment gateway issue is missing RELEASE BLOCKER comment "
            f"(found {len(pg_comments)} comment(s))"
        )

    # --- Check 2: Login button has reassignment comment (25 pts) ---
    lb_comments = lb.get('comments', [])
    has_lb_comment = (
        _any_comment_contains(lb_comments, 'carol') or
        _any_comment_contains(lb_comments, 'reassigned') or
        _any_comment_contains(lb_comments, 'due date') or
        _any_comment_contains(lb_comments, 'v1.0')
    )
    if has_lb_comment:
        score += 25
        subscores['login_button_has_comment'] = True
        feedback.append(f"Login button has reassignment comment ({len(lb_comments)} comment(s))")
    else:
        subscores['login_button_has_comment'] = False
        feedback.append(
            f"Login button missing reassignment comment "
            f"(found {len(lb_comments)} comment(s), expected comment about carol/reassignment/due date)"
        )

    # --- Check 3: Login button reassigned to Carol Santos (25 pts) ---
    lb_assignee = lb.get('assignee_name', '')
    if 'carol' in lb_assignee.lower() or 'santos' in lb_assignee.lower():
        score += 25
        subscores['login_button_reassigned'] = True
        feedback.append(f"Login button reassigned to '{lb_assignee}'")
    else:
        subscores['login_button_reassigned'] = False
        feedback.append(
            f"Login button assignee is '{lb_assignee}' (expected Carol Santos)"
        )

    # --- Check 4: Login button due date matches v1.0 Launch due date (25 pts) ---
    lb_due = lb.get('due_date', 'none')
    if v1_due != 'none' and lb_due == v1_due:
        score += 25
        subscores['login_button_due_date_aligned'] = True
        feedback.append(f"Login button due_date ({lb_due}) matches v1.0 Launch milestone ({v1_due})")
    elif v1_due == 'none':
        # Can't determine v1.0 Launch due date — give partial credit if due date was set
        if lb_due != 'none' and lb_due not in ('null', ''):
            score += 15
            subscores['login_button_due_date_aligned'] = 'partial'
            feedback.append(f"Login button due_date set to {lb_due} (v1.0 Launch due date unavailable for comparison)")
        else:
            subscores['login_button_due_date_aligned'] = False
            feedback.append("Login button due_date not set and v1.0 Launch due date unavailable")
    else:
        subscores['login_button_due_date_aligned'] = False
        feedback.append(
            f"Login button due_date ({lb_due}) does not match v1.0 Launch ({v1_due})"
        )

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "payment_gateway_priority": pg.get('priority'),
            "payment_gateway_comments_count": len(pg_comments),
            "login_button_assignee": lb_assignee,
            "login_button_due_date": lb_due,
            "login_button_comments_count": len(lb_comments),
            "v1_launch_due_date": v1_due,
        }
    }
