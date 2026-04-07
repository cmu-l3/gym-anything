#!/usr/bin/env python3
"""
Verifier for supply_chain_security_remediation task.

Scoring (100 points total):
- C1 (25 pts): registry-proxy — privileged removed AND seccompProfile=RuntimeDefault AND resource limits set
- C2 (25 pts): artifact-scanner — docker.sock hostPath removed AND runAsNonRoot=true (user != 0)
- C3 (25 pts): build-agent — SYS_ADMIN capability removed from capabilities.add
- C4 (25 pts): deploy-controller — no ClusterRoleBinding to cluster-admin for its ServiceAccount

Pass threshold: 70 (any 3 of 4 criteria)

Anti-gaming analysis:
  Do-nothing: C1=0 (privileged=true, no seccomp, no limits), C2=0 (has docker.sock, runs as root),
              C3=0 (SYS_ADMIN present), C4=0 (cluster-admin CRB exists) → score=0
  Mass-delete all deployments: C1=0 (deployment gone, cannot check), C2=0, C3=0, C4=25 (CRB may remain)
  Max partial total: 0 per criterion (binary scoring) → cannot game partial credits
  Wrong namespace: rejected with score=0

Strategy enumeration:
  | Strategy          | C1 | C2 | C3 | C4 | Score | Pass? |
  | Do-nothing        |  0 |  0 |  0 |  0 |     0 | No    |
  | Delete namespace  |  0 |  0 |  0 |  0 |     0 | No    |
  | Fix C1 only       | 25 |  0 |  0 |  0 |    25 | No    |
  | Fix C1+C2         | 25 | 25 |  0 |  0 |    50 | No    |
  | Fix any 3         | 25 | 25 | 25 |  0 |    75 | Yes   |
  | Fix all 4         | 25 | 25 | 25 | 25 |   100 | Yes   |
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/supply_chain_security_remediation_result.json"
PASS_THRESHOLD = 70


def verify_supply_chain_security_remediation(traj, env_info, task_info):
    """
    Verify that security audit findings have been remediated in the supply-chain namespace.

    Scoring:
      C1: registry-proxy privileged removed + seccomp set + limits set  25 pts
      C2: artifact-scanner docker.sock removed + runAsNonRoot           25 pts
      C3: build-agent SYS_ADMIN capability removed                      25 pts
      C4: deploy-controller no cluster-admin ClusterRoleBinding         25 pts
    Pass: >= 70
    """
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
            "feedback": "Result file not found — export script did not run",
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    # Wrong-target guard
    if result.get("namespace") != "supply-chain":
        return {
            "passed": False,
            "score": 0,
            "feedback": "Wrong namespace — must target 'supply-chain'",
        }

    score = 0
    feedback_parts = []

    # ── Criterion 1: registry-proxy ───────────────────────────────────────────
    reg = result.get("registry_proxy", {})
    reg_privileged = str(reg.get("privileged", "true")).lower()
    reg_seccomp = str(reg.get("seccomp_profile", "")).strip()
    reg_cpu_limit = str(reg.get("cpu_limit", "")).strip()
    reg_mem_limit = str(reg.get("mem_limit", "")).strip()

    # privileged must NOT be "true"
    priv_fixed = reg_privileged not in ("true",)
    # seccomp must be RuntimeDefault or Localhost
    seccomp_fixed = reg_seccomp in ("RuntimeDefault", "Localhost")
    # resource limits must be present
    limits_fixed = bool(reg_cpu_limit) and bool(reg_mem_limit)

    if priv_fixed and seccomp_fixed and limits_fixed:
        score += 25
        feedback_parts.append(
            f"C1 PASS: registry-proxy — privileged removed, seccomp={reg_seccomp}, limits set (+25)"
        )
    else:
        issues = []
        if not priv_fixed:
            issues.append(f"privileged={reg_privileged} (must not be true)")
        if not seccomp_fixed:
            issues.append(f"seccompProfile='{reg_seccomp}' (must be RuntimeDefault)")
        if not limits_fixed:
            issues.append("no resource limits set")
        feedback_parts.append(f"C1 FAIL: registry-proxy — {'; '.join(issues)}")

    # ── Criterion 2: artifact-scanner ─────────────────────────────────────────
    scanner = result.get("artifact_scanner", {})
    has_docker_sock = bool(scanner.get("has_docker_sock_mount", True))
    run_as_non_root = str(scanner.get("run_as_non_root", "null")).lower()
    run_as_user = int(scanner.get("run_as_user", 0))

    # docker.sock must be gone
    sock_fixed = not has_docker_sock
    # runAsNonRoot=true OR runAsUser != 0 (non-root UID)
    nonroot_fixed = (run_as_non_root == "true") or (run_as_user != 0 and run_as_user > 0)

    if sock_fixed and nonroot_fixed:
        score += 25
        feedback_parts.append(
            f"C2 PASS: artifact-scanner — docker.sock removed, runAsNonRoot enforced (+25)"
        )
    else:
        issues = []
        if not sock_fixed:
            issues.append("docker.sock hostPath mount still present (escape vector)")
        if not nonroot_fixed:
            issues.append(f"running as root (runAsNonRoot={run_as_non_root}, uid={run_as_user})")
        feedback_parts.append(f"C2 FAIL: artifact-scanner — {'; '.join(issues)}")

    # ── Criterion 3: build-agent — SYS_ADMIN removed ──────────────────────────
    build = result.get("build_agent", {})
    has_sys_admin = bool(build.get("has_sys_admin", True))

    if not has_sys_admin:
        score += 25
        feedback_parts.append(
            "C3 PASS: build-agent — SYS_ADMIN capability removed from capabilities.add (+25)"
        )
    else:
        caps = build.get("capabilities_add", "")
        feedback_parts.append(
            f"C3 FAIL: build-agent — SYS_ADMIN still present in capabilities.add: {caps}"
        )

    # ── Criterion 4: deploy-controller — no cluster-admin binding ─────────────
    ctrl = result.get("deploy_controller", {})
    orig_crb = str(ctrl.get("original_crb_role", "not-found")).strip()
    any_admin = str(ctrl.get("any_cluster_admin_binding", "none")).strip()

    # Either the original CRB is gone (not-found) OR no CRB maps SA to cluster-admin
    crb_fixed = (orig_crb in ("not-found", "")) or (any_admin in ("none", ""))

    if crb_fixed:
        score += 25
        feedback_parts.append(
            "C4 PASS: deploy-controller — cluster-admin ClusterRoleBinding removed (+25)"
        )
    else:
        feedback_parts.append(
            f"C4 FAIL: deploy-controller-sa still bound to cluster-admin "
            f"(original CRB role='{orig_crb}', any binding='{any_admin}')"
        )

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
