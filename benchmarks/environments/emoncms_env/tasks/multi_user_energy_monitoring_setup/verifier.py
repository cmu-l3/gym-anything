#!/usr/bin/env python3
"""
Verifier for multi_user_energy_monitoring_setup task.

Scoring (100 pts total, pass >= 60):
  - User 'tenant_a' exists:                                      10 pts
  - tenant_a has >= 2 inputs with non-empty process lists:       25 pts
  - tenant_a has >= 2 feeds:                                     15 pts
  - User 'tenant_b' exists:                                      10 pts
  - tenant_b has >= 2 inputs with non-empty process lists:       25 pts
  - tenant_b has >= 2 feeds:                                     15 pts
"""


def verify_multi_user_energy_monitoring_setup(traj, env_info, task_info):
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
        copy_from_env('/tmp/multi_user_energy_monitoring_setup_result.json', tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result JSON from VM: {e}"
        }

    def score_tenant(tenant_data, label):
        """Score one tenant's setup. Returns (points, feedback_lines)."""
        pts = 0
        lines = []

        # User existence (10 pts)
        if tenant_data.get('exists'):
            pts += 10
            uid = tenant_data.get('userid', '?')
            email = tenant_data.get('email', '')
            lines.append(f"{label} account exists (id={uid}, email={email})")
        else:
            lines.append(f"{label} account does NOT exist — create user first")
            return pts, lines  # Can't score the rest without a user

        # Inputs with process lists (25 pts)
        inputs_with_pl = tenant_data.get('inputs_with_process', 0)
        input_count    = tenant_data.get('input_count', 0)
        if inputs_with_pl >= 2:
            pts += 25
            lines.append(
                f"{label} has {inputs_with_pl}/{input_count} inputs with process lists (>= 2)"
            )
        elif inputs_with_pl == 1:
            pts += 10
            lines.append(
                f"{label} has {inputs_with_pl}/{input_count} input with process list "
                f"(need >= 2 — post data to both hvac_w and lighting_w and configure each)"
            )
        else:
            lines.append(
                f"{label} has {input_count} input(s) but none have process lists configured"
            )

        # Feeds (15 pts)
        feed_count = tenant_data.get('feed_count', 0)
        if feed_count >= 2:
            pts += 15
            lines.append(f"{label} has {feed_count} feed(s) (>= 2 required)")
        elif feed_count == 1:
            pts += 6
            lines.append(f"{label} has {feed_count} feed (need >= 2)")
        else:
            lines.append(f"{label} has no feeds configured")

        return pts, lines

    tenant_a = result.get('tenant_a', {})
    tenant_b = result.get('tenant_b', {})

    pts_a, lines_a = score_tenant(tenant_a, 'tenant_a')
    pts_b, lines_b = score_tenant(tenant_b, 'tenant_b')

    score = pts_a + pts_b
    feedback = lines_a + lines_b

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": {
            "tenant_a_exists":          tenant_a.get('exists', False),
            "tenant_a_inputs_with_pl":  tenant_a.get('inputs_with_process', 0),
            "tenant_a_feeds":           tenant_a.get('feed_count', 0),
            "tenant_b_exists":          tenant_b.get('exists', False),
            "tenant_b_inputs_with_pl":  tenant_b.get('inputs_with_process', 0),
            "tenant_b_feeds":           tenant_b.get('feed_count', 0),
        }
    }
