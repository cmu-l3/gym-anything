#!/usr/bin/env python3
"""
Verifier for secure_api_key_management task.

Requirements:
1. API Key moved to local.properties.
2. build.gradle.kts configured to read key and create buildConfigField.
3. WeatherService.kt refactored to use BuildConfig.
4. Project compiles successfully.
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

def verify_secure_api_key(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    expected_key = metadata.get("api_key_value", "owm_8a7b6c5d4e3f2g1h0i9j8k7l6m5n4o3p")
    key_name = metadata.get("api_key_name", "WEATHER_API_KEY")

    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    
    local_props = result.get("local_properties_content", "")
    build_gradle = result.get("build_gradle_content", "")
    service_code = result.get("service_file_content", "")
    build_success = result.get("build_success", False)

    score = 0
    feedback_parts = []
    
    # Check 1: local.properties contains the key (20 pts)
    # Regex for key=value, allowing whitespace
    key_in_props = False
    if re.search(fr'^{key_name}\s*=\s*{expected_key}', local_props, re.MULTILINE):
        key_in_props = True
    elif re.search(fr'^{key_name}\s*=\s*"*{expected_key}"*', local_props, re.MULTILINE):
        # Handle quotes if user added them
        key_in_props = True
        
    if key_in_props:
        score += 20
        feedback_parts.append("Key found in local.properties")
    else:
        feedback_parts.append("Key NOT found in local.properties")

    # Check 2: build.gradle.kts configurations (30 pts)
    # Needs: buildConfig = true (or implied), buildConfigField logic
    # We look for 'buildConfigField' and the key name
    
    has_build_config_field = "buildConfigField" in build_gradle
    has_key_in_gradle = key_name in build_gradle
    
    if has_build_config_field and has_key_in_gradle:
        score += 30
        feedback_parts.append("build.gradle.kts configured correctly")
    elif has_build_config_field:
        score += 15
        feedback_parts.append("buildConfigField found but key name missing in gradle")
    else:
        feedback_parts.append("buildConfigField configuration missing in build.gradle.kts")

    # Check 3: WeatherService.kt refactoring (20 pts)
    # Should NOT contain the raw key string
    # Should contain BuildConfig.WEATHER_API_KEY
    
    raw_key_present = expected_key in service_code
    uses_build_config = f"BuildConfig.{key_name}" in service_code
    
    if not raw_key_present and uses_build_config:
        score += 20
        feedback_parts.append("Code refactored successfully")
    elif raw_key_present:
        feedback_parts.append("Hardcoded key still present in source code")
    elif not uses_build_config:
        feedback_parts.append("Source code does not reference BuildConfig")

    # Check 4: Build Success (30 pts)
    if build_success:
        score += 30
        feedback_parts.append("Project builds successfully")
    else:
        feedback_parts.append("Project build failed")

    passed = score == 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }