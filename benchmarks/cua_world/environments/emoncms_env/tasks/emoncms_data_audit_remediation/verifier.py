#!/usr/bin/env python3
"""
Verifier for emoncms_data_audit_remediation task.

Five independent broken configurations were injected at setup.
Each fixed configuration earns 20 points.

Scoring (100 pts total, pass >= 60):
  - power1 input processlist references a valid (existing) feed ID:    20 pts
  - solar input processlist references a valid (existing) feed ID:     20 pts
  - House Power feed has interval > 0:                                  20 pts
  - House Temperature feed has engine > 0 (storage enabled):            20 pts
  - Solar PV feed has a non-empty tag:                                  20 pts
"""


def verify_emoncms_data_audit_remediation(traj, env_info, task_info):
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
        copy_from_env('/tmp/emoncms_data_audit_remediation_result.json', tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result JSON from VM: {e}"
        }

    # Criterion 1: power1 input references a valid feed ID (20 pts)
    if result.get('power1_references_valid_feed'):
        score += 20
        fids = result.get('power1_feed_ids_referenced', [])
        feedback.append(f"power1 processlist references valid feed (IDs: {fids})")
    else:
        pl = result.get('power1_processlist', '')
        fids = result.get('power1_feed_ids_referenced', [])
        feedback.append(
            f"power1 processlist still broken: '{pl}' "
            f"(referenced feed IDs {fids} do not exist)"
        )

    # Criterion 2: solar input references a valid feed ID (20 pts)
    if result.get('solar_references_valid_feed'):
        score += 20
        fids = result.get('solar_feed_ids_referenced', [])
        feedback.append(f"solar processlist references valid feed (IDs: {fids})")
    else:
        pl = result.get('solar_processlist', '')
        fids = result.get('solar_feed_ids_referenced', [])
        feedback.append(
            f"solar processlist still broken: '{pl}' "
            f"(referenced feed IDs {fids} do not exist)"
        )

    # Criterion 3: House Power feed has interval > 0 (20 pts)
    interval = result.get('house_power_interval', 0)
    if result.get('house_power_interval_valid'):
        score += 20
        feedback.append(f"House Power feed interval fixed: {interval}s")
    else:
        feedback.append(
            f"House Power feed interval still {interval} "
            f"(must be > 0 for PHPFina to store data)"
        )

    # Criterion 4: House Temperature feed has engine > 0 (20 pts)
    engine = result.get('house_temp_engine', 0)
    if result.get('house_temp_engine_valid'):
        score += 20
        feedback.append(f"House Temperature feed engine fixed: engine={engine} (active)")
    else:
        feedback.append(
            f"House Temperature feed engine still {engine} "
            f"(must be > 0 to enable storage; e.g. engine=5 for PHPFina)"
        )

    # Criterion 5: Solar PV feed has non-empty tag (20 pts)
    tag = result.get('solar_pv_tag', '')
    if result.get('solar_pv_tag_valid'):
        score += 20
        feedback.append(f"Solar PV feed tag fixed: '{tag}'")
    else:
        feedback.append(
            "Solar PV feed tag is still empty (set a descriptive tag, e.g. 'solar')"
        )

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": {
            "power1_fixed":      result.get('power1_references_valid_feed', False),
            "solar_fixed":       result.get('solar_references_valid_feed', False),
            "house_power_fixed": result.get('house_power_interval_valid', False),
            "house_temp_fixed":  result.get('house_temp_engine_valid', False),
            "solar_pv_fixed":    result.get('solar_pv_tag_valid', False),
        }
    }
