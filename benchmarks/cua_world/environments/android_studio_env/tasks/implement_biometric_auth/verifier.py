#!/usr/bin/env python3
"""
Verifier for implement_biometric_auth task.

Success Criteria:
1. build.gradle.kts contains 'androidx.biometric:biometric' (20 pts)
2. LoginActivity.kt uses BiometricPrompt (20 pts)
3. LoginActivity.kt has PromptInfo configured (20 pts)
4. LoginActivity.kt has secure navigation logic (StartActivity inside onAuthenticationSucceeded) (40 pts)
   - Must NOT have direct navigation in setOnClickListener
   - Must have navigation in callback
5. Build success (Pass/Fail check, required for full score confidence)
"""

import json
import logging
import re
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_biometric_auth(traj, env_info, task_info):
    """Verify biometric authentication implementation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy_from_env missing"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    login_code = result.get('login_activity_content', '')
    gradle_code = result.get('build_gradle_content', '')
    build_success = result.get('build_success', False)

    score = 0
    feedback = []

    # Criterion 1: Dependency Check (20 pts)
    # Check for implementation("androidx.biometric:biometric:...") or implementation '...'
    if re.search(r'androidx\.biometric:biometric', gradle_code):
        score += 20
        feedback.append("Dependency added (20/20)")
    else:
        feedback.append("Missing biometric dependency in build.gradle.kts (0/20)")

    # Criterion 2: BiometricPrompt Usage (20 pts)
    # Check for instantiation of BiometricPrompt
    if 'BiometricPrompt(' in login_code and 'ContextCompat.getMainExecutor' in login_code:
        score += 20
        feedback.append("BiometricPrompt instantiated (20/20)")
    else:
        feedback.append("BiometricPrompt instantiation not found (0/20)")

    # Criterion 3: PromptInfo Configuration (20 pts)
    # Check for PromptInfo builder and setTitle
    if 'PromptInfo.Builder()' in login_code and '.setTitle(' in login_code:
        score += 20
        feedback.append("PromptInfo configured (20/20)")
    else:
        feedback.append("PromptInfo configuration missing or incomplete (0/20)")

    # Criterion 4: Secure Navigation Logic (40 pts)
    # This is the most critical part. 
    # Logic: 
    #   1. 'startActivity' should NOT be inside 'setOnClickListener' direct block
    #   2. 'startActivity' SHOULD be inside 'onAuthenticationSucceeded'
    #   3. 'setOnClickListener' SHOULD call '.authenticate'

    secure_nav_score = 0
    
    # Remove comments to avoid false positives
    code_no_comments = re.sub(r'//.*', '', login_code)
    
    # Check if authenticate is called
    if '.authenticate(' in code_no_comments:
        secure_nav_score += 10
        feedback.append("Button triggers authentication (10/10)")
    else:
        feedback.append("Button does not seem to trigger authentication (0/10)")

    # Check if startActivity is inside onAuthenticationSucceeded
    # We look for the pattern: onAuthenticationSucceeded ... { ... startActivity ... }
    # Using regex with DOTALL is tricky for nested braces, so we use a simpler heuristic:
    # Does 'startActivity' appear after 'onAuthenticationSucceeded'?
    match_callback = re.search(r'onAuthenticationSucceeded.*startActivity', code_no_comments, re.DOTALL)
    if match_callback:
        secure_nav_score += 20
        feedback.append("Navigation logic found in callback (20/20)")
    else:
        feedback.append("Navigation logic NOT found in onAuthenticationSucceeded (0/20)")

    # Check for Insecure Direct Navigation (Penalty)
    # We look for: setOnClickListener ... startActivity ... WITHOUT an intervening object/callback definition
    # This is hard to regex perfectly, but we can look for "startActivity" appearing close to setOnClickListener
    # A robust way: extract the setOnClickListener block.
    # If the student left the old code: "setOnClickListener { startActivity(...) }" -> FAIL
    
    # Heuristic: If we find `setOnClickListener` followed closely by `startActivity` without `authenticate` in between?
    # Better: If the user implemented it correctly, the button click usually just calls `prompt.authenticate(...)`.
    # If `startActivity` is present inside the listener scope directly, it's insecure.
    
    # We'll assume full points for the previous check (callback presence) implies intent, 
    # but we give the final 10 points only if the insecure pattern isn't obvious.
    # If `startActivity` appears twice, they might have left dead code.
    
    # Let's count occurrences.
    # If logic is moved, startActivity should likely appear ONCE (in the callback).
    # If it appears TWICE, they might have duplicated it (one secure, one insecure).
    if login_code.count('startActivity') == 1 and match_callback:
        secure_nav_score += 10
        feedback.append("Old insecure navigation removed (10/10)")
    elif login_code.count('startActivity') > 1:
        feedback.append("Warning: Multiple startActivity calls found. Ensure insecure path is removed (0/10)")
    else:
        # If it's 0, they deleted it entirely (broken app). If 1 but no match_callback, it's insecure.
        if not match_callback:
             feedback.append("Insecure navigation remains (0/10)")

    score += secure_nav_score

    # Penalty for build failure
    if not build_success:
        score = max(0, score - 20)
        feedback.append("PENALTY: Project does not compile (-20)")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback)
    }