#!/usr/bin/env python3
"""
Verifier for solar_storage_monitoring_pipeline task.

Scoring (100 pts total, pass >= 60):
  - solar_w has >= 2 process steps (Log to Feed + Power to kWh):  25 pts
  - solar_w has Power-to-kWh process (process ID 4):               20 pts
  - All 3 battery inputs have non-empty process lists:             25 pts
  - >= 4 new pvbms/solar/battery feeds created:                    20 pts
  - Dashboard named 'Solar Storage Monitor' (or similar) exists:   10 pts
"""


def verify_solar_storage_monitoring_pipeline(traj, env_info, task_info):
    import json
    import os
    import tempfile
    import logging

    logger = logging.getLogger(__name__)
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback = []

    # Copy result JSON from VM
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
            tmp_path = f.name
        copy_from_env('/tmp/solar_storage_monitoring_pipeline_result.json', tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result JSON from VM: {e}"
        }

    # GATE: agent must have configured the pvbms node — if solar_w has no steps
    # AND no pvbms/solar/battery feeds exist, they worked on the wrong node entirely
    if result.get('solar_process_count', 0) == 0 and result.get('pvbms_feed_count', 0) == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAIL: solar_w has no process steps and no pvbms/solar feeds exist. "
                        "Agent did not configure the pvbms node pipeline.",
            "subscores": {}
        }

    # Criterion 1: solar_w has >= 2 process steps (25 pts)
    solar_steps = result.get('solar_process_count', 0)
    if solar_steps >= 2:
        score += 25
        feedback.append(f"solar_w has {solar_steps} process steps (>=2 required)")
    elif solar_steps == 1:
        score += 8
        feedback.append(f"solar_w has only {solar_steps} process step (need >=2 for log+kWh)")
    else:
        feedback.append("solar_w has no process steps configured")

    # Criterion 2: solar_w has Power-to-kWh process (process ID 4) (20 pts)
    if result.get('solar_has_kwh_process'):
        score += 20
        feedback.append("solar_w has Power-to-kWh energy accumulation (process 4)")
    else:
        feedback.append("solar_w missing Power-to-kWh process (add process ID 4 to log kWh)")

    # Criterion 3: all 3 battery inputs have process lists (25 pts total: 8+8+9)
    battery_ok = 0
    for key, label in [
        ('battery_soc_has_process',       'battery_soc'),
        ('battery_charge_has_process',    'battery_charge_w'),
        ('battery_discharge_has_process', 'battery_discharge_w'),
    ]:
        if result.get(key):
            battery_ok += 1
            feedback.append(f"{label} has process list configured")
        else:
            feedback.append(f"{label} has no process list — data not being logged")
    pts = [0, 8, 16, 25][battery_ok]
    score += pts

    # Criterion 4: >= 4 pvbms/solar/battery feeds exist (20 pts)
    feed_count = max(
        result.get('pvbms_feed_count', 0),
        result.get('new_feed_count', 0)
    )
    if feed_count >= 5:
        score += 20
        feedback.append(f"{feed_count} solar/battery feeds configured (>= 5)")
    elif feed_count >= 4:
        score += 15
        feedback.append(f"{feed_count} solar/battery feeds configured (>= 4)")
    elif feed_count >= 2:
        score += 8
        feedback.append(f"Only {feed_count} feeds found (need >= 4 for all channels + kWh)")
    else:
        feedback.append("Insufficient feeds created for pvbms monitoring")

    # Criterion 5: solar/battery dashboard exists (10 pts)
    if result.get('dashboard_exists'):
        score += 7
        dash_name = result.get('dashboard_name', '')
        feedback.append(f"Dashboard '{dash_name}' exists")
        widget_count = result.get('dashboard_widget_count', 0)
        if widget_count >= 4:
            score += 3
            feedback.append(f"Dashboard has {widget_count} widgets (>= 4 required)")
        else:
            feedback.append(
                f"Dashboard has {widget_count} widget(s) (need >= 4 to cover all channels)"
            )
    else:
        feedback.append("No Solar/Battery/PV dashboard found (create 'Solar Storage Monitor')")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": {
            "solar_process_steps": solar_steps,
            "solar_kwh_process": result.get('solar_has_kwh_process', False),
            "battery_inputs_configured": battery_ok,
            "feeds_created": feed_count,
            "dashboard_exists": result.get('dashboard_exists', False),
        }
    }
