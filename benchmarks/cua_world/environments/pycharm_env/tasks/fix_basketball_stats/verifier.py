#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_basketball_stats(traj, env_info, task_info):
    """
    Verifies the fix_basketball_stats task.
    
    Scoring:
    - Bug 1 (Shared State): 35 points (Critical data corruption issue)
    - Bug 2 (Tie-Breaker): 35 points (Complex logic)
    - Bug 3 (Streak): 20 points (Simple logic)
    - Regression Check: 10 points (All happy path tests pass)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/fix_basketball_stats_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Bug 1: Shared State
    if result.get('bug1_fixed_test'):
        score += 35
        feedback_parts.append("Bug 1 (Player Stats Shared State) Fixed (+35)")
    else:
        feedback_parts.append("Bug 1 FAILED: test_player_stats_isolation did not pass")

    # 2. Verify Bug 2: Tie-Breaker
    if result.get('bug2_fixed_test'):
        score += 35
        feedback_parts.append("Bug 2 (Head-to-Head Tiebreaker) Fixed (+35)")
    else:
        feedback_parts.append("Bug 2 FAILED: test_standings_head_to_head_tiebreaker did not pass")

    # 3. Verify Bug 3: Streak Logic
    # We check both the test result and static analysis (reset to 0 must exist)
    if result.get('bug3_fixed_test') and result.get('code_check_streak_reset_added'):
        score += 20
        feedback_parts.append("Bug 3 (Streak Reset) Fixed (+20)")
    elif result.get('bug3_fixed_test'):
        # Partial credit if test passes but static analysis is unsure
        score += 15
        feedback_parts.append("Bug 3 Test Passed (Static check warning) (+15)")
    else:
        feedback_parts.append("Bug 3 FAILED: test_streak_calculation_reset_on_loss did not pass")

    # 4. Regression Check
    # If pytest exit code is 0, it means ALL tests passed (including regressions)
    if result.get('pytest_exit_code') == 0:
        score += 10
        feedback_parts.append("Regression Tests Passed (+10)")
    else:
        # Check if we at least passed the specific bug tests but failed others
        failed = result.get('tests_failed', 0)
        if failed > 0:
            feedback_parts.append(f"Regression Check FAILED: {failed} tests failing")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }