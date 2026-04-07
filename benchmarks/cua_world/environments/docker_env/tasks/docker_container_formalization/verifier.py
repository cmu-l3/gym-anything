#!/usr/bin/env python3
"""
Verifier for docker_container_formalization task.

Scoring (100 points total):
- Frontend (25 pts): Dockerfile (5), Build (5), Content Match (7), Config/Health (8)
- API (25 pts): Dockerfile (5), Build (5), Status Endpoint (7), Deps Installed (8)
- Cron (25 pts): Dockerfile (5), Build (5), Tools Installed (7), Script Exists (8)
- Audit Report (15 pts): Exists (5), Reasonable Size (5), Mentions all containers (5)
- Image Tagging (10 pts): All 3 images tagged correctly
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_container_formalization(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()
        copy_from_env("/tmp/formalization_result.json", temp_path)
        with open(temp_path, "r") as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback_parts = []

    # --- Frontend ---
    fe = result.get("frontend", {})
    if fe.get("dockerfile_exists"): score += 5
    if fe.get("image_exists"): score += 5
    if fe.get("content_match"): score += 7
    if fe.get("config_match"): score += 8
    
    if fe.get("content_match") and fe.get("config_match"):
        feedback_parts.append("Frontend verified")
    else:
        feedback_parts.append("Frontend incomplete")

    # --- API ---
    api = result.get("api", {})
    if api.get("dockerfile_exists"): score += 5
    if api.get("image_exists"): score += 5
    if api.get("status_endpoint"): score += 7
    if api.get("dependencies"): score += 8
    
    if api.get("status_endpoint"):
        feedback_parts.append("API verified")
    else:
        feedback_parts.append("API issues")

    # --- Cron ---
    cron = result.get("cron", {})
    if cron.get("dockerfile_exists"): score += 5
    if cron.get("image_exists"): score += 5
    if cron.get("tools_installed"): score += 7
    if cron.get("script_exists"): score += 8
    
    if cron.get("tools_installed"):
        feedback_parts.append("Cron verified")
    else:
        feedback_parts.append("Cron issues")

    # --- Report ---
    rep = result.get("report", {})
    if rep.get("exists"): score += 5
    if rep.get("size", 0) > 100: score += 5
    if rep.get("mentions_all"): score += 5

    # --- Image Tagging Bonus ---
    # Implicitly checked by image_exists, but we add 10 points if ALL exist
    if fe.get("image_exists") and api.get("image_exists") and cron.get("image_exists"):
        score += 10
        feedback_parts.append("All tags correct (+10)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": f"Score: {score}/100. " + " | ".join(feedback_parts)
    }