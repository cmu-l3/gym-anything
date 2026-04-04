#!/usr/bin/env python3
"""Verifier for sprint_closeout_mobile_v2 task.

Checks that the Scrum Master correctly performed sprint closeout actions:
1. Dark mode issue: status changed to Closed                        (20 pts)
2. Offline sync issue: moved to v2.1 Hotfix milestone               (20 pts)
3. Offline sync issue: has Deferred comment                         (10 pts)
4. Push notif issue: has >=1.5h Testing time entry                  (25 pts)
5. Push notif issue: status changed to Resolved                     (15 pts)
6. Closeout summary issue created (Closed, v2.0 Release, alice.chen)(10 pts)

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


def verify_sprint_closeout_mobile_v2(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    result_path = task_info.get('metadata', {}).get(
        'result_file', '/tmp/sprint_closeout_mobile_v2_result.json')
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

    dark = result.get('dark_mode_issue', {})
    offline = result.get('offline_sync_issue', {})
    push = result.get('push_notif_issue', {})
    closeout = result.get('closeout_issue')

    # --- Check 1: Dark mode issue status = Closed (20 pts) ---
    dark_status = dark.get('status', '')
    dark_baseline = dark.get('baseline', {}).get('status', 'unknown')
    if dark_status.lower() == 'closed':
        score += 20
        subscores['dark_mode_closed'] = True
        feedback.append("Dark mode issue status changed to Closed")
    else:
        subscores['dark_mode_closed'] = False
        feedback.append(
            f"Dark mode issue status is '{dark_status}' "
            f"(was '{dark_baseline}', expected Closed)"
        )

    # --- Check 2: Offline sync moved to v2.1 Hotfix (20 pts) ---
    offline_version = offline.get('current_version', '')
    offline_baseline_version = offline.get('baseline', {}).get('version', 'unknown')
    if 'v2.1' in offline_version or 'hotfix' in offline_version.lower():
        score += 20
        subscores['offline_sync_moved_to_hotfix'] = True
        feedback.append(f"Offline sync moved to '{offline_version}' milestone")
    else:
        subscores['offline_sync_moved_to_hotfix'] = False
        feedback.append(
            f"Offline sync still in '{offline_version}' "
            f"(was '{offline_baseline_version}', expected v2.1 Hotfix)"
        )

    # --- Check 3: Offline sync has Deferred comment (10 pts) ---
    offline_comments = offline.get('comments', [])
    has_deferred = (
        _any_comment_contains(offline_comments, 'Deferred') or
        _any_comment_contains(offline_comments, 'deferred') or
        _any_comment_contains(offline_comments, 'hotfix') or
        _any_comment_contains(offline_comments, 'v2.1')
    )
    if has_deferred:
        score += 10
        subscores['offline_sync_deferred_comment'] = True
        feedback.append("Offline sync has deferred/hotfix comment")
    else:
        subscores['offline_sync_deferred_comment'] = False
        feedback.append(
            f"Offline sync missing deferred comment "
            f"(found {len(offline_comments)} comment(s))"
        )

    # --- Check 4: Push notif has >=1.5h Testing time entry (25 pts) ---
    push_testing_hours = float(push.get('testing_hours', 0))
    push_total_hours = float(push.get('total_hours', 0))
    if push_testing_hours >= 1.5:
        score += 25
        subscores['push_notif_testing_hours'] = True
        feedback.append(f"Push notif issue has {push_testing_hours}h Testing logged")
    else:
        subscores['push_notif_testing_hours'] = False
        feedback.append(
            f"Push notif has {push_testing_hours}h Testing logged "
            f"({push_total_hours}h total, expected >=1.5h with Testing activity)"
        )

    # --- Check 5: Push notif status = Resolved (15 pts) ---
    push_status = push.get('status', '')
    push_baseline_status = push.get('baseline', {}).get('status', 'unknown')
    if push_status.lower() == 'resolved':
        score += 15
        subscores['push_notif_resolved'] = True
        feedback.append("Push notif issue status changed to Resolved")
    else:
        subscores['push_notif_resolved'] = False
        feedback.append(
            f"Push notif status is '{push_status}' "
            f"(was '{push_baseline_status}', expected Resolved)"
        )

    # --- Check 6: Closeout summary issue created (10 pts) ---
    if closeout and closeout != 'null':
        is_alice = (
            'alice' in closeout.get('assigned_to', '').lower() or
            'chen' in closeout.get('assigned_to', '').lower()
        )
        is_v2_release = 'v2.0' in closeout.get('fixed_version', '')
        is_closed = closeout.get('status', '').lower() in ('closed',)
        subject_ok = (
            'closeout' in closeout.get('subject', '').lower() or
            'sprint' in closeout.get('subject', '').lower()
        )
        if subject_ok:
            score += 10
            subscores['closeout_issue_created'] = True
            details_list = []
            if is_alice:
                details_list.append(f"assigned to '{closeout.get('assigned_to', '')}'")
            else:
                details_list.append(f"assignee '{closeout.get('assigned_to', '')}' (expected alice.chen)")
            if is_v2_release:
                details_list.append("version v2.0 Release")
            if is_closed:
                details_list.append("status Closed")
            feedback.append(f"Closeout issue created: {', '.join(details_list)}")
        else:
            score += 5
            subscores['closeout_issue_created'] = 'partial'
            feedback.append(
                f"Issue found but subject doesn't match: '{closeout.get('subject', '')}'"
            )
    else:
        subscores['closeout_issue_created'] = False
        feedback.append("No sprint closeout summary issue found in mobile-app-v2")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "dark_mode_status": dark_status,
            "offline_version": offline_version,
            "push_status": push_status,
            "push_testing_hours": push_testing_hours,
            "closeout_issue": closeout,
        }
    }
