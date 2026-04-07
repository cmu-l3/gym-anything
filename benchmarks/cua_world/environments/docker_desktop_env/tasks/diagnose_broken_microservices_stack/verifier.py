#!/usr/bin/env python3
"""Verifier for diagnose_broken_microservices_stack task.

Scores the agent on fixing a broken 4-service Docker Compose deployment.
Actual verification is also done externally via VLM evaluators.
"""


def verify_diagnose_broken_microservices_stack(traj, env_info, task_info):
    """Verify the broken microservices stack has been fully diagnosed and fixed.

    Scoring (100 points total):
      - All 4 services running:              15 pts
      - Health endpoint returns HTTP 200:     15 pts
      - Database reports connected:           25 pts
      - Cache reports connected:              25 pts
      - Items endpoint returns valid data:    20 pts

    Pass condition: score >= 80
    """
    import json
    import tempfile

    score = 0
    details = {}

    # Load result JSON exported by export_result.sh
    try:
        tmp = tempfile.NamedTemporaryFile(suffix='.json', delete=False)
        tmp.close()
        env_info['copy_from_env']('/tmp/task_result.json', tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result file: {e}",
            "details": {}
        }

    # 1. All 4 services running (15 pts)
    running_count = result.get('running_count', 0)
    if running_count == 4:
        score += 15
        details['all_services_running'] = True
    else:
        details['all_services_running'] = False
        details['running_count'] = running_count

    # 2. Health endpoint reachable with HTTP 200 (15 pts)
    health_code = str(result.get('health_http_code', '000'))
    if health_code == '200':
        score += 15
        details['health_reachable'] = True
    else:
        details['health_reachable'] = False
        details['health_http_code'] = health_code

    # 3. Database connected (25 pts)
    db_status = result.get('database_status', 'unknown')
    if db_status == 'connected':
        score += 25
        details['database_connected'] = True
    else:
        details['database_connected'] = False
        details['database_status'] = db_status

    # 4. Cache connected (25 pts)
    cache_status = result.get('cache_status', 'unknown')
    if cache_status == 'connected':
        score += 25
        details['cache_connected'] = True
    else:
        details['cache_connected'] = False
        details['cache_status'] = cache_status

    # 5. Items endpoint returns valid data (20 pts)
    items_valid = result.get('items_valid', False)
    items_count = result.get('items_count', 0)
    if items_valid and items_count >= 3:
        score += 20
        details['items_working'] = True
        details['items_count'] = items_count
    else:
        details['items_working'] = False
        details['items_count'] = items_count

    passed = score >= 80

    feedback_parts = []
    if not details.get('all_services_running'):
        feedback_parts.append(f"Only {running_count}/4 services running")
    if not details.get('health_reachable'):
        feedback_parts.append(f"Health endpoint returned HTTP {health_code}")
    if not details.get('database_connected'):
        feedback_parts.append(f"Database status: {db_status}")
    if not details.get('cache_connected'):
        feedback_parts.append(f"Cache status: {cache_status}")
    if not details.get('items_working'):
        feedback_parts.append(f"Items endpoint: {items_count} items, valid={items_valid}")

    feedback = f"Score: {score}/100. "
    if feedback_parts:
        feedback += "; ".join(feedback_parts)
    else:
        feedback += "All checks passed."

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }
