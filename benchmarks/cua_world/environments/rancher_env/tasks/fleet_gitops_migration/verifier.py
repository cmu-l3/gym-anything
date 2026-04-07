#!/usr/bin/env python3
"""
Verifier for fleet_gitops_migration task.

Scoring (100 points total):
- C1 (20 pts): Legacy cleanup (`legacy-frontend` deployment and service deleted)
- C2 (30 pts): `GitRepo` named `guestbook-gitops` exists in `fleet-local` namespace
- C3 (20 pts): `GitRepo` points to correct URL, branch, and path
- C4 (15 pts): `GitRepo` targetNamespace is correctly set to `webapp-prod`
- C5 (15 pts): `frontend` deployment exists in `webapp-prod`, is Running, AND has Fleet tracking labels (Anti-gaming check)

Pass threshold: 70 points WITH C2 and C5 met.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/fleet_gitops_migration_result.json"
PASS_THRESHOLD = 70


def normalize_url(url):
    """Normalize github repository URLs for flexible comparison."""
    if not url:
        return ""
    url = url.strip().lower()
    if url.endswith(".git"):
        url = url[:-4]
    if url.endswith("/"):
        url = url[:-1]
    return url


def normalize_path(path):
    """Normalize paths inside the repo."""
    if not path:
        return ""
    path = path.strip()
    if path.startswith("./"):
        path = path[2:]
    if path.startswith("/"):
        path = path[1:]
    if path.endswith("/"):
        path = path[:-1]
    return path


def verify_fleet_gitops_migration(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may not have run",
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    
    # ── Criterion 1: Legacy Cleanup ──────────────────────────────────────────
    legacy_cleanup = result.get("legacy_cleanup", False)
    if legacy_cleanup:
        score += 20
        feedback_parts.append("C1 PASS: Legacy frontend deployment and service removed (+20)")
    else:
        feedback_parts.append("C1 FAIL: Legacy frontend resources were not fully deleted from webapp-prod")

    # ── Criterion 2: GitRepo Exists ──────────────────────────────────────────
    gitrepo = result.get("gitrepo")
    c2_pass = gitrepo is not None
    
    if c2_pass:
        score += 30
        feedback_parts.append("C2 PASS: GitRepo 'guestbook-gitops' exists in 'fleet-local' (+30)")
    else:
        feedback_parts.append("C2 FAIL: GitRepo 'guestbook-gitops' not found in 'fleet-local' namespace")

    # ── Criterion 3 & 4: GitRepo Config ──────────────────────────────────────
    c3_pass = False
    c4_pass = False
    
    if c2_pass:
        spec = gitrepo.get("spec", {})
        
        # C3 Check: URL, Branch, Paths
        repo_url = normalize_url(spec.get("repo", ""))
        expected_url = "https://github.com/rancher/fleet-examples"
        
        branch = spec.get("branch", "master") # Fleet UI sometimes omits this if default
        paths = [normalize_path(p) for p in spec.get("paths", [])]
        
        url_match = (repo_url == expected_url)
        branch_match = (branch in ["master", "main", ""])
        path_match = ("simple" in paths)
        
        if url_match and branch_match and path_match:
            c3_pass = True
            score += 20
            feedback_parts.append("C3 PASS: GitRepo URL, branch, and path configured correctly (+20)")
        else:
            reasons = []
            if not url_match: reasons.append(f"url '{repo_url}' != '{expected_url}'")
            if not branch_match: reasons.append(f"branch '{branch}' != 'master'")
            if not path_match: reasons.append(f"paths {paths} missing 'simple'")
            feedback_parts.append(f"C3 FAIL: GitRepo config mismatch: {', '.join(reasons)}")

        # C4 Check: Target Namespace
        target_ns = spec.get("targetNamespace", "")
        if not target_ns:
            # Check targets array as fallback
            targets = spec.get("targets", [])
            if targets:
                target_ns = targets[0].get("namespace", "")
                
        if target_ns == "webapp-prod":
            c4_pass = True
            score += 15
            feedback_parts.append("C4 PASS: GitRepo targetNamespace set to 'webapp-prod' (+15)")
        else:
            feedback_parts.append(f"C4 FAIL: Target namespace is '{target_ns}' instead of 'webapp-prod'")

    # ── Criterion 5: Fleet Managed Workload (Anti-gaming) ────────────────────
    new_deploy = result.get("new_deploy")
    c5_pass = False
    
    if new_deploy:
        ready_replicas = new_deploy.get("status", {}).get("readyReplicas", 0)
        labels = new_deploy.get("metadata", {}).get("labels", {})
        annotations = new_deploy.get("metadata", {}).get("annotations", {})
        
        # Check if the deployment is actually managed by Fleet
        has_fleet_metadata = any(k.startswith("fleet.cattle.io/") for k in labels.keys()) or \
                             any(k.startswith("fleet.cattle.io/") for k in annotations.keys())
        
        if ready_replicas >= 1 and has_fleet_metadata:
            c5_pass = True
            score += 15
            feedback_parts.append(f"C5 PASS: 'frontend' deployment is Running ({ready_replicas} ready) and managed by Fleet (+15)")
        elif ready_replicas >= 1:
            feedback_parts.append("C5 FAIL: 'frontend' deployment is Running but missing Fleet tracking labels (deployed manually?)")
        else:
            feedback_parts.append("C5 FAIL: 'frontend' deployment exists but has 0 ready replicas (Fleet sync incomplete?)")
    else:
        feedback_parts.append("C5 FAIL: 'frontend' deployment not found in 'webapp-prod' namespace")

    # ── Final Determination ──────────────────────────────────────────────────
    passed = (score >= PASS_THRESHOLD) and c2_pass and c5_pass
    
    # Override logic if score is high but critical criteria fail
    if score >= PASS_THRESHOLD and not (c2_pass and c5_pass):
        feedback_parts.append("CRITICAL FAIL: Passed point threshold, but critical requirements (GitRepo created & Fleet workload running) not met.")
        passed = False

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }