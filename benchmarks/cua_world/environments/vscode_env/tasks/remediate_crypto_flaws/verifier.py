#!/usr/bin/env python3
"""
Verifier for Remediate Cryptographic Flaws task.
Combines programmatic AST parsing, dynamic module evaluation, and VLM trajectory analysis.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_crypto_remediation(traj, env_info, task_info):
    """
    Verify the remediation of 5 crypto flaws using the container's exported report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/crypto_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve evaluation report: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get("error"):
        logger.error(f"Container Evaluation Error: {result['error']}")
        return {"passed": False, "score": 0, "feedback": "Code contains fatal syntax or runtime errors preventing evaluation."}

    score = 0
    feedback = []
    ast_checks = result.get("ast_checks", {})
    dyn_checks = result.get("dynamic_checks", {})

    # Criterion 1: Key Derivation (MD5 -> PBKDF2) [15 points]
    if ast_checks.get("uses_pbkdf2") and not ast_checks.get("uses_md5"):
        score += 15
        feedback.append("[+] Key Derivation fixed (MD5 removed, PBKDF2 applied)")
    else:
        feedback.append("[-] Key Derivation failed (MD5 still present or PBKDF2 missing)")

    # Criterion 2: Cipher Mode (CBC -> GCM) [20 points]
    if ast_checks.get("uses_gcm") and not ast_checks.get("uses_cbc_or_ecb"):
        score += 20
        feedback.append("[+] Cipher Mode fixed (CBC removed, GCM applied)")
    else:
        feedback.append("[-] Cipher Mode failed (CBC/ECB still present or GCM missing)")

    # Criterion 3: Random Nonce / IV [20 points]
    if dyn_checks.get("nonce_is_random"):
        score += 20
        feedback.append("[+] Static IV fixed (Encryption output is dynamically randomized)")
    else:
        encrypt_err = dyn_checks.get("encrypt_error", "Outputs are identical.")
        feedback.append(f"[-] Static IV failed (Not randomized or broken implementation: {encrypt_err})")

    # Criterion 4: Secure PRNG (random -> secrets) [15 points]
    if ast_checks.get("uses_secrets_choice") and not ast_checks.get("uses_random_choice"):
        score += 15
        feedback.append("[+] API Key PRNG fixed (secrets.choice used)")
    else:
        feedback.append("[-] API Key PRNG failed (random.choice still used or secrets not used)")

    # Criterion 5: Timing Attack (== -> compare_digest) [15 points]
    if ast_checks.get("uses_compare_digest") and not ast_checks.get("uses_eq"):
        score += 15
        feedback.append("[+] Timing attack vulnerability fixed (compare_digest used)")
    else:
        feedback.append("[-] Timing attack vulnerability failed (== still used or compare_digest missing)")

    # Criterion 6: Functional Pytest Passes [10 points]
    pytest_passed = result.get("pytest_passed", False)
    if pytest_passed:
        score += 10
        feedback.append("[+] Functional test suite passed")
    else:
        feedback.append("[-] Functional test suite failed (Encryption/decryption is broken)")

    # Criterion 7: Git Commit [5 points]
    expected_msg = task_info.get("metadata", {}).get("expected_git_msg", "Fix cryptographic vulnerabilities")
    if expected_msg.lower() in result.get("git_commit", "").lower():
        score += 5
        feedback.append("[+] Code properly committed to Git")
    else:
        feedback.append("[-] Missing or incorrect Git commit")

    # Anti-gaming: Ensure file was actually modified
    if not result.get("file_modified", False):
        score = 0
        feedback.append("[-] CRITICAL: secure_vault.py was not modified during the task window.")

    # Determine Pass/Fail
    # Agent must achieve >= 70 points AND must not break the functional test suite.
    passed = (score >= 70) and pytest_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback),
        "details": result
    }