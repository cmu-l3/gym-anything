#!/usr/bin/env python3
"""
Verifier for grid_tied_cost_monitoring task.

Scoring (100 pts total, pass >= 60):
  - import_w has >= 3 process steps (multiply + log + kWh): 25 pts
  - import_w processlist includes a multiply step (process ID 3): 20 pts
  - export_w has >= 2 process steps (log + kWh):             20 pts
  - >= 4 new smartmeter/grid feeds created:                   20 pts
  - Dashboard 'Grid Energy Monitor' (or similar) exists
    with >= 4 widgets:                                        15 pts
"""


def verify_grid_tied_cost_monitoring(traj, env_info, task_info):
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
        copy_from_env('/tmp/grid_tied_cost_monitoring_result.json', tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result JSON from VM: {e}"
        }

    # GATE: if import_w has no process steps AND no smartmeter/grid feeds exist,
    # the agent did not configure the smartmeter node at all → score=0
    if result.get('import_steps', 0) == 0 and result.get('grid_feed_count', 0) == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAIL: import_w has no process steps and no grid/smartmeter feeds exist. "
                        "Agent did not configure the smartmeter node pipeline.",
            "subscores": {}
        }

    # Criterion 1: import_w has >= 3 process steps (25 pts)
    import_steps = result.get('import_steps', 0)
    if import_steps >= 3:
        score += 25
        feedback.append(f"import_w has {import_steps} process steps (>= 3 required)")
    elif import_steps == 2:
        score += 10
        feedback.append(
            f"import_w has {import_steps} steps (need >= 3 for multiply + log + kWh)"
        )
    elif import_steps == 1:
        score += 4
        feedback.append(f"import_w has only {import_steps} process step")
    else:
        feedback.append("import_w has no process steps configured")

    # Criterion 2: import_w has multiply step (process ID 3) (20 pts)
    if result.get('import_has_multiply'):
        score += 20
        mv = result.get('multiply_value')
        if mv is not None:
            feedback.append(f"import_w has calibration multiply step (value: {mv})")
        else:
            feedback.append("import_w has multiply step configured")
    else:
        feedback.append(
            "import_w missing calibration multiply (add process ID 3 with value 1.15)"
        )

    # Criterion 3: export_w has >= 2 process steps (20 pts)
    export_steps = result.get('export_steps', 0)
    if export_steps >= 2:
        score += 20
        feedback.append(f"export_w has {export_steps} process steps (>= 2 required)")
    elif export_steps == 1:
        score += 8
        feedback.append(f"export_w has {export_steps} step (need >= 2 for log + kWh)")
    else:
        feedback.append("export_w has no process steps configured")

    # Criterion 4: >= 4 grid/smartmeter feeds created (20 pts)
    feed_count = max(
        result.get('grid_feed_count', 0),
        result.get('new_feed_count', 0)
    )
    if feed_count >= 4:
        score += 20
        feedback.append(f"{feed_count} grid/import/export feeds created (>= 4 required)")
    elif feed_count >= 2:
        score += 10
        feedback.append(f"Only {feed_count} grid feeds found (need >= 4)")
    elif feed_count >= 1:
        score += 4
        feedback.append(f"Only {feed_count} grid feed found")
    else:
        feedback.append("No grid/import/export feeds created")

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
                f"Dashboard has {widget_count} widget(s) "
                f"(need >= 4 for import power, export power, import kWh, export kWh)"
            )
    else:
        feedback.append(
            "No Grid Energy Monitor dashboard found (create 'Grid Energy Monitor')"
        )

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": {
            "import_steps":       import_steps,
            "import_has_multiply": result.get('import_has_multiply', False),
            "export_steps":        result.get('export_steps', 0),
            "feeds_created":       feed_count,
            "dashboard":           result.get('dashboard_exists', False),
        }
    }
