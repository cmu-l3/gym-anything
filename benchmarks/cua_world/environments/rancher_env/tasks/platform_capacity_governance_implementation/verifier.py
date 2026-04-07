#!/usr/bin/env python3
"""
Verifier for platform_capacity_governance_implementation task.

Scoring (100 points total):
- C1 (25 pts): ResourceQuota 'payments-quota' with limits.cpu=8, limits.memory=16Gi, pods=20, services=10
- C2 (25 pts): LimitRange 'payments-limits' with Container default CPU=500m, default memory=512Mi
- C3 (25 pts): HPA 'transaction-processor-hpa' targeting transaction-processor, min=2, max=10, CPU=70%
- C4 (25 pts): PodDisruptionBudget 'payment-gateway-pdb' with minAvailable=1

Pass threshold: 70 (any 3 of 4 criteria)

Anti-gaming analysis:
  Do-nothing: C1=0 (no quota), C2=0 (no limitrange), C3=0 (no HPA), C4=0 (no PDB) → score=0
  Wrong namespace: rejected with score=0
  Create with wrong names: name check is part of criterion → score=0

Strategy enumeration:
  | Strategy          | C1 | C2 | C3 | C4 | Score | Pass? |
  | Do-nothing        |  0 |  0 |  0 |  0 |     0 | No    |
  | Create C1 only    | 25 |  0 |  0 |  0 |    25 | No    |
  | Create C1+C2      | 25 | 25 |  0 |  0 |    50 | No    |
  | Create any 3      | 25 | 25 | 25 |  0 |    75 | Yes   |
  | Create all 4      | 25 | 25 | 25 | 25 |   100 | Yes   |
"""

import json
import tempfile
import os
import logging
import re

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/platform_capacity_governance_implementation_result.json"
PASS_THRESHOLD = 70


def _normalize_cpu(val: str) -> float:
    """Convert CPU string like '8', '500m', '2' to millicores float."""
    val = str(val).strip()
    if val.endswith("m"):
        return float(val[:-1])
    try:
        return float(val) * 1000
    except ValueError:
        return -1.0


def _normalize_mem(val: str) -> float:
    """Convert memory string to MiB float."""
    val = str(val).strip()
    if val.endswith("Gi"):
        return float(val[:-2]) * 1024
    if val.endswith("Mi"):
        return float(val[:-2])
    if val.endswith("G"):
        return float(val[:-1]) * 1024
    if val.endswith("M"):
        return float(val[:-1])
    try:
        return float(val) / (1024 * 1024)
    except ValueError:
        return -1.0


def verify_platform_capacity_governance_implementation(traj, env_info, task_info):
    """
    Verify that capacity governance controls have been implemented in payments-prod namespace.

    Scoring:
      C1: ResourceQuota 'payments-quota' with correct limits        25 pts
      C2: LimitRange 'payments-limits' with correct defaults        25 pts
      C3: HPA 'transaction-processor-hpa' with correct config       25 pts
      C4: PDB 'payment-gateway-pdb' with minAvailable=1             25 pts
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
    if result.get("namespace") != "payments-prod":
        return {
            "passed": False,
            "score": 0,
            "feedback": "Wrong namespace — must target 'payments-prod'",
        }

    score = 0
    feedback_parts = []

    # ── Criterion 1: ResourceQuota ────────────────────────────────────────────
    rq = result.get("resource_quota", {})
    rq_exists = int(rq.get("exists", 0))
    rq_cpu = str(rq.get("cpu_limit", "")).strip()
    rq_mem = str(rq.get("memory_limit", "")).strip()
    rq_pods = str(rq.get("pods", "")).strip()
    rq_svcs = str(rq.get("services", "")).strip()

    # cpu limit must be >= 8 cores (8000m)
    cpu_mc = _normalize_cpu(rq_cpu)
    cpu_ok = cpu_mc >= 7900  # 8 cores = 8000m, allow 100m tolerance
    # memory limit must be >= 16Gi
    mem_mib = _normalize_mem(rq_mem)
    mem_ok = mem_mib >= 16383  # 16Gi = 16384 MiB, allow 1 MiB tolerance
    # pods must be 20
    try:
        pods_ok = int(rq_pods) == 20
    except (ValueError, TypeError):
        pods_ok = False
    # services must be 10
    try:
        svcs_ok = int(rq_svcs) == 10
    except (ValueError, TypeError):
        svcs_ok = False

    if rq_exists >= 1 and cpu_ok and mem_ok and pods_ok and svcs_ok:
        score += 25
        feedback_parts.append(
            f"C1 PASS: ResourceQuota 'payments-quota' — cpu={rq_cpu}, mem={rq_mem}, "
            f"pods={rq_pods}, services={rq_svcs} (+25)"
        )
    else:
        issues = []
        if rq_exists < 1:
            issues.append("ResourceQuota 'payments-quota' not found")
        if not cpu_ok:
            issues.append(f"limits.cpu='{rq_cpu}' (must be 8)")
        if not mem_ok:
            issues.append(f"limits.memory='{rq_mem}' (must be 16Gi)")
        if not pods_ok:
            issues.append(f"pods='{rq_pods}' (must be 20)")
        if not svcs_ok:
            issues.append(f"services='{rq_svcs}' (must be 10)")
        feedback_parts.append(f"C1 FAIL: ResourceQuota — {'; '.join(issues)}")

    # ── Criterion 2: LimitRange ───────────────────────────────────────────────
    lr = result.get("limit_range", {})
    lr_exists = int(lr.get("exists", 0))
    lr_cpu = str(lr.get("default_cpu", "")).strip()
    lr_mem = str(lr.get("default_memory", "")).strip()

    # default CPU must be 500m (±50m tolerance)
    lr_cpu_mc = _normalize_cpu(lr_cpu)
    lr_cpu_ok = 450 <= lr_cpu_mc <= 550
    # default memory must be 512Mi (±64Mi tolerance)
    lr_mem_mib = _normalize_mem(lr_mem)
    lr_mem_ok = 448 <= lr_mem_mib <= 576

    if lr_exists >= 1 and lr_cpu_ok and lr_mem_ok:
        score += 25
        feedback_parts.append(
            f"C2 PASS: LimitRange 'payments-limits' — default cpu={lr_cpu}, "
            f"default memory={lr_mem} (+25)"
        )
    else:
        issues = []
        if lr_exists < 1:
            issues.append("LimitRange 'payments-limits' not found")
        if not lr_cpu_ok:
            issues.append(f"default cpu='{lr_cpu}' (must be 500m)")
        if not lr_mem_ok:
            issues.append(f"default memory='{lr_mem}' (must be 512Mi)")
        feedback_parts.append(f"C2 FAIL: LimitRange — {'; '.join(issues)}")

    # ── Criterion 3: HPA ─────────────────────────────────────────────────────
    hpa = result.get("hpa", {})
    hpa_exists = int(hpa.get("exists", 0))
    hpa_min = int(hpa.get("min_replicas", 0))
    hpa_max = int(hpa.get("max_replicas", 0))
    hpa_cpu = str(hpa.get("cpu_target", "")).strip()
    hpa_target = str(hpa.get("target_ref", "")).strip()

    hpa_min_ok = hpa_min == 2
    hpa_max_ok = hpa_max == 10
    try:
        hpa_cpu_val = float(hpa_cpu)
        hpa_cpu_ok = 65 <= hpa_cpu_val <= 75  # 70% ± 5% tolerance
    except (ValueError, TypeError):
        hpa_cpu_ok = False
    hpa_target_ok = hpa_target == "transaction-processor"

    if hpa_exists >= 1 and hpa_min_ok and hpa_max_ok and hpa_cpu_ok and hpa_target_ok:
        score += 25
        feedback_parts.append(
            f"C3 PASS: HPA 'transaction-processor-hpa' — target={hpa_target}, "
            f"min={hpa_min}, max={hpa_max}, cpu={hpa_cpu}% (+25)"
        )
    else:
        issues = []
        if hpa_exists < 1:
            issues.append("HPA 'transaction-processor-hpa' not found")
        if not hpa_target_ok:
            issues.append(f"scaleTargetRef='{hpa_target}' (must be 'transaction-processor')")
        if not hpa_min_ok:
            issues.append(f"minReplicas={hpa_min} (must be 2)")
        if not hpa_max_ok:
            issues.append(f"maxReplicas={hpa_max} (must be 10)")
        if not hpa_cpu_ok:
            issues.append(f"CPU target='{hpa_cpu}' (must be 70)")
        feedback_parts.append(f"C3 FAIL: HPA — {'; '.join(issues)}")

    # ── Criterion 4: PodDisruptionBudget ─────────────────────────────────────
    pdb = result.get("pdb", {})
    pdb_exists = int(pdb.get("exists", 0))
    pdb_min = str(pdb.get("min_available", "")).strip()

    try:
        pdb_min_ok = int(pdb_min) >= 1
    except (ValueError, TypeError):
        pdb_min_ok = False

    if pdb_exists >= 1 and pdb_min_ok:
        score += 25
        feedback_parts.append(
            f"C4 PASS: PDB 'payment-gateway-pdb' — minAvailable={pdb_min} (+25)"
        )
    else:
        issues = []
        if pdb_exists < 1:
            issues.append("PodDisruptionBudget 'payment-gateway-pdb' not found")
        if not pdb_min_ok:
            issues.append(f"minAvailable='{pdb_min}' (must be >= 1)")
        feedback_parts.append(f"C4 FAIL: PDB — {'; '.join(issues)}")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
