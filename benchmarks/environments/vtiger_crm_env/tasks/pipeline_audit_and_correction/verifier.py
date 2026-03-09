#!/usr/bin/env python3
"""
Verifier for pipeline_audit_and_correction task.

The agent must:
1. Fix Nexus SCADA probability to 100 (Closed Won stage requires 100%)        [25 pts]
2. Fix GreenLeaf probability to ≤50 (Needs Analysis range: 20-50%)            [20 pts]
3. Move Atlas Supply Chain to Closed Lost with probability 0 (stale deal)      [25 pts]
4. Move Catalyst LIMS to Closed Lost with probability 0 (stale deal)           [10 pts]
5. Update Horizon 5G amount to 320000                                          [20 pts]

Pass threshold: 65/100
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 65


def verify_pipeline_audit_and_correction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/pipeline_audit_result.json', tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    # --- Criterion 1: Nexus SCADA probability fixed to 100 (25 pts) ---
    nexus_stage = result.get('nexus_stage', '').strip()
    try:
        nexus_prob = float(result.get('nexus_probability', -1))
    except (TypeError, ValueError):
        nexus_prob = -1.0

    if nexus_prob == 100.0:
        score += 25
        feedback.append("C1 PASS: Nexus SCADA probability corrected to 100% for Closed Won stage (25/25)")
    elif 90 <= nexus_prob <= 100:
        score += 10
        feedback.append(f"C1 PARTIAL: Nexus SCADA probability = {nexus_prob} — close but Closed Won requires exactly 100% (10/25)")
    else:
        feedback.append(f"C1 FAIL: Nexus SCADA probability = {nexus_prob} — should be 100% for Closed Won stage (0/25)")

    # --- Criterion 2: GreenLeaf probability fixed to ≤50 (20 pts) ---
    try:
        greenleaf_prob = float(result.get('greenleaf_probability', 999))
    except (TypeError, ValueError):
        greenleaf_prob = 999.0

    greenleaf_stage = result.get('greenleaf_stage', '').strip()

    if 20 <= greenleaf_prob <= 50:
        score += 20
        feedback.append(f"C2 PASS: GreenLeaf probability corrected to {greenleaf_prob}% (within Needs Analysis range 20-50%) (20/20)")
    elif 0 <= greenleaf_prob <= 55:
        score += 10
        feedback.append(f"C2 PARTIAL: GreenLeaf probability = {greenleaf_prob}% — acceptable range is 20-50% for Needs Analysis (10/20)")
    elif greenleaf_stage in ('Closed Lost', 'Closed Won'):
        # Agent changed the stage instead — give partial credit if probability is correct for new stage
        if greenleaf_stage == 'Closed Lost' and greenleaf_prob == 0:
            score += 15
            feedback.append(f"C2 PARTIAL: GreenLeaf moved to Closed Lost/0% — acceptable alternative fix (15/20)")
        else:
            feedback.append(f"C2 FAIL: GreenLeaf probability = {greenleaf_prob}% (stage={greenleaf_stage}) — inconsistency not resolved (0/20)")
    else:
        feedback.append(f"C2 FAIL: GreenLeaf probability still {greenleaf_prob}% for Needs Analysis stage — should be 20-50% (0/20)")

    # --- Criterion 3: Atlas Supply Chain → Closed Lost, probability 0 (25 pts) ---
    atlas_stage = result.get('atlas_stage', '').strip()
    try:
        atlas_prob = float(result.get('atlas_probability', -1))
    except (TypeError, ValueError):
        atlas_prob = -1.0

    if atlas_stage == 'Closed Lost' and atlas_prob == 0:
        score += 25
        feedback.append("C3 PASS: Atlas Supply Chain moved to Closed Lost with probability 0 (stale deal cleaned up) (25/25)")
    elif atlas_stage == 'Closed Lost':
        score += 15
        feedback.append(f"C3 PARTIAL: Atlas moved to Closed Lost but probability = {atlas_prob} (should be 0) (15/25)")
    elif atlas_prob == 0:
        score += 5
        feedback.append(f"C3 PARTIAL: Atlas probability set to 0 but stage = '{atlas_stage}' (should be Closed Lost) (5/25)")
    else:
        feedback.append(f"C3 FAIL: Atlas Supply Chain — stage='{atlas_stage}', probability={atlas_prob}. Expected Closed Lost/0 for stale past-dated deal (0/25)")

    # --- Criterion 4: Catalyst LIMS → Closed Lost, probability 0 (10 pts) ---
    catalyst_stage = result.get('catalyst_stage', '').strip()
    try:
        catalyst_prob = float(result.get('catalyst_probability', -1))
    except (TypeError, ValueError):
        catalyst_prob = -1.0

    if catalyst_stage == 'Closed Lost' and catalyst_prob == 0:
        score += 10
        feedback.append("C4 PASS: Catalyst LIMS moved to Closed Lost with probability 0 (10/10)")
    elif catalyst_stage == 'Closed Lost':
        score += 5
        feedback.append(f"C4 PARTIAL: Catalyst moved to Closed Lost but probability = {catalyst_prob} (5/10)")
    else:
        feedback.append(f"C4 FAIL: Catalyst LIMS — stage='{catalyst_stage}', prob={catalyst_prob}. Expected Closed Lost/0 (0/10)")

    # --- Criterion 5: Horizon 5G amount updated to 320000 (20 pts) ---
    try:
        horizon_amount = float(str(result.get('horizon_amount', 0)).replace(',', '').strip())
    except (TypeError, ValueError):
        horizon_amount = 0.0

    if abs(horizon_amount - 320000) < 1:
        score += 20
        feedback.append(f"C5 PASS: Horizon 5G amount updated to $320,000 (20/20)")
    elif 310000 <= horizon_amount <= 330000:
        score += 10
        feedback.append(f"C5 PARTIAL: Horizon 5G amount = ${horizon_amount:.0f} — close but expected exactly $320,000 (10/20)")
    else:
        feedback.append(f"C5 FAIL: Horizon 5G amount = ${horizon_amount:.0f} — should be $320,000 (0/20)")

    score = min(score, 100)
    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
