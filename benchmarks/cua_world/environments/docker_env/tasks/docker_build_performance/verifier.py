#!/usr/bin/env python3
"""
Verifier for docker_build_performance task.

Scoring (100 points):
  - Image size < 400MB: 30 pts (partial: < 700MB = 15 pts)
  - Cached build time < 60s: 25 pts (partial: < 120s = 12 pts)
  - .dockerignore exists with meaningful content: 15 pts
  - Dev dependencies excluded from production image: 15 pts
  - App starts and /health responds 200: 15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_docker_build_performance(traj, env_info, task_info):
    """Verify Docker image optimization criteria."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/docker_build_result.json", temp_path)
            with open(temp_path, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except Exception:
                pass

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    task_start = result.get("task_start", 0)
    # agent_rebuilt: True only if the agent built a NEW image (different digest from the original)
    # The export script rebuilds :optimized during timing measurement, so we cannot use
    # creation timestamp; we must use image digest comparison instead.
    agent_rebuilt = bool(result.get("agent_rebuilt", 0))

    # ── Criterion 1: Image size (30 pts) ─────────────────────────────────────
    optimized_size_mb = result.get("optimized_size_mb", 9999)
    initial_size_mb = result.get("initial_size_mb", 1200)

    if not agent_rebuilt:
        feedback_parts.append(
            f"Image was not replaced by agent — original :optimized unchanged (0/30)"
        )
        subscores["image_size"] = False
    elif optimized_size_mb < 400:
        score += 30
        subscores["image_size"] = True
        feedback_parts.append(
            f"Image size {optimized_size_mb}MB < 400MB target (+30)"
        )
    elif optimized_size_mb < 700:
        score += 15
        subscores["image_size"] = "partial"
        feedback_parts.append(
            f"Image size {optimized_size_mb}MB — improved but still > 400MB target (15/30)"
        )
    else:
        subscores["image_size"] = False
        feedback_parts.append(
            f"Image size {optimized_size_mb}MB — no meaningful reduction from {initial_size_mb}MB (0/30)"
        )

    # ── Criterion 2: Cached build time (25 pts) ──────────────────────────────
    cached_build_sec = result.get("cached_build_sec", 9999)

    if cached_build_sec < 60:
        score += 25
        subscores["cached_build_time"] = True
        feedback_parts.append(
            f"Cached build: {cached_build_sec}s < 60s target (+25)"
        )
    elif cached_build_sec < 120:
        score += 12
        subscores["cached_build_time"] = "partial"
        feedback_parts.append(
            f"Cached build: {cached_build_sec}s — improved but still > 60s target (12/25)"
        )
    else:
        subscores["cached_build_time"] = False
        feedback_parts.append(
            f"Cached build: {cached_build_sec}s — layer caching not working effectively (0/25)"
        )

    # ── Criterion 3: .dockerignore (15 pts) ──────────────────────────────────
    dockerignore_exists = result.get("dockerignore_exists", 0)
    dockerignore_lines = result.get("dockerignore_lines", 0)

    if dockerignore_exists and dockerignore_lines >= 3:
        score += 15
        subscores["dockerignore"] = True
        feedback_parts.append(f".dockerignore exists with {dockerignore_lines} entries (+15)")
    elif dockerignore_exists:
        score += 7
        subscores["dockerignore"] = "partial"
        feedback_parts.append(f".dockerignore exists but minimal content ({dockerignore_lines} lines) (7/15)")
    else:
        subscores["dockerignore"] = False
        feedback_parts.append(".dockerignore not found (0/15)")

    # ── Criterion 4: Dev dependencies excluded (15 pts) ──────────────────────
    dev_excluded = result.get("dev_deps_excluded", 0)

    if dev_excluded:
        score += 15
        subscores["dev_deps_excluded"] = True
        feedback_parts.append("Dev dependencies excluded from production image (+15)")
    else:
        subscores["dev_deps_excluded"] = False
        feedback_parts.append(
            "Dev dependencies (pytest/black/locust) still present in production image (0/15)"
        )

    # ── Criterion 5: Application health check (15 pts) ───────────────────────
    # Gated on agent_rebuilt: the original image also starts fine, so free points
    # in do-nothing test would occur without this gate (Lesson 20 from best practices).
    app_responds = result.get("app_responds", 0)
    app_code = result.get("app_status_code", "000")

    if app_responds and agent_rebuilt:
        score += 15
        subscores["app_health"] = True
        feedback_parts.append("Application starts and /health responds 200 (+15)")
    elif app_responds and not agent_rebuilt:
        subscores["app_health"] = False
        feedback_parts.append(
            "App responds but no optimization applied — health credit requires actual changes (0/15)"
        )
    else:
        subscores["app_health"] = False
        feedback_parts.append(
            f"Application /health endpoint not responding (HTTP {app_code}) (0/15)"
        )

    # ── GATE: App must work to pass ───────────────────────────────────────────
    if not app_responds and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback_parts.append(
            f"Score capped at {PASS_THRESHOLD - 1}: application must start correctly to pass"
        )

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores,
        "details": {
            "agent_rebuilt": agent_rebuilt,
            "initial_size_mb": initial_size_mb,
            "optimized_size_mb": optimized_size_mb,
            "cached_build_sec": cached_build_sec,
        },
    }
