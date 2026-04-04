#!/usr/bin/env python3
"""
Verifier for configure_release_signing task.

Verifies:
1. Keystore created with correct credentials and DN (via keytool output)
2. Build.gradle.kts configured with signingConfig
3. Release APK created and signed (via apksigner output)
4. Report file correctness
5. Anti-gaming (timestamps)
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _read_json_from_env(copy_from_env, container_path: str) -> dict:
    """Copy a JSON file out of the container and return parsed dict."""
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

def verify_configure_release_signing(traj, env_info, task_info):
    """Verify release signing configuration and artifacts."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_alias = metadata.get('expected_alias', 'weather-release-key')
    expected_cn = metadata.get('expected_cn', 'Weather App Team')
    expected_org = metadata.get('expected_org', 'CloudView Inc')

    # Read result from container
    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    
    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. Keystore Verification (25 points)
    # =========================================================
    keystore_exists = result.get('keystore_exists', False)
    keystore_valid = result.get('keystore_valid', False)
    keystore_details = result.get('keystore_details', '')
    keystore_fresh = result.get('keystore_created_during_task', False)
    
    if keystore_exists and keystore_fresh:
        score += 5
        feedback_parts.append("Keystore file created")
        
        if keystore_valid:
            score += 10
            feedback_parts.append("Keystore password valid")
            
            # Check Alias
            if expected_alias in keystore_details:
                score += 5
                feedback_parts.append(f"Alias '{expected_alias}' found")
            else:
                feedback_parts.append(f"Alias '{expected_alias}' NOT found")
                
            # Check DN (Distinguished Name)
            # keytool output format: "Owner: CN=Weather App Team, O=CloudView Inc, ..."
            if f"CN={expected_cn}" in keystore_details and f"O={expected_org}" in keystore_details:
                score += 5
                feedback_parts.append("Certificate DN matches requirements")
            else:
                feedback_parts.append("Certificate DN incorrect")
        else:
            feedback_parts.append("Keystore invalid (wrong password?)")
    elif keystore_exists:
        feedback_parts.append("Keystore exists but pre-dates task start (Anti-gaming)")
    else:
        feedback_parts.append("Keystore not found")

    # =========================================================
    # 2. Gradle Configuration (25 points)
    # =========================================================
    bg_content = result.get('build_gradle_content', '')
    
    # Check for signingConfigs block
    if 'signingConfigs' in bg_content and 'create("release")' in bg_content:
        score += 10
        feedback_parts.append("signingConfigs configured")
    elif 'signingConfigs' in bg_content and 'release' in bg_content:
        # Loose check for Groovy or other syntax
        score += 10
        feedback_parts.append("signingConfigs configured")
    else:
        feedback_parts.append("signingConfigs missing in build.gradle.kts")
        
    # Check for usage in buildType
    if 'signingConfig' in bg_content and 'getByName("release")' in bg_content:
        score += 15
        feedback_parts.append("release buildType uses signingConfig")
    elif 'signingConfig = signingConfigs.getByName("release")' in bg_content:
        score += 15
    elif 'signingConfig' in bg_content and 'release' in bg_content:
         # Generic loose check
        score += 10 
        feedback_parts.append("release buildType seems to use signingConfig")
    else:
        feedback_parts.append("signingConfig assignment missing in release buildType")

    # =========================================================
    # 3. APK Generation & Signing (40 points)
    # =========================================================
    apk_exists = result.get('apk_exists', False)
    apk_signed = result.get('apk_signed', False)
    apk_signer_details = result.get('apk_signer_details', '')
    apk_fresh = result.get('apk_created_during_task', False)
    
    if apk_exists and apk_fresh:
        score += 15
        feedback_parts.append("Release APK created")
        
        if apk_signed:
            score += 15
            feedback_parts.append("APK verification passed")
            
            # Verify the cert in the APK matches the expected CN
            if f"CN={expected_cn}" in apk_signer_details:
                score += 10
                feedback_parts.append("APK signed with correct certificate")
            else:
                feedback_parts.append("APK signed with WRONG certificate")
        else:
            feedback_parts.append("APK verification FAILED (not signed properly)")
    elif apk_exists:
        feedback_parts.append("APK exists but pre-dates task (Anti-gaming)")
    else:
        feedback_parts.append("Release APK not found")

    # =========================================================
    # 4. Report File (10 points)
    # =========================================================
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').strip().split('\n')
    
    if report_exists:
        if len(report_content) >= 3:
            # Check if lines look like paths/alias
            keystore_path_check = '/home/ga' in report_content[0]
            alias_check = expected_alias in report_content[1]
            apk_path_check = '.apk' in report_content[2]
            
            if keystore_path_check and alias_check and apk_path_check:
                score += 10
                feedback_parts.append("Report file valid")
            else:
                score += 5
                feedback_parts.append("Report file exists but content issues")
        else:
            score += 2
            feedback_parts.append("Report file incomplete")
    else:
        feedback_parts.append("Report file missing")

    # =========================================================
    # 5. VLM / Trajectory Verification (Bonus / Sanity)
    # =========================================================
    # (Optional implementation for VLM could go here using gym_anything.vlm)
    # Since we have strong programmatic signals (APK signature), we rely on that.

    passed = (score >= 60) and apk_signed and keystore_valid

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }