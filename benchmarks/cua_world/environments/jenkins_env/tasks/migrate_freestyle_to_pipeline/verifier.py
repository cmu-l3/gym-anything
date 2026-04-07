#!/usr/bin/env python3
"""
Verifier for Migrate Freestyle to Pipeline task.

The agent must examine 4 interconnected Freestyle jobs and consolidate them into
a single Declarative Pipeline job named 'orders-api-pipeline' with 4 stages.

Scoring (100 points):
  - Job exists & Pipeline type                     :  8 pts
  - Parameters block (6 params × 3pts)             : 18 pts
  - Credential bindings (2 × 6pts)                 : 12 pts
  - Environment variables (DB_HOST, DB_PORT)        :  6 pts
  - 4 stages with correct names (4 × 3pts)         : 12 pts
  - Shell commands preserved (4 × 3pts)             : 12 pts
  - Artifact archiving (2 × 3pts)                   :  6 pts
  - JUnit publishing                                :  5 pts
  - Security node restriction                       :  5 pts
  - Cron trigger (H/30)                             :  5 pts
  - Build discarder (10 builds, 5 artifacts)        :  5 pts
  - Build triggered & completed                     :  6 pts

Pass threshold: 55 points.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_migrate_freestyle_to_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/migrate_freestyle_to_pipeline_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found -- export_result.sh may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON: {e}"}
    except Exception as e:
        logger.error(f"Error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    score = 0
    feedback_parts = []

    # ── Criterion 1: Job exists & is Pipeline type (8 pts) ────
    if result.get("job_exists") and result.get("is_pipeline"):
        score += 8
        feedback_parts.append("Pipeline job exists (8/8)")
    elif result.get("job_exists"):
        score += 3
        feedback_parts.append("Job exists but not Pipeline type (3/8)")
    else:
        feedback_parts.append("Job 'orders-api-pipeline' not found (0/8)")

    # ── Criterion 2: Parameters (18 pts, 3 per param) ─────────
    params = result.get("parameters", {})
    expected_params = {
        "BRANCH_NAME": "string",
        "SKIP_TESTS": "boolean",
        "BUILD_PROFILE": "choice",
        "TEST_SUITE": "string",
        "DEPLOY_REGION": "choice",
        "FORCE_DEPLOY": "boolean",
    }
    param_score = 0
    for pname, ptype in expected_params.items():
        if pname in params:
            if params[pname].get("type") == ptype:
                param_score += 3
            else:
                param_score += 2  # right name, wrong type
    score += param_score
    found_names = [p for p in expected_params if p in params]
    feedback_parts.append(f"Parameters: {len(found_names)}/6 found ({param_score}/18)")

    # ── Criterion 3: Credential bindings (12 pts) ─────────────
    cred_score = 0
    if result.get("has_credential_staging_db"):
        cred_score += 6
    if result.get("has_credential_staging_ssh"):
        cred_score += 6
    score += cred_score
    feedback_parts.append(f"Credentials in script ({cred_score}/12)")

    # ── Criterion 4: Environment variables (6 pts) ────────────
    env_score = 0
    if result.get("has_db_host"):
        env_score += 3
    if result.get("has_db_port"):
        env_score += 3
    score += env_score
    feedback_parts.append(f"Env vars ({env_score}/6)")

    # ── Criterion 5: Stages (12 pts, 3 per stage) ────────────
    stage_score = 0
    for key, label in [
        ("has_stage_build", "Build"),
        ("has_stage_test", "Test"),
        ("has_stage_security", "Security Scan"),
        ("has_stage_deploy", "Deploy"),
    ]:
        if result.get(key):
            stage_score += 3
    score += stage_score
    feedback_parts.append(f"Stages ({stage_score}/12)")

    # ── Criterion 6: Shell commands preserved (12 pts) ────────
    shell_score = 0
    if result.get("shell_has_building"):
        shell_score += 3
    if result.get("shell_has_integration"):
        shell_score += 3
    if result.get("shell_has_owasp"):
        shell_score += 3
    if result.get("shell_has_deploying"):
        shell_score += 3
    score += shell_score
    feedback_parts.append(f"Shell commands ({shell_score}/12)")

    # ── Criterion 7: Artifact archiving (6 pts) ──────────────
    archive_score = 0
    if result.get("has_archive_jar"):
        archive_score += 3
    if result.get("has_archive_security"):
        archive_score += 3
    score += archive_score
    feedback_parts.append(f"Artifact archiving ({archive_score}/6)")

    # ── Criterion 8: JUnit (5 pts) ──────────────────────────
    if result.get("has_junit"):
        score += 5
        feedback_parts.append("JUnit step found (5/5)")
    else:
        feedback_parts.append("JUnit step missing (0/5)")

    # ── Criterion 9: Security node label (5 pts) ─────────────
    if result.get("has_security_node_label"):
        score += 5
        feedback_parts.append("Security-node label (5/5)")
    else:
        feedback_parts.append("Security-node label missing (0/5)")

    # ── Criterion 10: Cron trigger (5 pts) ───────────────────
    if result.get("has_cron_trigger"):
        score += 5
        feedback_parts.append("Cron trigger H/30 (5/5)")
    else:
        feedback_parts.append("Cron trigger missing (0/5)")

    # ── Criterion 11: Build discarder (5 pts) ────────────────
    discarder_score = 0
    if result.get("has_build_discarder"):
        discarder_score += 2
        if str(result.get("num_to_keep")) == "10":
            discarder_score += 2
        if str(result.get("artifact_num_to_keep")) == "5":
            discarder_score += 1
    score += discarder_score
    feedback_parts.append(f"Build discarder ({discarder_score}/5)")

    # ── Criterion 12: Build triggered & completed (6 pts) ────
    build_score = 0
    if result.get("build_triggered"):
        build_score += 3
    build_result = result.get("build_result", "")
    if build_result in ("SUCCESS", "UNSTABLE"):
        build_score += 3
    score += build_score
    feedback_parts.append(f"Build execution ({build_score}/6)")

    score = min(score, 100)
    passed = score >= 55

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
    }
