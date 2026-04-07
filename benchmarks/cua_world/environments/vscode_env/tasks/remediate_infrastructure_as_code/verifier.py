#!/usr/bin/env python3
"""
Verifier for the remediate_infrastructure_as_code task.

Checks whether the agent identified and fixed 6 critical security
misconfigurations across Docker, Kubernetes, Terraform, and nginx files.

Each fix is worth 16-17 points (total 100).  Pass threshold: 60.
"""

import sys
import os
import json
import re
import hashlib
import logging
import tempfile
import shutil

sys.path.insert(
    0,
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../", "utils"),
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ──────────────────────────────────────────────────────────
# Helper utilities
# ──────────────────────────────────────────────────────────

def _safe_get(data, key):
    """Return file content from the result dict, or empty string."""
    val = data.get(key)
    return val if isinstance(val, str) else ""


def _md5(text):
    return hashlib.md5(text.encode("utf-8")).hexdigest()


# ──────────────────────────────────────────────────────────
# Individual misconfiguration checks
# ──────────────────────────────────────────────────────────

def check_non_root_container(dockerfile_src):
    """
    Bug 1 -- Dockerfile runs as root (17 pts)
    Original has no USER directive.
    Fix: add a non-root USER directive (e.g. USER appuser).
    """
    if not dockerfile_src:
        return False, "Dockerfile is missing or empty"

    # Look for a USER directive that is NOT 'root'
    user_directives = re.findall(r'^\s*USER\s+(\S+)', dockerfile_src, re.MULTILINE)

    if not user_directives:
        return False, "Dockerfile has no USER directive -- application runs as root"

    # Check if the last USER directive (the effective one) is non-root
    last_user = user_directives[-1].strip()
    if last_user.lower() == "root":
        return False, "Dockerfile USER is set to root"

    return True, f"Dockerfile correctly sets USER to '{last_user}'"


def check_no_hardcoded_secrets(compose_src):
    """
    Bug 2 -- docker-compose.yml has hardcoded secrets (17 pts)
    Original contains POSTGRES_PASSWORD: "SuperSecret123!" and
    SECRET_KEY=my-super-secret-key-12345.
    Fix: use ${...} env var references or Docker secrets.
    """
    if not compose_src:
        return False, "docker-compose.yml is missing or empty"

    has_password = "SuperSecret123!" in compose_src
    has_secret_key = "my-super-secret-key-12345" in compose_src

    if has_password and has_secret_key:
        return False, "docker-compose.yml still contains both hardcoded password and secret key"
    if has_password:
        return False, "docker-compose.yml still contains hardcoded password 'SuperSecret123!'"
    if has_secret_key:
        return False, "docker-compose.yml still contains hardcoded secret key"

    return True, "docker-compose.yml no longer contains hardcoded secrets"


def check_resource_limits(deployment_src):
    """
    Bug 3 -- deployment.yaml missing resource limits (17 pts)
    Original has no resources: section in the container spec.
    Fix: add resources with limits (memory and/or cpu).
    """
    if not deployment_src:
        return False, "deployment.yaml is missing or empty"

    has_resources = bool(re.search(r'resources\s*:', deployment_src))
    has_limits = bool(re.search(r'limits\s*:', deployment_src))
    has_memory_or_cpu = bool(
        re.search(r'memory\s*:', deployment_src) or
        re.search(r'cpu\s*:', deployment_src)
    )

    if has_resources and has_limits and has_memory_or_cpu:
        return True, "deployment.yaml has resource limits defined"

    if has_resources and has_limits:
        return True, "deployment.yaml has resources with limits section"

    if has_resources:
        return False, "deployment.yaml has resources: but missing limits:"

    return False, "deployment.yaml has no resource limits defined"


def check_health_probes(deployment_src):
    """
    Bug 4 -- deployment.yaml missing health probes (17 pts)
    Original has no readinessProbe or livenessProbe.
    Fix: add at least one (ideally both).
    """
    if not deployment_src:
        return False, "deployment.yaml is missing or empty"

    has_readiness = bool(re.search(r'readinessProbe\s*:', deployment_src))
    has_liveness = bool(re.search(r'livenessProbe\s*:', deployment_src))

    if has_readiness and has_liveness:
        return True, "deployment.yaml has both readinessProbe and livenessProbe"
    if has_readiness:
        return True, "deployment.yaml has readinessProbe"
    if has_liveness:
        return True, "deployment.yaml has livenessProbe"

    return False, "deployment.yaml has no readinessProbe or livenessProbe"


def check_restricted_security_group(terraform_src):
    """
    Bug 5 -- terraform main.tf has overly permissive security group (16 pts)
    Original allows 0.0.0.0/0 on ports 0-65535.
    Fix: restrict to specific ports and/or CIDR blocks.
    """
    if not terraform_src:
        return False, "main.tf is missing or empty"

    # Check if the combination of all-ports + all-CIDRs still exists
    # We look for an ingress block that has both 0-65535 range AND 0.0.0.0/0
    has_all_ports = bool(re.search(r'from_port\s*=\s*0', terraform_src)) and \
                    bool(re.search(r'to_port\s*=\s*65535', terraform_src))
    has_all_cidr = bool(re.search(r'cidr_blocks\s*=\s*\[\s*"0\.0\.0\.0/0"\s*\]', terraform_src))

    if has_all_ports and has_all_cidr:
        return False, "main.tf still allows all ports (0-65535) from 0.0.0.0/0"

    return True, "main.tf security group ingress has been restricted"


def check_security_headers(nginx_src):
    """
    Bug 6 -- nginx.conf missing security headers (16 pts)
    Original has no security headers.
    Fix: add at least 2 of: X-Frame-Options, X-Content-Type-Options,
         Content-Security-Policy, Strict-Transport-Security, X-XSS-Protection.
    """
    if not nginx_src:
        return False, "nginx.conf is missing or empty"

    security_headers = [
        "X-Frame-Options",
        "X-Content-Type-Options",
        "Content-Security-Policy",
        "Strict-Transport-Security",
        "X-XSS-Protection",
    ]

    found = [h for h in security_headers if h in nginx_src]

    if len(found) >= 2:
        return True, f"nginx.conf includes security headers: {', '.join(found)}"
    elif len(found) == 1:
        return False, f"nginx.conf has only 1 security header ({found[0]}); need at least 2"
    else:
        return False, "nginx.conf has no security headers"


# ──────────────────────────────────────────────────────────
# Anti-gaming: verify files were actually changed
# ──────────────────────────────────────────────────────────

def _files_were_modified(data, copy_from_env, temp_dir):
    """
    Compare current file contents against baseline hashes recorded
    during setup.  Returns True if at least one file was modified.
    """
    try:
        hashes_local = os.path.join(temp_dir, "initial_hashes.txt")
        copy_from_env("/tmp/infra_initial_hashes.txt", hashes_local)
        if not os.path.exists(hashes_local):
            return True  # can't verify, assume modified

        with open(hashes_local, "r") as fh:
            original_hashes = {}
            for line in fh:
                parts = line.strip().split()
                if len(parts) >= 2:
                    h, path = parts[0], parts[-1]
                    # Map the absolute path back to our result keys
                    for key in data:
                        if path.endswith(key) or path.endswith(key.replace("/", os.sep)):
                            original_hashes[key] = h

        # Check if any monitored file has a different hash now
        for key, orig_hash in original_hashes.items():
            content = data.get(key, "")
            if content and _md5(content) != orig_hash:
                return True

        return False
    except Exception as e:
        logger.warning(f"Could not verify file modification: {e}")
        return True  # fail open


# ──────────────────────────────────────────────────────────
# Main verifier entry point
# ──────────────────────────────────────────────────────────

def verify_infrastructure_remediation(traj, env_info, task_info):
    """
    Verify that the agent fixed the 6 infrastructure security misconfigurations.

    Returns
    -------
    dict
        {"passed": bool, "score": int, "feedback": str}
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    temp_dir = tempfile.mkdtemp(prefix="verify_infra_")

    try:
        # ── Retrieve exported result JSON ───────────────
        result_local = os.path.join(temp_dir, "infra_remediation_result.json")
        try:
            copy_from_env("/tmp/infra_remediation_result.json", result_local)
        except Exception as e:
            logger.error(f"Could not copy result file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not retrieve result file: {e}",
            }

        if not os.path.exists(result_local):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found after export",
            }

        with open(result_local, "r", encoding="utf-8") as fh:
            data = json.load(fh)

        # ── Extract file contents ───────────────────────
        dockerfile_src = _safe_get(data, "docker/Dockerfile")
        compose_src = _safe_get(data, "docker/docker-compose.yml")
        deployment_src = _safe_get(data, "kubernetes/deployment.yaml")
        terraform_src = _safe_get(data, "terraform/main.tf")
        nginx_src = _safe_get(data, "nginx/nginx.conf")

        # ── Anti-gaming check ───────────────────────────
        if not _files_were_modified(data, copy_from_env, temp_dir):
            return {
                "passed": False,
                "score": 0,
                "feedback": "No files appear to have been modified from the original.",
            }

        # ── Run the six checks ──────────────────────────
        checks = [
            ("Non-root container",         17, check_non_root_container(dockerfile_src)),
            ("No hardcoded secrets",        17, check_no_hardcoded_secrets(compose_src)),
            ("Resource limits",             17, check_resource_limits(deployment_src)),
            ("Health probes",               17, check_health_probes(deployment_src)),
            ("Restricted security group",   16, check_restricted_security_group(terraform_src)),
            ("Security headers",            16, check_security_headers(nginx_src)),
        ]

        score = 0
        feedback_lines = []

        for label, points, (ok, msg) in checks:
            if ok:
                score += points
                feedback_lines.append(f"PASS [{points}pts] {label}: {msg}")
            else:
                feedback_lines.append(f"FAIL [ 0pts] {label}: {msg}")

        passed = score >= 60
        feedback_lines.insert(
            0,
            f"{'PASSED' if passed else 'FAILED'}: {score}/100 "
            f"(threshold 60, {sum(1 for _, _, (ok, _) in checks if ok)}/6 issues fixed)",
        )

        logger.info(f"Score: {score}/100, passed={passed}")
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback_lines),
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
        }

    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
