#!/usr/bin/env python3
"""Verifier for configure_scqc_parameters_scconfig."""

import json
import os
import tempfile


def _load_result(copy_from_env):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/configure_scqc_parameters_scconfig_result.json", tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def verify_configure_scqc_parameters_scconfig(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result = _load_result(copy_from_env)
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {exc}"}

    if not result.get("config_exists"):
        return {"passed": False, "score": 0, "feedback": "scqc.cfg was not created."}
    if not result.get("config_is_new"):
        return {"passed": False, "score": 0, "feedback": "scqc.cfg was not modified during the task session."}

    expected = {
        "report_interval": "60",
        "report_buffer": "3600",
        "stream_mask": "GE.*.*.*",
        "realtime_buffer": "1800",
    }

    labels = {
        "report_interval": "report.interval",
        "report_buffer": "report.buffer",
        "stream_mask": "streamMask",
        "realtime_buffer": "realtime.buffer",
    }

    score = 0
    feedback = []
    for key, expected_value in expected.items():
        actual = str(result.get(key, "")).strip()
        if actual == expected_value:
            score += 25
            feedback.append(f"{labels[key]}={actual} correct.")
        else:
            feedback.append(f"{labels[key]}='{actual}' (expected '{expected_value}').")

    passed = score >= 75
    return {"passed": passed, "score": score, "feedback": " ".join(feedback)}
