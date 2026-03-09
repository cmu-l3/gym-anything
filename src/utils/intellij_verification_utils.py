#!/usr/bin/env python3
from __future__ import annotations

import json
import logging
import os
import tempfile


logger = logging.getLogger(__name__)


def copy_and_read_text(copy_from_env, remote_path):
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".tmp")
        tmp.close()
        copy_from_env(remote_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8", errors="ignore") as handle:
            content = handle.read()
        os.unlink(tmp.name)
        return content
    except Exception as exc:
        logger.debug("Failed to read %s: %s", remote_path, exc)
        try:
            os.unlink(tmp.name)
        except Exception:
            pass
        return None


def copy_and_read_binary(copy_from_env, remote_path):
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".tmp")
        tmp.close()
        copy_from_env(remote_path, tmp.name)
        with open(tmp.name, "rb") as handle:
            content = handle.read()
        os.unlink(tmp.name)
        return content
    except Exception as exc:
        logger.debug("Failed to read %s: %s", remote_path, exc)
        try:
            os.unlink(tmp.name)
        except Exception:
            pass
        return None


def verify_java_class_file(copy_from_env, class_path):
    content = copy_and_read_binary(copy_from_env, class_path)
    if content and len(content) >= 4:
        return content[:4] == b"\xca\xfe\xba\xbe"
    return False


def read_json_result(copy_from_env, result_path="/tmp/task_result.json"):
    content = copy_and_read_text(copy_from_env, result_path)
    if content:
        try:
            return json.loads(content)
        except json.JSONDecodeError as exc:
            logger.warning("Invalid JSON in %s: %s", result_path, exc)
    return None


def vlm_verify_intellij_task(traj, env_info, task_description, checklist_items):
    query_vlm = env_info.get("query_vlm")
    if not query_vlm:
        return None

    from vlm_utils import get_final_screenshot, sample_trajectory_frames

    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    images = frames + ([final] if final else [])
    if not images:
        return None

    checklist = "\n".join(f"- {item}" for item in checklist_items)
    prompt = (
        "You are verifying an IntelliJ IDEA workflow.\n"
        f"Task: {task_description}\n"
        "Check whether the screenshots show these items:\n"
        f"{checklist}\n"
        "Return JSON with keys checklist_hits (integer), checklist_total (integer), passed (boolean), feedback (string)."
    )
    try:
        result = query_vlm(prompt=prompt, images=images)
        parsed = result.get("parsed", {}) if isinstance(result, dict) else {}
        hits = int(parsed.get("checklist_hits", 0))
        total = int(parsed.get("checklist_total", len(checklist_items))) or len(checklist_items)
        passed = bool(parsed.get("passed", hits >= max(1, total - 1)))
        return {
            "vlm_score": int((hits / total) * 100) if total else 0,
            "vlm_feedback": parsed.get("feedback", ""),
            "vlm_passed": passed,
        }
    except Exception as exc:
        logger.debug("VLM verification failed: %s", exc)
        return None


__all__ = [
    "copy_and_read_binary",
    "copy_and_read_text",
    "read_json_result",
    "verify_java_class_file",
    "vlm_verify_intellij_task",
]
