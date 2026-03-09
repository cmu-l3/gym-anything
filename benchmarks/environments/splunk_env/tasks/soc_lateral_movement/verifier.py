#!/usr/bin/env python3
"""Verifier for soc_lateral_movement task.

The task asks the agent to investigate compromise patterns and build detection
infrastructure — without specifying exact artifact names or schedules.

Scoring (each criterion = 20 points, total = 100):
1. At least one NEW saved search/alert was created (not pre-existing)
2. The best new search references the security_logs index
3. The best new search logic includes BOTH failure and success detection
4. The best new search is scheduled (continuous monitoring)
5. The best new search has a cron schedule set
"""

import json, tempfile, os, re, logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

POINTS_PER_CRITERION = 20
PASS_THRESHOLD = 80


def search_detects_both_states(search_text):
    low = search_text.lower()
    has_fail = any(kw in low for kw in ['failed', 'failure', 'invalid', 'denied', 'reject'])
    has_success = any(kw in low for kw in ['accepted', 'success', 'granted', 'authenticated'])
    return has_fail and has_success


def score_search(s):
    sc = 0
    low = s.get('search', '').lower()
    if 'security_logs' in low: sc += 1
    if search_detects_both_states(s.get('search', '')): sc += 1
    if s.get('is_scheduled', False): sc += 1
    if s.get('cron_schedule', ''): sc += 1
    return sc


def verify_soc_lateral_movement(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/soc_lateral_movement_result.json", tmp.name)
        with open(tmp.name) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name): os.unlink(tmp.name)

    analysis = data.get('analysis', {})
    new_searches = analysis.get('new_searches', [])

    score = 0
    feedback = []
    subscores = {}

    # Criterion 1: at least one new search created
    if new_searches:
        score += POINTS_PER_CRITERION
        feedback.append(f"New search(es) created: {[s['name'] for s in new_searches[:3]]}")
        subscores['new_alert_created'] = True
    else:
        feedback.append("FAIL: No new saved searches or alerts were created")
        subscores['new_alert_created'] = False
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback), "subscores": subscores, "details": {}}

    best = max(new_searches, key=score_search)
    best_search = best.get('search', '')

    # Criterion 2: references security_logs
    refs_sec = 'security_logs' in best_search.lower()
    if refs_sec:
        score += POINTS_PER_CRITERION
        feedback.append(f"Search '{best['name']}' references security_logs")
        subscores['references_security_logs'] = True
    else:
        feedback.append(f"FAIL: Best new search ('{best['name']}') does not reference security_logs")
        subscores['references_security_logs'] = False

    # Criterion 3: detects both failure and success
    detects_both = search_detects_both_states(best_search)
    if detects_both:
        score += POINTS_PER_CRITERION
        feedback.append("Search contains both failure and success detection keywords")
        subscores['detects_both_states'] = True
    else:
        feedback.append("FAIL: Search must detect BOTH failed and successful auth events")
        subscores['detects_both_states'] = False

    # Criterion 4: is scheduled
    if best.get('is_scheduled', False):
        score += POINTS_PER_CRITERION
        feedback.append("Search is scheduled for continuous monitoring")
        subscores['is_scheduled'] = True
    else:
        feedback.append("FAIL: Search must be scheduled (is_scheduled=1)")
        subscores['is_scheduled'] = False

    # Criterion 5: has cron expression
    if best.get('cron_schedule', ''):
        score += POINTS_PER_CRITERION
        feedback.append(f"Cron schedule configured: '{best['cron_schedule']}'")
        subscores['has_cron'] = True
    else:
        feedback.append("FAIL: Scheduled search must have a cron expression")
        subscores['has_cron'] = False

    return {
        "passed": score >= PASS_THRESHOLD,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "best_search_name": best.get('name', ''),
            "cron_schedule": best.get('cron_schedule', ''),
            "search_preview": best_search[:200],
            "total_new": len(new_searches),
        }
    }
