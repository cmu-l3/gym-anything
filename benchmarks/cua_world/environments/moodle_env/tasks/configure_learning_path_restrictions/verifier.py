#!/usr/bin/env python3
"""Verifier for Configure Learning Path Restrictions task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_learning_path(traj, env_info, task_info):
    """
    Verify that the sequential learning path is correctly configured.

    Criteria:
    1. All 3 modules exist (30 pts)
    2. Completion tracking enabled on Mod 1 & 2 (20 pts)
    3. Mod 2 restricted by Mod 1 completion (20 pts)
    4. Mod 3 restricted by Mod 2 completion (20 pts)
    5. Newly created (10 pts)

    Pass threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/learning_path_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # Load module info
        mod1 = result.get('module1', {})
        mod2 = result.get('module2', {})
        mod3 = result.get('module3', {})
        task_start = int(result.get('task_start_timestamp', 0))

        # 1. Check Existence (30 pts - 10 each)
        if mod1.get('exists'):
            score += 10
            feedback_parts.append("Module 1 found")
        else:
            feedback_parts.append("Module 1 MISSING")

        if mod2.get('exists'):
            score += 10
            feedback_parts.append("Module 2 found")
        else:
            feedback_parts.append("Module 2 MISSING")

        if mod3.get('exists'):
            score += 10
            feedback_parts.append("Module 3 found")
        else:
            feedback_parts.append("Module 3 MISSING")

        # 2. Check Completion Enabled (20 pts - 10 each for Mod 1 & 2)
        # completion > 0 means enabled (1=manual, 2=conditional)
        if mod1.get('completion', 0) > 0:
            score += 10
            feedback_parts.append("Mod 1 completion enabled")
        else:
            feedback_parts.append("Mod 1 completion DISABLED")

        if mod2.get('completion', 0) > 0:
            score += 10
            feedback_parts.append("Mod 2 completion enabled")
        else:
            feedback_parts.append("Mod 2 completion DISABLED")

        # 3. Check Restriction Mod 2 -> Mod 1 (20 pts)
        # availability string should contain Mod 1's cm_id
        mod1_cmid = mod1.get('cm_id')
        mod2_avail = mod2.get('availability', '') or ''
        
        if mod1_cmid and str(mod1_cmid) in mod2_avail and 'completion' in mod2_avail:
            score += 20
            feedback_parts.append("Mod 2 restricted by Mod 1")
        else:
            feedback_parts.append("Mod 2 restriction INCORRECT/MISSING")

        # 4. Check Restriction Mod 3 -> Mod 2 (20 pts)
        mod2_cmid = mod2.get('cm_id')
        mod3_avail = mod3.get('availability', '') or ''
        
        if mod2_cmid and str(mod2_cmid) in mod3_avail and 'completion' in mod3_avail:
            score += 20
            feedback_parts.append("Mod 3 restricted by Mod 2")
        else:
            feedback_parts.append("Mod 3 restriction INCORRECT/MISSING")

        # 5. Check Anti-Gaming (Timestamp) (10 pts)
        # At least one module should be created after task start
        created_during = False
        for m in [mod1, mod2, mod3]:
            if m.get('added', 0) > task_start:
                created_during = True
                break
        
        if created_during:
            score += 10
        else:
            feedback_parts.append("Modules appear pre-existing (timestamp check failed)")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}