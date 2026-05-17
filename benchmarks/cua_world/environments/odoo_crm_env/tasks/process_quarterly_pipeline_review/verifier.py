#!/usr/bin/env python3
"""
Verifier for process_quarterly_pipeline_review task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_pipeline_review(traj, env_info, task_info):
    """
    Verify the quarterly pipeline review actions taken on three Odoo CRM
    opportunities seeded with real company data (Weis Markets, VSE Corporation,
    Insteel Industries).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get('connection_error'):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Database connection failed: {result.get('error_msg')}"
        }

    score = 0
    feedback = []

    # ------------------------------------------------------------------
    # 1. Weis Markets — must be marked Lost with reason "Too Expensive"
    #    (deal lost to Azure's bundled pricing; CFO budget cap)
    # ------------------------------------------------------------------
    weis = result.get('weis', {})
    if not weis.get('exists'):
        feedback.append("❌ Opportunity 'Cloud Migration - Weis Markets' not found.")
    else:
        if weis.get('active') is False:
            score += 15
            feedback.append("✅ Weis Markets marked as Lost.")

            reason = weis.get('lost_reason')
            if reason == "Too Expensive":
                score += 15
                feedback.append("✅ Weis Markets lost reason is 'Too Expensive'.")
            else:
                feedback.append(
                    f"❌ Weis Markets lost reason is '{reason}', expected 'Too Expensive'."
                )
        else:
            feedback.append("❌ Weis Markets is still Active (not marked Lost).")

    # ------------------------------------------------------------------
    # 2. VSE Corporation — must have "At Risk" tag + Priority 0
    #    (champion resigned; new leadership skeptical; timeline delayed)
    # ------------------------------------------------------------------
    vse = result.get('vse', {})
    if not vse.get('exists'):
        feedback.append("❌ Opportunity 'ERP Rollout - VSE Corporation' not found.")
    else:
        tags = vse.get('tags', [])
        if "At Risk" in tags:
            score += 20
            feedback.append("✅ VSE Corporation tagged 'At Risk'.")
        else:
            feedback.append(f"❌ VSE Corporation tags: {tags}, expected 'At Risk'.")

        priority = str(vse.get('priority'))
        if priority == '0':
            score += 10
            feedback.append("✅ VSE Corporation priority set to Low (0 stars).")
        else:
            feedback.append(
                f"❌ VSE Corporation priority is {priority} stars, expected 0."
            )

    # ------------------------------------------------------------------
    # 3. Insteel Industries — must be in Negotiation stage + 90% probability
    #    (CFO and COO gave verbal go-ahead; legal reviewing MSA)
    # ------------------------------------------------------------------
    insteel = result.get('insteel', {})
    if not insteel.get('exists'):
        feedback.append("❌ Opportunity 'Consulting Retainer - Insteel Industries' not found.")
    else:
        stage = insteel.get('stage')
        if stage == "Negotiation":
            score += 20
            feedback.append("✅ Insteel Industries moved to 'Negotiation' stage.")
        else:
            feedback.append(
                f"❌ Insteel Industries stage is '{stage}', expected 'Negotiation'."
            )

        prob = insteel.get('probability', 0)
        if 89.9 <= prob <= 90.1:
            score += 20
            feedback.append("✅ Insteel Industries probability set to 90%.")
        else:
            feedback.append(
                f"❌ Insteel Industries probability is {prob}%, expected 90%."
            )

    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }
