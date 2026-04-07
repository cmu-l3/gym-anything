#!/usr/bin/env python3
"""
Verifier for the fix_bme280_embedded_driver task.

Robust Verification Strategy:
1. Recompiles the agent's C code with a HIDDEN set of I2C raw data/calibration.
2. Compares the output against a known perfect C implementation running against the same hidden mock.
3. Tests 5 independent axes: Initialization, Temp Precedence, Press Struct, Humid Sequence, Humid Endianness.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bme280_driver(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    agent_out = result.get("agent_out", {})
    truth_out = result.get("truth_out", {})
    
    score = 0
    feedback_parts = []
    
    logger.info(f"Agent Output: {agent_out}")
    logger.info(f"Truth Output: {truth_out}")

    # ================================================================
    # 1. Initialization Check (ID Mismatch) (20 points)
    # ================================================================
    agent_error = agent_out.get("error")
    if agent_error:
        feedback_parts.append(f"[-] Bug 1 Failed: Initialization or execution failed ({agent_error})")
        # If initialization fails, the rest of the reads won't execute. Return early with 0 score.
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }
    else:
        score += 20
        feedback_parts.append("[+] Bug 1 Fixed: Driver successfully initialized (Device ID correct)")

    # ================================================================
    # 2. Temperature Accuracy (Precedence Error) (20 points)
    # ================================================================
    a_temp = agent_out.get("temperature", -999.0)
    t_temp = truth_out.get("temperature", 0.0)
    
    if abs(a_temp - t_temp) <= 0.5:
        score += 20
        feedback_parts.append("[+] Bug 2 Fixed: Temperature parsed with correct bitwise precedence")
    else:
        feedback_parts.append(f"[-] Bug 2 Failed: Temperature mismatch (Agent: {a_temp:.2f}, Truth: {t_temp:.2f})")

    # ================================================================
    # 3. Pressure Accuracy (Struct Signedness) (20 points)
    # ================================================================
    a_press = agent_out.get("pressure", -999.0)
    t_press = truth_out.get("pressure", 0.0)
    
    if abs(a_press - t_press) <= 2.0:
        score += 20
        feedback_parts.append("[+] Bug 3 Fixed: Pressure calculation correct (calibration struct uses int16_t)")
    else:
        feedback_parts.append(f"[-] Bug 3 Failed: Pressure mismatch, likely uint16_t cast error (Agent: {a_press:.2f}, Truth: {t_press:.2f})")

    # ================================================================
    # 4. Humidity Stale Check (Register Sequence) (20 points)
    # ================================================================
    a_hum = agent_out.get("humidity", -999.0)
    t_hum = truth_out.get("humidity", 0.0)
    
    if abs(a_hum - 0.00) < 0.01 and abs(t_hum - 0.00) > 0.1:
        feedback_parts.append("[-] Bug 4 Failed: Humidity is stale (0.00). ctrl_hum was not written before ctrl_meas.")
    else:
        score += 20
        feedback_parts.append("[+] Bug 4 Fixed: Humidity updates (ctrl_hum sequence correct)")

    # ================================================================
    # 5. Humidity Accuracy (Endianness) (20 points)
    # ================================================================
    # Check if bug 4 was fixed before evaluating bug 5 (if stale, it's 0.0, so it naturally fails)
    if abs(a_hum - 0.00) >= 0.01:
        if abs(a_hum - t_hum) <= 1.0:
            score += 20
            feedback_parts.append("[+] Bug 5 Fixed: Humidity endianness correct")
        else:
            feedback_parts.append(f"[-] Bug 5 Failed: Humidity mismatch, likely endianness (Agent: {a_hum:.2f}, Truth: {t_hum:.2f})")
    else:
        feedback_parts.append("[-] Bug 5 Skipped: Humidity cannot be verified while stale")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }