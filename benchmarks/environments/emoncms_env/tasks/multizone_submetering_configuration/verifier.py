#!/usr/bin/env python3
"""
Verifier for multizone_submetering_configuration task.

Scoring (100 pts total, pass >= 60):
  - zone_hvac/power_w has >= 2 process steps:           20 pts
  - zone_lighting/power_w has >= 2 process steps:       20 pts
  - zone_sockets/power_w has >= 2 process steps:        20 pts
  - >= 6 new zone feeds created (power + kWh per zone): 25 pts
  - Dashboard 'Building Submetering' (or similar)
    exists with >= 4 widgets:                           15 pts
"""


def verify_multizone_submetering_configuration(traj, env_info, task_info):
    import json
    import os
    import tempfile
    import logging

    logger = logging.getLogger(__name__)
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback = []

    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
            tmp_path = f.name
        copy_from_env('/tmp/multizone_submetering_configuration_result.json', tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result JSON from VM: {e}"
        }

    # GATE: if ALL zone inputs have zero steps AND no zone feeds exist,
    # the agent did not configure the submetering node at all → score=0
    all_steps_zero = (
        result.get('hvac_process_steps', 0) == 0 and
        result.get('lighting_process_steps', 0) == 0 and
        result.get('sockets_process_steps', 0) == 0
    )
    if all_steps_zero and result.get('zone_feed_count', 0) == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAIL: no zone inputs have process steps and no zone feeds exist. "
                        "Agent did not configure the submetering node pipeline.",
            "subscores": {}
        }

    zones = [
        ('hvac_process_steps',    'hvac_has_kwh',     'zone_hvac/power_w'),
        ('lighting_process_steps','lighting_has_kwh',  'zone_lighting/power_w'),
        ('sockets_process_steps', 'sockets_has_kwh',   'zone_sockets/power_w'),
    ]

    # Criteria 1-3: each zone input has >= 2 process steps (20 pts each)
    zone_scores = []
    for steps_key, kwh_key, label in zones:
        steps = result.get(steps_key, 0)
        has_kwh = result.get(kwh_key, False)
        if steps >= 2:
            score += 20
            zone_scores.append(steps)
            feedback.append(f"{label}: {steps} process steps configured")
        elif steps == 1:
            score += 7
            zone_scores.append(steps)
            feedback.append(f"{label}: only {steps} step (need >=2 for log+kWh)")
        else:
            zone_scores.append(0)
            feedback.append(f"{label}: no process steps — data not being logged")

        if steps >= 2 and not has_kwh:
            feedback.append(f"  (note: {label} has {steps} steps but no Power-to-kWh process)")

    # Criterion 4: >= 6 zone feeds exist (25 pts)
    feed_count = max(
        result.get('zone_feed_count', 0),
        result.get('new_feed_count', 0)
    )
    if feed_count >= 6:
        score += 25
        feedback.append(f"{feed_count} zone feeds configured (>= 6 required)")
    elif feed_count >= 4:
        score += 15
        feedback.append(f"{feed_count} zone feeds (need >= 6 for power+kWh per zone)")
    elif feed_count >= 2:
        score += 7
        feedback.append(f"Only {feed_count} zone feeds found")
    else:
        feedback.append("No zone feeds created")

    # Criterion 5: dashboard exists with >= 4 widgets (15 pts)
    if result.get('dashboard_exists'):
        score += 8
        dash_name = result.get('dashboard_name', '')
        feedback.append(f"Dashboard '{dash_name}' exists")
        widget_count = result.get('dashboard_widget_count', 0)
        if widget_count >= 4:
            score += 7
            feedback.append(f"Dashboard has {widget_count} widgets (>= 4 required)")
        else:
            feedback.append(
                f"Dashboard has {widget_count} widget(s) (need >= 4 to show all 3 zones)"
            )
    else:
        feedback.append(
            "No Building Submetering dashboard found (create 'Building Submetering')"
        )

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": {
            "hvac_steps":     result.get('hvac_process_steps', 0),
            "lighting_steps": result.get('lighting_process_steps', 0),
            "sockets_steps":  result.get('sockets_process_steps', 0),
            "feeds_created":  feed_count,
            "dashboard":      result.get('dashboard_exists', False),
        }
    }
