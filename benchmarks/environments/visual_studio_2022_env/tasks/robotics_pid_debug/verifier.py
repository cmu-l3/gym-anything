"""
Verifier for robotics_pid_debug task.

Scoring (100 points):
  - Bug 1 fixed: PID derivative term sign corrected:          35 pts
  - Bug 2 fixed: JointLimiter clamp condition corrected:      35 pts
  - Bug 3 fixed: VelocityScaler divide instead of multiply:   20 pts
  - Build passes (0 errors):                                   10 pts

Pass threshold: 60 points
Build gate: if build_errors > 0, score capped at 40
"""

import json
import os
import re
import shutil
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\robotics_pid_debug_result.json"
PID_PATH    = "C:\\Users\\Docker\\source\\repos\\ArmController\\PidController.cs"
LIM_PATH    = "C:\\Users\\Docker\\source\\repos\\ArmController\\JointLimiter.cs"
SCALER_PATH = "C:\\Users\\Docker\\source\\repos\\ArmController\\VelocityScaler.cs"


def _has(pattern, text, flags=re.IGNORECASE | re.DOTALL):
    return bool(re.search(pattern, text, flags))


def verify_robotics_pid_debug(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.mkdtemp(prefix="verify_robotics_")
    try:
        # --- Step 1: Read export result JSON ---
        result = {}
        json_local = os.path.join(tmp, "result.json")
        try:
            copy_from_env(RESULT_PATH, json_local)
            with open(json_local, encoding="utf-8-sig") as f:
                result = json.load(f)
        except FileNotFoundError:
            return {"passed": False, "score": 0,
                    "feedback": "Result JSON not found — export script may not have run"}
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Cannot read result JSON: {e}"}

        # --- Anti-gaming gate ---
        if not result.get("any_modified", False):
            return {"passed": False, "score": 0,
                    "feedback": "No controller files were modified — no work detected"}

        # --- Step 2: Independently read source files ---
        def _read_remote(remote, name):
            local = os.path.join(tmp, name)
            try:
                copy_from_env(remote, local)
                with open(local, encoding="utf-8-sig") as f:
                    return f.read()
            except Exception:
                return ""

        pid_src    = _read_remote(PID_PATH,    "PidController.cs")
        lim_src    = _read_remote(LIM_PATH,    "JointLimiter.cs")
        scaler_src = _read_remote(SCALER_PATH, "VelocityScaler.cs")

        score = 0
        fb    = []

        # ── Bug 1: PID derivative sign (35 pts) ───────────────────────────────
        # Bug:     _previousError - error   (inverted → positive feedback)
        # Correct: error - _previousError   (standard discrete PID derivative)
        if pid_src:
            still_inverted = _has(r"_previousError\s*-\s*error\b", pid_src) and \
                             not _has(r"\berror\s*-\s*_previousError\b", pid_src)
            pid_fixed      = _has(r"\berror\s*-\s*_previousError\b", pid_src) and \
                             not _has(r"_previousError\s*-\s*error\b", pid_src)
        else:
            still_inverted = not result.get("pid_fixed", False)
            pid_fixed      = result.get("pid_fixed", False)

        if pid_fixed:
            score += 35
            fb.append("PID derivative term fixed — error-previousError is correct (+35)")
        elif not still_inverted:
            # Modified but neither pattern found — give partial credit
            score += 15
            fb.append("PID file modified but derivative pattern unclear (+15)")
        else:
            fb.append("PID derivative sign still inverted — causes positive feedback / oscillation (0/35)")

        # ── Bug 2: JointLimiter inverted condition (35 pts) ───────────────────
        # Bug:     else { return requestedAngle; }  (returns out-of-range values unclamped)
        # Correct: Math.Clamp(requestedAngle, MinAngle, MaxAngle) — unconditional
        #          OR: correct if/else with clamping in the out-of-range branch
        if lim_src:
            # Look for the bug: bare "return requestedAngle;" in else branch
            has_bare_return = _has(r"else\s*\{[^}]*return requestedAngle\s*;", lim_src)
            # Look for correct pattern: Math.Clamp without an else return requestedAngle
            has_clamp = _has(r"Math\.Clamp\s*\(requestedAngle,\s*MinAngle,\s*MaxAngle\s*\)", lim_src)
            # Also accept: correctly structured if (< min) return min; if (> max) return max;
            has_correct_guards = (
                _has(r"requestedAngle\s*<\s*MinAngle", lim_src) and
                _has(r"requestedAngle\s*>\s*MaxAngle", lim_src)
            )
            lim_fixed = (has_clamp or has_correct_guards) and not has_bare_return
        else:
            lim_fixed = result.get("lim_fixed", False)

        if lim_fixed:
            score += 35
            fb.append("JointLimiter clamping logic corrected (+35)")
        elif not result.get("lim_has_bug", True):
            score += 15
            fb.append("JointLimiter modified — condition may be partially fixed (+15)")
        else:
            fb.append("JointLimiter still returns unclamped out-of-range values (0/35)")

        # ── Bug 3: VelocityScaler multiply → divide (20 pts) ─────────────────
        # Bug:     velocityMilliRadPerSec * MilliRadiansPerRadian  (1000x too large)
        # Correct: velocityMilliRadPerSec / MilliRadiansPerRadian  (mrad/s → rad/s)
        if scaler_src:
            still_multiply = _has(r"velocityMilliRadPerSec\s*\*\s*MilliRadiansPerRadian", scaler_src) and \
                             not _has(r"velocityMilliRadPerSec\s*/\s*(?:MilliRadiansPerRadian|1000)", scaler_src)
            scaler_fixed   = _has(r"velocityMilliRadPerSec\s*/\s*(?:MilliRadiansPerRadian|1000)", scaler_src) and \
                             not _has(r"velocityMilliRadPerSec\s*\*\s*MilliRadiansPerRadian", scaler_src)
        else:
            still_multiply = not result.get("scaler_fixed", False)
            scaler_fixed   = result.get("scaler_fixed", False)

        if scaler_fixed:
            score += 20
            fb.append("VelocityScaler corrected to divide by 1000 (mrad/s → rad/s) (+20)")
        elif not still_multiply:
            score += 8
            fb.append("VelocityScaler modified but divide pattern unclear (+8)")
        else:
            fb.append("VelocityScaler still multiplies by 1000 — 1000x velocity scale error (0/20)")

        # ── Build gate ────────────────────────────────────────────────────────
        build_success = result.get("build_success", False)
        build_errors  = result.get("build_errors", 999)

        if build_success and build_errors == 0:
            fb.append("Build: OK (0 errors)")
        else:
            if score > 40:
                score = 40
                fb.append(f"BUILD FAILED ({build_errors} errors) — score capped at 40")
            else:
                fb.append(f"BUILD FAILED ({build_errors} errors)")

        passed = score >= 60
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(fb)
        }

    except Exception as e:
        logger.exception("Verification error")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
