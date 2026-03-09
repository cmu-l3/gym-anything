#!/usr/bin/env python3
"""
Verifier for implement_encrypted_shared_preferences task.

Requirements:
1. 'androidx.security:security-crypto' dependency added to build.gradle.kts.
2. TokenManager.kt uses EncryptedSharedPreferences.
3. MasterKey is created/used.
4. Correct filename "secure_app_prefs" used.
5. Correct encryption schemes (AES256_SIV, AES256_GCM) used.
6. Tests pass.
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _read_json_from_env(copy_from_env, container_path: str) -> dict:
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception as exc:
        logger.debug("Could not read JSON %s: %s", container_path, exc)
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

def verify_encrypted_shared_preferences(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from export_result.sh
    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    
    tm_content = result.get("token_manager_content", "")
    bg_content = result.get("build_gradle_content", "")
    test_success = result.get("test_success", False)
    file_modified = result.get("file_modified_during_task", False)

    score = 0
    feedback_parts = []
    
    # ----------------------------------------------------------------
    # Criterion 1: Dependency Added (20 pts)
    # ----------------------------------------------------------------
    # Look for implementation("androidx.security:security-crypto:...")
    # or implementation 'androidx.security:security-crypto:...'
    dep_regex = r"implementation\s*\(?['\"]androidx\.security:security-crypto:.*?['\"]\)?(?!\s*apply\s+false)"
    if re.search(dep_regex, bg_content):
        score += 20
        feedback_parts.append("Dependency added (20/20)")
    else:
        feedback_parts.append("Missing 'security-crypto' dependency (0/20)")

    # ----------------------------------------------------------------
    # Criterion 2: MasterKey Created (20 pts)
    # ----------------------------------------------------------------
    # Look for MasterKey.Builder(context) or similar
    if "MasterKey.Builder" in tm_content or "MasterKey(" in tm_content:
        score += 20
        feedback_parts.append("MasterKey usage detected (20/20)")
    else:
        feedback_parts.append("MasterKey initialization not found (0/20)")

    # ----------------------------------------------------------------
    # Criterion 3: EncryptedSharedPreferences Implementation (30 pts)
    # ----------------------------------------------------------------
    # Look for EncryptedSharedPreferences.create(...)
    if "EncryptedSharedPreferences.create" in tm_content:
        score += 30
        feedback_parts.append("EncryptedSharedPreferences used (30/30)")
    else:
        feedback_parts.append("EncryptedSharedPreferences.create not found (0/30)")

    # ----------------------------------------------------------------
    # Criterion 4: Encryption Schemes (10 pts)
    # ----------------------------------------------------------------
    # Check for AES256_SIV and AES256_GCM
    has_siv = "AES256_SIV" in tm_content
    has_gcm = "AES256_GCM" in tm_content
    
    if has_siv and has_gcm:
        score += 10
        feedback_parts.append("Correct encryption schemes used (10/10)")
    elif has_siv or has_gcm:
        score += 5
        feedback_parts.append("One correct encryption scheme found (5/10)")
    else:
        feedback_parts.append("Missing required encryption schemes (0/10)")

    # ----------------------------------------------------------------
    # Criterion 5: Correct Filename (10 pts)
    # ----------------------------------------------------------------
    if '"secure_app_prefs"' in tm_content:
        score += 10
        feedback_parts.append("Correct filename used (10/10)")
    else:
        feedback_parts.append("Filename 'secure_app_prefs' not found (0/10)")

    # ----------------------------------------------------------------
    # Criterion 6: Tests Pass (10 pts)
    # ----------------------------------------------------------------
    if test_success:
        score += 10
        feedback_parts.append("Tests passed (10/10)")
    else:
        feedback_parts.append("Tests failed or did not run (0/10)")

    # Anti-gaming check
    if not file_modified:
        feedback_parts.append("WARNING: TokenManager.kt was not modified during task.")
        score = 0
    
    # Calculate pass status
    passed = score >= 70 and "EncryptedSharedPreferences.create" in tm_content and "androidx.security:security-crypto" in bg_content

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }