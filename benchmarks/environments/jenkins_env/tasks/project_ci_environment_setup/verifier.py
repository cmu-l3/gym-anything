#!/usr/bin/env python3
"""
Verifier for Project CI Environment Setup task.

The agent must create from scratch:
  1. alpha-backend-build   : Pipeline job with Git SCM (github.com/jenkinsci/pipeline-examples,
                             branch master) and H/15 SCM polling
  2. alpha-frontend-build  : Any job type with NODE_VERSION choice param (16/18/20)
                             and build discarder keeping 7 builds
  3. npm-registry-token    : Secret text credential
  4. Project-Alpha CI      : List view containing both jobs

Scoring (100 points):
  - alpha-backend-build exists as Pipeline with correct Git URL : 25 pts
  - alpha-backend-build has H/15 SCM polling                   : 15 pts
  - alpha-frontend-build NODE_VERSION choice param (16/18/20)  : 25 pts
  - alpha-frontend-build build discarder keeps 7 builds        : 15 pts
  - npm-registry-token exists as secret text                    : 10 pts
  - View 'Project-Alpha CI' contains both jobs                  : 10 pts

Pass threshold: 60 points.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_project_ci_environment_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/project_ci_environment_setup_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.sh may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON: {e}"}
    except Exception as e:
        logger.error(f"Error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    backend  = result.get('alpha_backend_build', {})
    frontend = result.get('alpha_frontend_build', {})
    cred     = result.get('npm_registry_token', {})
    view     = result.get('view_project_alpha_ci', {})

    # ── Criterion 1: alpha-backend-build Pipeline + Git URL ───
    if backend.get('exists', False):
        is_pipeline     = backend.get('is_pipeline', False)
        git_url_correct = backend.get('git_url_correct', False)
        git_url         = backend.get('git_url', '')

        if is_pipeline and git_url_correct:
            score += 25
            subscores['backend_pipeline_git'] = True
            feedback_parts.append(
                "alpha-backend-build: Pipeline with correct Git URL (25/25)")
        elif git_url_correct:
            # Job exists with correct Git URL but not detected as Pipeline type
            score += 18
            subscores['backend_pipeline_git'] = 'partial'
            feedback_parts.append(
                "alpha-backend-build: correct Git URL but not detected as Pipeline type (18/25)")
        elif is_pipeline:
            score += 12
            subscores['backend_pipeline_git'] = 'partial'
            feedback_parts.append(
                f"alpha-backend-build: is Pipeline but Git URL wrong or missing"
                f" (got '{git_url}') (12/25)")
        else:
            score += 5
            subscores['backend_pipeline_git'] = 'partial'
            feedback_parts.append(
                "alpha-backend-build: exists but not Pipeline and Git URL incorrect (5/25)")
    else:
        subscores['backend_pipeline_git'] = False
        feedback_parts.append("Job 'alpha-backend-build' not found (0/25)")

    # ── Criterion 2: alpha-backend-build H/15 SCM polling ─────
    if backend.get('has_h15_polling', False):
        score += 15
        subscores['backend_polling'] = True
        spec = backend.get('scm_poll_spec', '')
        feedback_parts.append(
            f"alpha-backend-build: H/15 SCM polling configured (spec='{spec}') (15/15)")
    elif backend.get('scm_poll_spec', ''):
        score += 8
        subscores['backend_polling'] = 'partial'
        spec = backend.get('scm_poll_spec', '')
        feedback_parts.append(
            f"alpha-backend-build: SCM polling present but not H/15 (spec='{spec}') (8/15)")
    else:
        subscores['backend_polling'] = False
        feedback_parts.append("alpha-backend-build: no SCM polling trigger (0/15)")

    # ── Criterion 3: alpha-frontend-build NODE_VERSION param ──
    if frontend.get('exists', False):
        choices = frontend.get('node_version_choices', [])
        choices_str = [str(c) for c in choices]
        required = ['16', '18', '20']
        has_all   = all(r in choices_str for r in required)
        order_ok  = choices_str == required if choices_str else False

        if has_all and order_ok:
            score += 25
            subscores['frontend_node_param'] = True
            feedback_parts.append(
                "alpha-frontend-build: NODE_VERSION choices 16/18/20 in correct order (25/25)")
        elif has_all:
            score += 18
            subscores['frontend_node_param'] = 'partial'
            feedback_parts.append(
                f"alpha-frontend-build: NODE_VERSION has all values but wrong order"
                f" (got {choices_str}) (18/25)")
        elif choices_str:
            present = [r for r in required if r in choices_str]
            partial = len(present) * 6
            score += partial
            subscores['frontend_node_param'] = 'partial'
            feedback_parts.append(
                f"alpha-frontend-build: NODE_VERSION partial — found {present}"
                f" of [16,18,20] (got {choices_str}) ({partial}/25)")
        else:
            subscores['frontend_node_param'] = False
            feedback_parts.append(
                "alpha-frontend-build: NODE_VERSION choice parameter not found (0/25)")
    else:
        subscores['frontend_node_param'] = False
        feedback_parts.append("Job 'alpha-frontend-build' not found (0/25)")

    # ── Criterion 4: alpha-frontend-build build discarder ─────
    if frontend.get('exists', False):
        keep = str(frontend.get('build_discarder_keep', '')).strip()
        if keep == '7':
            score += 15
            subscores['frontend_discarder'] = True
            feedback_parts.append(
                "alpha-frontend-build: build discarder keeps 7 builds (15/15)")
        elif keep and keep != '-1' and keep != '':
            score += 7
            subscores['frontend_discarder'] = 'partial'
            feedback_parts.append(
                f"alpha-frontend-build: build discarder present but keeps {keep}"
                f" builds (expected 7) (7/15)")
        else:
            subscores['frontend_discarder'] = False
            feedback_parts.append(
                "alpha-frontend-build: no build discarder configured (0/15)")
    else:
        subscores['frontend_discarder'] = False
        feedback_parts.append(
            "alpha-frontend-build does not exist; build discarder not checked (0/15)")

    # ── Criterion 5: npm-registry-token secret text ───────────
    if cred.get('exists', False):
        if cred.get('is_secret_text', False):
            score += 10
            subscores['npm_token_cred'] = True
            feedback_parts.append(
                "npm-registry-token: exists as secret text (10/10)")
        else:
            score += 5
            subscores['npm_token_cred'] = 'partial'
            ctype = cred.get('type', '?')
            feedback_parts.append(
                f"npm-registry-token: exists but wrong type (got '{ctype}') (5/10)")
    else:
        subscores['npm_token_cred'] = False
        feedback_parts.append("Credential 'npm-registry-token' not found (0/10)")

    # ── Criterion 6: Project-Alpha CI view ────────────────────
    if view.get('exists', False):
        has_backend  = view.get('has_backend_job', False)
        has_frontend = view.get('has_frontend_job', False)

        if has_backend and has_frontend:
            score += 10
            subscores['view_complete'] = True
            feedback_parts.append(
                "View 'Project-Alpha CI' contains both jobs (10/10)")
        elif has_backend or has_frontend:
            score += 5
            subscores['view_complete'] = 'partial'
            jobs_found = view.get('jobs_in_view', [])
            feedback_parts.append(
                f"View 'Project-Alpha CI' exists but missing one job"
                f" (found: {jobs_found}) (5/10)")
        else:
            score += 2
            subscores['view_complete'] = 'partial'
            feedback_parts.append(
                "View 'Project-Alpha CI' exists but contains neither target job (2/10)")
    else:
        subscores['view_complete'] = False
        feedback_parts.append("View 'Project-Alpha CI' not found (0/10)")

    score = min(score, 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores
    }
