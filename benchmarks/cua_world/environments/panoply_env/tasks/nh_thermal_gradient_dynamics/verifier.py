#!/usr/bin/env python3
"""
Verifier for nh_thermal_gradient_dynamics task.
"""

import json
import os
import tempfile
import re

def verify_nh_thermal_gradient_dynamics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/nh_thermal_gradient_dynamics_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = int(result.get('task_start', 0))

    # 1. January Zonal Mean Plot (20 pts)
    jan_exists = result.get('png_jan_exists', False)
    jan_mtime = int(result.get('png_jan_mtime', 0))
    jan_size = int(result.get('png_jan_size', 0))

    if jan_exists and jan_mtime >= task_start and jan_size >= 10000:
        score += 20
        feedback.append(f"January zonal mean plot exported ({jan_size} bytes)")
    elif jan_exists and jan_mtime >= task_start and jan_size >= 2000:
        score += 10
        feedback.append(f"January plot present but small ({jan_size} bytes, expected >=10KB)")
    else:
        feedback.append(f"January plot missing or not created during task (exists={jan_exists}, size={jan_size})")

    # 2. July Zonal Mean Plot (20 pts)
    jul_exists = result.get('png_jul_exists', False)
    jul_mtime = int(result.get('png_jul_mtime', 0))
    jul_size = int(result.get('png_jul_size', 0))

    if jul_exists and jul_mtime >= task_start and jul_size >= 10000:
        score += 20
        feedback.append(f"July zonal mean plot exported ({jul_size} bytes)")
    elif jul_exists and jul_mtime >= task_start and jul_size >= 2000:
        score += 10
        feedback.append(f"July plot present but small ({jul_size} bytes, expected >=10KB)")
    else:
        feedback.append(f"July plot missing or not created during task (exists={jul_exists}, size={jul_size})")

    # 3. Report Structure (20 pts)
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    jan_grad_str = result.get('jan_gradient', '').strip()
    jul_grad_str = result.get('jul_gradient', '').strip()
    stronger_jet = result.get('stronger_jet', '').strip()

    has_jan = bool(jan_grad_str)
    has_jul = bool(jul_grad_str)
    has_jet = bool(stronger_jet)

    if report_exists and report_mtime >= task_start and has_jan and has_jul and has_jet:
        score += 20
        feedback.append(f"Gradient report complete (Jan={jan_grad_str}, Jul={jul_grad_str}, StrongerJet={stronger_jet})")
    elif report_exists and report_mtime >= task_start and (has_jan or has_jul or has_jet):
        score += 10
        feedback.append("Gradient report partially complete")
    else:
        feedback.append("Gradient report missing or incomplete")

    # Helper to parse float from string (handling units/symbols like K, C, degrees)
    def parse_float(s):
        match = re.search(r'[-+]?\d*\.\d+|\d+', s)
        if match:
            return float(match.group())
        return None

    jan_grad_val = parse_float(jan_grad_str) if has_jan else None
    jul_grad_val = parse_float(jul_grad_str) if has_jul else None

    # 4. Scientific Accuracy (Values) (20 pts)
    # January delta T is ~55-65. July is ~25-30. Allow generous physical bounds.
    jan_accurate = False
    jul_accurate = False

    if jan_grad_val is not None:
        if 45 <= abs(jan_grad_val) <= 75:
            jan_accurate = True
        else:
            feedback.append(f"JAN_GRADIENT_MAGNITUDE ({jan_grad_val}) out of expected range (45-75)")
    
    if jul_grad_val is not None:
        if 15 <= abs(jul_grad_val) <= 35:
            jul_accurate = True
        else:
            feedback.append(f"JUL_GRADIENT_MAGNITUDE ({jul_grad_val}) out of expected range (15-35)")

    if jan_accurate and jul_accurate:
        score += 20
        feedback.append("Both temperature gradients calculated accurately")
    elif jan_accurate or jul_accurate:
        score += 10
        feedback.append("One temperature gradient calculated accurately")

    # 5. Scientific Accuracy (Dynamics) (20 pts)
    # January gradient must be > July gradient, and STRONGER_JET_MONTH should be January
    dynamics_accurate = False
    if jan_grad_val is not None and jul_grad_val is not None:
        if abs(jan_grad_val) > abs(jul_grad_val) and "jan" in stronger_jet.lower():
            dynamics_accurate = True
            score += 20
            feedback.append("Correctly identified January as having the stronger gradient and jet stream")
        else:
            feedback.append(f"Dynamics conclusion incorrect: Jan={jan_grad_val}, Jul={jul_grad_val}, Stronger={stronger_jet}")
    else:
        feedback.append("Missing values to verify dynamics conclusion")

    # Determine Pass
    passed = score >= 80 and dynamics_accurate

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "jan_grad_val": jan_grad_val,
            "jul_grad_val": jul_grad_val,
            "stronger_jet": stronger_jet
        }
    }