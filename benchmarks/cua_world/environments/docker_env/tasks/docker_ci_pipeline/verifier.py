#!/usr/bin/env python3
"""
Verifier for docker_ci_pipeline task.

Scoring (100 points):
- pipeline.sh exists & executable: 10 pts
- Dockerfile exists & uses non-root USER: 10 pts
- lint-report.txt valid: 10 pts
- test-results.txt valid: 15 pts
- coverage.txt valid: 10 pts
- security-scan.txt valid: 10 pts
- pipeline-summary.txt valid: 10 pts
- webapp:production exists & < 200MB: 15 pts
- /health endpoint returns 200: 10 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60

def verify_docker_ci_pipeline(traj, env_info, task_info):
    """Verify CI/CD pipeline creation and execution."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/ci_pipeline_result.json", temp_path)
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
    
    # 1. Pipeline Script (10 pts)
    if result.get("pipeline_executable", 0):
        score += 10
        feedback_parts.append("pipeline.sh is executable (+10)")
    elif result.get("pipeline_exists", 0):
        score += 5
        feedback_parts.append("pipeline.sh exists but not executable (+5)")
    else:
        feedback_parts.append("pipeline.sh missing (0/10)")

    # 2. Dockerfile Quality (10 pts)
    d_exists = result.get("dockerfile_exists", 0)
    d_user = result.get("dockerfile_user_check", 0)
    if d_exists and d_user:
        score += 10
        feedback_parts.append("Dockerfile exists with USER instruction (+10)")
    elif d_exists:
        score += 5
        feedback_parts.append("Dockerfile exists but missing USER instruction (+5)")
    else:
        feedback_parts.append("Dockerfile missing (0/10)")

    # Helper for artifact checking
    def check_artifact(stat_key, name, points, content_sample_key=None, content_keyword=None):
        stat = result.get(stat_key, {})
        s_score = 0
        s_msg = ""
        if stat.get("exists", 0) and stat.get("size", 0) > 20: # Min 20 bytes
            # If we have content checks
            valid_content = True
            if content_sample_key and content_keyword:
                sample = result.get(content_sample_key, "")
                # Simple keyword check in sample
                # Note: This is loose, but prevents empty files
                if not sample: # Empty sample means read failure or empty file
                    valid_content = False
            
            if valid_content:
                s_score = points
                s_msg = f"{name} generated (+{points})"
            else:
                s_score = points // 2
                s_msg = f"{name} empty/invalid (+{points//2})"
        else:
            s_msg = f"{name} missing (0/{points})"
        return s_score, s_msg

    # 3. Artifacts (55 pts total)
    # Lint (10)
    s, m = check_artifact("lint_stat", "Lint report", 10, "lint_content_sample", "app")
    score += s; feedback_parts.append(m)
    
    # Test (15)
    s, m = check_artifact("test_stat", "Test results", 15, "test_content_sample", "test")
    score += s; feedback_parts.append(m)

    # Coverage (10)
    s, m = check_artifact("cov_stat", "Coverage report", 10)
    score += s; feedback_parts.append(m)

    # Scan (10)
    s, m = check_artifact("scan_stat", "Security scan", 10, "scan_content_sample", "Total")
    score += s; feedback_parts.append(m)

    # Summary (10)
    s, m = check_artifact("summ_stat", "Pipeline summary", 10)
    score += s; feedback_parts.append(m)

    # 4. Image Quality (15 pts)
    img_exists = result.get("image_exists", 0)
    img_size = result.get("image_size_mb", 999)
    if img_exists:
        if img_size < 200:
            score += 15
            feedback_parts.append(f"Image optimized ({img_size}MB < 200MB) (+15)")
        else:
            score += 5
            feedback_parts.append(f"Image exists but too large ({img_size}MB > 200MB) (+5)")
    else:
        feedback_parts.append("Production image missing (0/15)")

    # 5. Functional Test (10 pts)
    if result.get("health_check_passed", 0):
        score += 10
        feedback_parts.append("Health check passed (+10)")
    else:
        feedback_parts.append("Health check failed (0/10)")

    passed = score >= PASS_THRESHOLD
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }