#!/usr/bin/env python3
"""
Verifier for cluster_rbac_audit_and_remediation task.

Scoring (100 points total):
- C1 (25 pts): No ClusterRoleBinding binds ci-runner (dev-team) to 'edit' ClusterRole
- C2 (25 pts): qa-tester Role in qa-team has no wildcard verbs (*) on pods resource
- C3 (25 pts): No ClusterRoleBinding binds ops-agent (platform-ops) to cluster-admin
- C4 (25 pts): dev-team namespace has label pod-security.kubernetes.io/enforce=restricted

Pass threshold: 70 (any 3 of 4 criteria)

Anti-gaming analysis:
  Do-nothing: C1=0 (CRB present), C2=0 (wildcard present), C3=0 (cluster-admin CRB present),
              C4=0 (label missing) → score=0
  Delete all CRBs: C1=25, C3=25 but C2=0 (role unchanged), C4=0 (label missing) → score=50, No
  Delete all namespaces: all checks return error/defaults → score=0
  Wrong namespace: rejected with score=0

Strategy enumeration:
  | Strategy          | C1 | C2 | C3 | C4 | Score | Pass? |
  | Do-nothing        |  0 |  0 |  0 |  0 |     0 | No    |
  | Fix C1 only       | 25 |  0 |  0 |  0 |    25 | No    |
  | Fix C1+C3         | 25 |  0 | 25 |  0 |    50 | No    |
  | Fix any 3         | 25 | 25 | 25 |  0 |    75 | Yes   |
  | Fix all 4         | 25 | 25 | 25 | 25 |   100 | Yes   |
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/cluster_rbac_audit_and_remediation_result.json"
PASS_THRESHOLD = 70


def verify_cluster_rbac_audit_and_remediation(traj, env_info, task_info):
    """
    Verify that RBAC violations have been remediated across dev-team, qa-team, platform-ops.

    Scoring:
      C1: ci-runner ClusterRoleBinding to 'edit' removed                25 pts
      C2: qa-tester Role no longer has wildcard verbs on pods            25 pts
      C3: ops-agent ClusterRoleBinding to cluster-admin removed          25 pts
      C4: dev-team namespace has pod-security.kubernetes.io/enforce=restricted  25 pts
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

    # Wrong-target guard — must reference the expected namespaces
    ns_list = result.get("namespaces", [])
    if "dev-team" not in ns_list or "qa-team" not in ns_list or "platform-ops" not in ns_list:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Wrong target — namespaces must include dev-team, qa-team, platform-ops (got: {ns_list})",
        }

    score = 0
    feedback_parts = []

    # ── Criterion 1: ci-runner edit CRB must be removed ──────────────────────
    fa = result.get("finding_a", {})
    crb_status = str(fa.get("ci_runner_edit_crb_status", "present")).strip()

    if crb_status == "removed":
        score += 25
        feedback_parts.append(
            "C1 PASS: ClusterRoleBinding granting 'edit' to ci-runner (dev-team) removed (+25)"
        )
    elif crb_status.startswith("error"):
        feedback_parts.append(
            f"C1 FAIL: Could not check ci-runner CRB status (error: {crb_status})"
        )
    else:
        feedback_parts.append(
            "C1 FAIL: ClusterRoleBinding still grants 'edit' ClusterRole to ci-runner "
            "across ALL namespaces — remove CRB and create namespace-scoped RoleBinding instead"
        )

    # ── Criterion 2: qa-tester Role must not have wildcard verbs on pods ──────
    fb = result.get("finding_b", {})
    role_exists = int(fb.get("qa_tester_role_exists", 0))
    wildcard_status = str(fb.get("wildcard_status", "wildcard-present")).strip()

    if role_exists >= 1 and wildcard_status == "wildcard-removed":
        score += 25
        feedback_parts.append(
            "C2 PASS: qa-tester Role no longer has wildcard verbs on pods resource (+25)"
        )
    elif role_exists < 1:
        # Role was deleted entirely — we require it to exist but without wildcards
        feedback_parts.append(
            "C2 FAIL: qa-tester Role was deleted — it must exist but with restricted verbs, "
            "not be removed entirely (QA team still needs pod read access)"
        )
    else:
        feedback_parts.append(
            "C2 FAIL: qa-tester Role still has wildcard ('*') verbs on pods — "
            "replace '*' with specific verbs like ['get', 'list', 'watch']"
        )

    # ── Criterion 3: ops-agent cluster-admin CRB must be removed ─────────────
    fc = result.get("finding_c", {})
    admin_crb_status = str(fc.get("ops_agent_admin_crb_status", "present")).strip()

    if admin_crb_status == "removed":
        score += 25
        feedback_parts.append(
            "C3 PASS: ClusterRoleBinding granting cluster-admin to ops-agent (platform-ops) removed (+25)"
        )
    elif admin_crb_status.startswith("error"):
        feedback_parts.append(
            f"C3 FAIL: Could not check ops-agent CRB status (error: {admin_crb_status})"
        )
    else:
        feedback_parts.append(
            "C3 FAIL: ClusterRoleBinding still grants cluster-admin to ops-agent — "
            "this is a CRITICAL security finding, must be removed immediately"
        )

    # ── Criterion 4: dev-team must have pod-security label ────────────────────
    fd = result.get("finding_d", {})
    pod_sec_enforce = str(fd.get("dev_team_pod_security_enforce", "")).strip().lower()

    if pod_sec_enforce == "restricted":
        score += 25
        feedback_parts.append(
            "C4 PASS: dev-team namespace has label "
            "pod-security.kubernetes.io/enforce=restricted (+25)"
        )
    else:
        feedback_parts.append(
            f"C4 FAIL: dev-team namespace pod-security.kubernetes.io/enforce='{pod_sec_enforce}' — "
            f"must be 'restricted' (run: kubectl label namespace dev-team "
            f"pod-security.kubernetes.io/enforce=restricted)"
        )

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
