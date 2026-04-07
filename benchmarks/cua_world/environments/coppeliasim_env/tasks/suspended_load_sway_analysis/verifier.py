#!/usr/bin/env python3
"""
Verifier for suspended_load_sway_analysis task.

Uses a multi-signal approach combining:
1. File verification and Anti-gaming checks (timestamps).
2. Trajectory VLM verification to confirm visual construction of the mechanism.
3. Logical Verification (Control logic): The smooth profile must reduce sway.
4. Physical Authenticity: Validates the simulation isn't faked by checking the
   natural oscillation period of the residual pendulum sway. A 1.0m pendulum
   in Earth gravity natively oscillates at ~2.0 seconds.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/sway_analysis_result.json"


def verify_suspended_load_sway_analysis(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get("metadata", {})
    min_sway_reduction_pct = metadata.get("min_sway_reduction_pct", 25.0)
    expected_period = metadata.get("expected_period_s", 2.006)
    period_tolerance = metadata.get("period_tolerance_s", 0.4)

    # Read exported result
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []

    # -------------------------------------------------------------------------
    # Criterion 1: File Generation & Timestamps (20 pts)
    # -------------------------------------------------------------------------
    json_fields = result.get("json_fields", {})
    if result.get("csv_exists") and result.get("csv_is_new") and result.get("json_exists") and result.get("json_is_new"):
        if json_fields.get("has_fields") and abs(json_fields.get("pendulum_length_m", 0.0) - 1.0) < 0.1:
            score += 20
            feedback.append("✅ Files generated after task start with correct fields (+20)")
        else:
            score += 10
            feedback.append("⚠️ Files exist but JSON missing fields or incorrect pendulum length (partial: 10/20)")
    else:
        feedback.append("❌ Output files missing or stale (predate task start)")
        # Fail early if files aren't properly generated
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # -------------------------------------------------------------------------
    # Criterion 2: Trial Completeness & VLM Trajectory (20 pts)
    # -------------------------------------------------------------------------
    csv_analysis = result.get("csv_analysis", {})
    has_abrupt = csv_analysis.get("has_abrupt", False)
    has_smooth = csv_analysis.get("has_smooth", False)
    reached_target = csv_analysis.get("reached_target", False)

    trial_score = 0
    if has_abrupt and has_smooth and reached_target:
        trial_score += 10
        feedback.append("✅ Both abrupt and smooth trials logged reaching target distance (+10)")
    else:
        feedback.append("❌ Trial data incomplete (missing trial types or failed to reach 2.0m)")

    # VLM Verification: Does the trajectory actually show the scene construction?
    vlm_score = 0
    query_vlm = env_info.get("query_vlm")
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            if frames and final:
                vlm_prompt = (
                    "Review these frames from a CoppeliaSim session. Do they show the agent constructing "
                    "a gantry crane or pendulum mechanism (e.g., a trolley/block with a suspended object) "
                    "and running a simulation? Answer strictly with a JSON object: {\"crane_simulated\": true/false, "
                    "\"reason\": \"brief explanation\"}"
                )
                vlm_result = query_vlm(prompt=vlm_prompt, images=frames + [final])
                parsed = vlm_result.get("parsed", {})
                
                if parsed.get("crane_simulated"):
                    vlm_score += 10
                    feedback.append("✅ VLM confirmed visual construction of crane/pendulum (+10)")
                else:
                    feedback.append(f"⚠️ VLM did not clearly see crane simulation ({parsed.get('reason', 'unknown')})")
        except Exception as e:
            logger.warning(f"VLM verification failed during execution: {e}")
    
    score += trial_score + vlm_score

    # -------------------------------------------------------------------------
    # Criterion 3: Sway Reduction Control Logic (30 pts)
    # -------------------------------------------------------------------------
    abrupt_sway = csv_analysis.get("abrupt_max_sway", 0.0)
    smooth_sway = csv_analysis.get("smooth_max_sway", 0.0)
    
    if abrupt_sway > 0 and smooth_sway > 0:
        reduction_pct = ((abrupt_sway - smooth_sway) / abrupt_sway) * 100.0
        if reduction_pct >= min_sway_reduction_pct:
            score += 30
            feedback.append(f"✅ Smooth profile reduced sway by {reduction_pct:.1f}% (≥{min_sway_reduction_pct}%) (+30)")
        elif reduction_pct > 0:
            score += 15
            feedback.append(f"⚠️ Smooth profile only reduced sway by {reduction_pct:.1f}% (partial: 15/30)")
        else:
            feedback.append(f"❌ Smooth profile failed to reduce sway (Abrupt: {abrupt_sway:.1f}°, Smooth: {smooth_sway:.1f}°)")
    else:
        feedback.append("❌ Invalid sway max values (0.0), physics missing")

    # -------------------------------------------------------------------------
    # Criterion 4: Physics Authenticity Anti-Gaming Check (30 pts)
    # -------------------------------------------------------------------------
    period_est = csv_analysis.get("period_estimate", 0.0)
    
    if period_est > 0:
        period_diff = abs(period_est - expected_period)
        if period_diff <= period_tolerance:
            score += 30
            feedback.append(f"✅ Physics Authenticity Passed: Natural oscillation period {period_est:.2f}s matches expected ~{expected_period:.2f}s (+30)")
        else:
            feedback.append(f"❌ Physics Authenticity Failed: Oscillation period {period_est:.2f}s is not physically realistic for a 1.0m pendulum. Fake data suspected.")
    else:
        feedback.append("❌ Physics Authenticity Failed: Could not detect valid pendulum oscillations in time-series data.")

    # Passed if score >= 70 and Physics Authenticity is strictly met
    passed = (score >= 70) and (abs(period_est - expected_period) <= period_tolerance)

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }