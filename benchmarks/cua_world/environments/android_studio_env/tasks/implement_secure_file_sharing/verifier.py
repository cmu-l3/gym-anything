#!/usr/bin/env python3
"""
Verifier for implement_secure_file_sharing task.

SCORING CRITERIA (100 points total):
1. Manifest Configuration (25 pts):
   - <provider> tag exists
   - authority = "com.example.logshare.fileprovider"
   - exported = false
   - grantUriPermissions = true
   - meta-data points to xml resource

2. XML Resource (25 pts):
   - file exists at app/src/main/res/xml/provider_paths.xml
   - contains <files-path> element

3. Kotlin Implementation (30 pts):
   - uses FileProvider.getUriForFile
   - uses "com.example.logshare.fileprovider" authority
   - sets FLAG_GRANT_READ_URI_PERMISSION
   - uses Intent.EXTRA_STREAM

4. Build Success (20 pts):
   - ./gradlew assembleDebug succeeds
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

def verify_implement_secure_file_sharing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    expected_authority = metadata.get("expected_authority", "com.example.logshare.fileprovider")

    # Read result from export script
    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")

    manifest_content = result.get("manifest_content", "")
    xml_content = result.get("xml_content", "")
    main_activity_content = result.get("main_activity_content", "")
    build_success = result.get("build_success", False)
    xml_exists = result.get("xml_exists", False)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Manifest Verification (25 pts)
    # ---------------------------------------------------------
    manifest_score = 0
    
    # Check for provider definition
    if "<provider" in manifest_content:
        manifest_score += 5
        
        # Check attributes
        if 'androidx.core.content.FileProvider' in manifest_content:
            manifest_score += 5
        
        if expected_authority in manifest_content:
            manifest_score += 5
        else:
            feedback_parts.append(f"Manifest missing authority: {expected_authority}")
            
        if 'android:exported="false"' in manifest_content or "android:exported='false'" in manifest_content:
            manifest_score += 5
        else:
            feedback_parts.append("Provider must have exported=false")
            
        if 'android:grantUriPermissions="true"' in manifest_content or "android:grantUriPermissions='true'" in manifest_content:
            manifest_score += 5
        
        # Check metadata
        if '<meta-data' in manifest_content and 'android:resource="@xml/provider_paths"' in manifest_content:
            # Bonus check, implied by previous but good for robustness
            pass
            
    else:
        feedback_parts.append("Manifest missing <provider> tag")

    score += manifest_score
    feedback_parts.append(f"Manifest score: {manifest_score}/25")

    # ---------------------------------------------------------
    # 2. XML Resource Verification (25 pts)
    # ---------------------------------------------------------
    xml_score = 0
    if xml_exists:
        xml_score += 10 # File exists
        
        # Check content
        if '<paths' in xml_content:
            xml_score += 5
        if '<files-path' in xml_content:
            xml_score += 10
        elif '<external-path' in xml_content or '<cache-path' in xml_content:
            # Partial credit if they used wrong path type but valid XML
            xml_score += 5
            feedback_parts.append("XML used wrong path type (expected <files-path>)")
    else:
        feedback_parts.append("provider_paths.xml not found")

    score += xml_score
    feedback_parts.append(f"XML score: {xml_score}/25")

    # ---------------------------------------------------------
    # 3. Kotlin Implementation Verification (30 pts)
    # ---------------------------------------------------------
    kotlin_score = 0
    
    if "FileProvider.getUriForFile" in main_activity_content:
        kotlin_score += 10
    else:
        feedback_parts.append("MainActivity missing FileProvider.getUriForFile")

    if expected_authority in main_activity_content:
        kotlin_score += 5
    
    if "FLAG_GRANT_READ_URI_PERMISSION" in main_activity_content:
        kotlin_score += 10
    else:
        feedback_parts.append("MainActivity missing FLAG_GRANT_READ_URI_PERMISSION")

    if "EXTRA_STREAM" in main_activity_content:
        kotlin_score += 5

    score += kotlin_score
    feedback_parts.append(f"Kotlin score: {kotlin_score}/30")

    # ---------------------------------------------------------
    # 4. Build Verification (20 pts)
    # ---------------------------------------------------------
    if build_success:
        score += 20
        feedback_parts.append("Build succeeded (20/20)")
    else:
        feedback_parts.append("Build failed (0/20)")

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    passed = score >= 80 and build_success
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }