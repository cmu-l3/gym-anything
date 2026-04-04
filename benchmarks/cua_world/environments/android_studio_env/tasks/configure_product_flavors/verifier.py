#!/usr/bin/env python3
"""
Verifier for Configure Product Flavors task.

Scoring (100 points total):
1. build.gradle.kts modified during task (10 pts)
2. flavorDimensions "version" present (15 pts)
3. productFlavors block present (10 pts)
4. 'free' flavor configured correctly (10 pts)
   - applicationIdSuffix = ".free"
   - versionNameSuffix = "-free"
5. 'paid' flavor configured correctly (10 pts)
   - applicationIdSuffix = ".paid"
   - versionNameSuffix = "-paid"
6. free/res/values/strings.xml exists and contains "Todo Free" (15 pts)
7. paid/res/values/strings.xml exists and contains "Todo Pro" (15 pts)
8. Gradle build confirms valid configuration (15 pts)
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


def verify_configure_product_flavors(traj, env_info, task_info):
    """Verify product flavors configuration."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result from export script
    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    
    build_gradle = result.get('build_gradle_content', '')
    free_strings = result.get('free_strings_content', '')
    paid_strings = result.get('paid_strings_content', '')
    
    score = 0
    feedback_parts = []
    
    # 1. Anti-gaming check (10 pts)
    if result.get('file_modified_during_task', False):
        score += 10
        feedback_parts.append("build.gradle.kts modified (10/10)")
    else:
        feedback_parts.append("build.gradle.kts NOT modified (0/10)")
        
    # 2. Check flavorDimensions (15 pts)
    # Matches: flavorDimensions += "version" OR flavorDimensions.add("version")
    if re.search(r'flavorDimensions.*["\']version["\']', build_gradle, re.IGNORECASE):
        score += 15
        feedback_parts.append("flavorDimensions configured (15/15)")
    else:
        feedback_parts.append("flavorDimensions missing or incorrect (0/15)")
        
    # 3. Check productFlavors block (10 pts)
    if 'productFlavors' in build_gradle:
        score += 10
        feedback_parts.append("productFlavors block found (10/10)")
    else:
        feedback_parts.append("productFlavors block missing (0/10)")
        
    # 4. Check 'free' flavor (10 pts)
    free_ok = False
    if re.search(r'(create|register|getByName)\s*\(\s*["\']free["\']', build_gradle) or \
       re.search(r'\bfree\s*\{', build_gradle):
        
        suffix_ok = re.search(r'applicationIdSuffix\s*=\s*["\']\.free["\']', build_gradle)
        ver_ok = re.search(r'versionNameSuffix\s*=\s*["\']-free["\']', build_gradle)
        
        if suffix_ok and ver_ok:
            score += 10
            free_ok = True
            feedback_parts.append("'free' flavor fully configured (10/10)")
        else:
            score += 5
            feedback_parts.append("'free' flavor defined but missing suffixes (5/10)")
    else:
        feedback_parts.append("'free' flavor missing (0/10)")
        
    # 5. Check 'paid' flavor (10 pts)
    paid_ok = False
    if re.search(r'(create|register|getByName)\s*\(\s*["\']paid["\']', build_gradle) or \
       re.search(r'\bpaid\s*\{', build_gradle):
        
        suffix_ok = re.search(r'applicationIdSuffix\s*=\s*["\']\.paid["\']', build_gradle)
        ver_ok = re.search(r'versionNameSuffix\s*=\s*["\']-paid["\']', build_gradle)
        
        if suffix_ok and ver_ok:
            score += 10
            paid_ok = True
            feedback_parts.append("'paid' flavor fully configured (10/10)")
        else:
            score += 5
            feedback_parts.append("'paid' flavor defined but missing suffixes (5/10)")
    else:
        feedback_parts.append("'paid' flavor missing (0/10)")

    # 6. Check free strings (15 pts)
    if result.get('free_strings_exists', False):
        if "Todo Free" in free_strings:
            score += 15
            feedback_parts.append("Free strings.xml correct (15/15)")
        else:
            score += 5
            feedback_parts.append("Free strings.xml exists but wrong content (5/15)")
    else:
        feedback_parts.append("Free strings.xml missing (0/15)")

    # 7. Check paid strings (15 pts)
    if result.get('paid_strings_exists', False):
        if "Todo Pro" in paid_strings:
            score += 15
            feedback_parts.append("Paid strings.xml correct (15/15)")
        else:
            score += 5
            feedback_parts.append("Paid strings.xml exists but wrong content (5/15)")
    else:
        feedback_parts.append("Paid strings.xml missing (0/15)")

    # 8. Gradle confirmation (15 pts)
    if result.get('gradle_variants_detected', False):
        score += 15
        feedback_parts.append("Gradle validated build configuration (15/15)")
    elif result.get('gradle_variants_count', 0) > 0:
        score += 5
        feedback_parts.append("Gradle saw some flavors but not all (5/15)")
    else:
        feedback_parts.append("Gradle validation failed (0/15)")
        
    # Cap score
    score = min(score, 100)
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }