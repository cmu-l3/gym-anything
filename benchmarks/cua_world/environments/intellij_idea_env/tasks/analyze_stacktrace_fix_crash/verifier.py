#!/usr/bin/env python3
"""Verifier for analyze_stacktrace_fix_crash task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_analyze_stacktrace_fix_crash(traj, env_info, task_info):
    """
    Verify that the agent fixed the NPE bug identified by the stack trace.

    Criteria:
    1. Bug Fixed (60 pts): Injected test case with null address passes (no NPE).
    2. Code Compiles (20 pts): Project builds successfully.
    3. Tool Usage (20 pts): VLM verifies use of "Analyze Stack Trace" tool or navigation from log.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read programmatic results
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # Criterion 1: Bug Fixed (60 pts)
    fix_verified = result.get('fix_verified', False)
    if fix_verified:
        score += 60
        feedback_parts.append("Bug fixed: NullPointerException prevented in verification test")
    else:
        feedback_parts.append("Bug NOT fixed: Verification test failed (NPE still thrown)")

    # Criterion 2: Compiles (20 pts)
    compiles = result.get('compiles', False)
    if compiles:
        score += 20
        feedback_parts.append("Code compiles successfully")
    else:
        feedback_parts.append("Code failed to compile")

    # Criterion 3: Tool Usage / VLM (20 pts)
    # Check if agent used the "Analyze Stack Trace" tool
    vlm_score = 0
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        
        # Sample frames to find evidence of tool usage
        frames = sample_trajectory_frames(traj, num_samples=5)
        
        prompt = """
        You are verifying if an agent used the "Analyze Stack Trace" feature in IntelliJ IDEA.
        Look at the sequence of screenshots.
        
        Signs of success:
        1. A dialog box titled "Analyze Stack Trace" or "Analyze Stack Trace or Thread Dump".
        2. A tool window/panel at the bottom showing a stack trace with clickable links (blue text).
        3. The agent pasting a stack trace into a text area.
        4. The agent navigating to 'OrderProcessingService.java' immediately after viewing a log or stack trace.
        
        Did the agent use the stack trace analysis tool or clearly navigate based on the log?
        Respond with JSON: {"used_tool": boolean, "confidence": "high/medium/low", "reason": "string"}
        """
        
        try:
            vlm_resp = query_vlm(prompt=prompt, images=frames)
            if vlm_resp and vlm_resp.get('success'):
                parsed = vlm_resp.get('parsed', {})
                if parsed.get('used_tool', False):
                    vlm_score = 20
                    feedback_parts.append("VLM confirmed usage of Analyze Stack Trace tool")
                else:
                    feedback_parts.append("VLM did not detect Analyze Stack Trace tool usage")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if they fixed the bug, give partial credit for "manual" finding
            if fix_verified:
                vlm_score = 10
                feedback_parts.append("VLM failed but bug was fixed (partial tool credit)")

    score += vlm_score

    # Final check
    # Must fix bug and compile to pass
    passed = fix_verified and compiles and score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }