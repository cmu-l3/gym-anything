#!/usr/bin/env python3
"""
Verifier for fix_security_vulns task.
Analyzes Java source code for security fixes and verifies compilation.
"""

import json
import logging
import re
import tempfile
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_security_vulns(traj, env_info, task_info):
    """
    Verify that 6 security vulnerabilities have been fixed correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    files = result.get("files", {})
    compilation_success = result.get("compilation_success", False)
    
    score = 0
    feedback = []
    
    # --- 1. SQL Injection (DatabaseHelper.java) ---
    # Expect: PreparedStatement usage, no string concat in query
    content = files.get("DatabaseHelper.java", "")
    if "PreparedStatement" in content and "prepareStatement" in content:
        # Crude check for absence of variable concatenation in SQL string
        # Look for: "SELECT ... '" + username + "'" pattern (bad)
        # Look for: "SELECT ... ?" (good)
        if "?" in content and "createStatement" not in content:
            score += 15
            feedback.append("[PASS] SQL Injection: Used PreparedStatement")
        else:
            score += 10 # Partial
            feedback.append("[WARN] SQL Injection: PreparedStatement used but check usage")
    elif content:
        feedback.append("[FAIL] SQL Injection: No PreparedStatement found")
    else:
        feedback.append("[FAIL] DatabaseHelper.java missing")

    # --- 2. Path Traversal (FileManager.java) ---
    # Expect: getCanonicalPath, toRealPath, or normalize check
    content = files.get("FileManager.java", "")
    if "getCanonicalPath" in content or "toRealPath" in content or "normalize" in content:
        score += 15
        feedback.append("[PASS] Path Traversal: Path normalization/canonicalization found")
    elif content:
        feedback.append("[FAIL] Path Traversal: No canonical path check found")
    else:
        feedback.append("[FAIL] FileManager.java missing")

    # --- 3. Insecure Random (TokenGenerator.java) ---
    # Expect: SecureRandom, NO java.util.Random
    content = files.get("TokenGenerator.java", "")
    if "SecureRandom" in content:
        if "new Random()" not in content:
            score += 15
            feedback.append("[PASS] Insecure Random: Replaced with SecureRandom")
        else:
            score += 5
            feedback.append("[WARN] Insecure Random: SecureRandom added but Random still present")
    elif content:
        feedback.append("[FAIL] Insecure Random: SecureRandom not found")
    else:
        feedback.append("[FAIL] TokenGenerator.java missing")

    # --- 4. Hardcoded Credentials (ConfigLoader.java) ---
    # Expect: System.getenv or similar. Check specifically that the old hardcoded strings are GONE.
    content = files.get("ConfigLoader.java", "")
    bad_pass = "db_p@ssw0rd_2024!"
    bad_key = "sk-api-9f8e7d6c5b4a3210"
    
    if content:
        if bad_pass not in content and bad_key not in content:
            if "System.getenv" in content or "getProperty" in content or "Properties" in content:
                score += 15
                feedback.append("[PASS] Credentials: Hardcoded secrets removed and externalized")
            else:
                score += 10
                feedback.append("[WARN] Credentials: Secrets removed but external loading method unclear")
        else:
            feedback.append("[FAIL] Credentials: Hardcoded secrets still present")
    else:
        feedback.append("[FAIL] ConfigLoader.java missing")

    # --- 5. XXE (XmlProcessor.java) ---
    # Expect: setFeature calls to disable DTDs
    content = files.get("XmlProcessor.java", "")
    if "setFeature" in content or "setAttribute" in content or "setExpandEntityReferences" in content:
        if "http://apache.org/xml/features/disallow-doctype-decl" in content or \
           "http://xml.org/sax/features/external-general-entities" in content or \
           "ACCESS_EXTERNAL_DTD" in content:
            score += 15
            feedback.append("[PASS] XXE: XML parser features configured securely")
        else:
            score += 5
            feedback.append("[WARN] XXE: Feature setting found but might be incomplete")
    elif content:
        feedback.append("[FAIL] XXE: No feature configuration found")
    else:
        feedback.append("[FAIL] XmlProcessor.java missing")

    # --- 6. Weak Hashing (PasswordUtil.java) ---
    # Expect: PBKDF2, BCrypt, Argon2, etc. NO "MD5".
    content = files.get("PasswordUtil.java", "")
    if "MD5" not in content:
        if "PBKDF2" in content or "SecretKeyFactory" in content or "BCrypt" in content or "Argon2" in content or "SCrypt" in content:
            score += 15
            feedback.append("[PASS] Weak Hashing: Replaced MD5 with strong algorithm")
        else:
            score += 5
            feedback.append("[WARN] Weak Hashing: MD5 removed but replacement unclear")
    elif content:
        feedback.append("[FAIL] Weak Hashing: MD5 still present")
    else:
        feedback.append("[FAIL] PasswordUtil.java missing")

    # --- 7. Compilation Check ---
    if compilation_success:
        score += 10
        feedback.append("[PASS] Compilation: Build success")
    else:
        # If compilation fails, strictly limit max score to prevent "blind editing" gaming
        # A non-compiling security fix is not a fix.
        score = min(score, 40) 
        feedback.append("[FAIL] Compilation: Build failed (max score capped at 40)")

    # Anti-gaming: Check if files were actually modified
    modified_count = result.get("modified_file_count", 0)
    if modified_count == 0:
        score = 0
        feedback.append("[FAIL] Anti-gaming: No files were modified")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": "\n".join(feedback)
    }