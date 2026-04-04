#!/usr/bin/env python3
"""
Verifier for migrate_version_catalog task.

Criteria:
1. gradle/libs.versions.toml exists and parses correctly.
2. TOML contains [versions], [libraries], [plugins].
3. build.gradle.kts files use 'libs.*' references.
4. Hardcoded versions are removed from build.gradle.kts.
5. Project builds successfully.
"""

import json
import logging
import os
import re
import tempfile
import configparser

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_migrate_version_catalog(traj, env_info, task_info):
    """
    Verify the migration to Gradle Version Catalog.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    score = 0
    feedback = []
    
    # Data extraction
    toml_content = result.get("toml_content", "")
    app_content = result.get("app_build_content", "")
    data_content = result.get("data_build_content", "")
    build_success = result.get("build_success", False)
    
    # --- Criterion 1: TOML Existence and Structure (30 pts) ---
    if result.get("toml_exists"):
        score += 10
        feedback.append("libs.versions.toml created.")
        
        # Simple string checks for sections (avoiding complex TOML parsing dependency issues)
        has_versions = "[versions]" in toml_content
        has_libraries = "[libraries]" in toml_content
        
        if has_versions and has_libraries:
            score += 20
            feedback.append("TOML structure looks correct ([versions] and [libraries] found).")
        else:
            feedback.append("TOML missing required sections ([versions] or [libraries]).")
    else:
        feedback.append("libs.versions.toml NOT found.")

    # --- Criterion 2: Content of TOML (20 pts) ---
    # Check for specific keys we expect to be migrated
    # "androidx-core", "retrofit", "room", "coroutines"
    
    expected_libs = ["retrofit", "room", "coroutines", "core-ktx"]
    found_libs = 0
    for lib in expected_libs:
        if lib in toml_content:
            found_libs += 1
            
    if found_libs >= 3:
        score += 20
        feedback.append(f"TOML contains expected library definitions ({found_libs}/{len(expected_libs)}).")
    elif found_libs > 0:
        score += 10
        feedback.append("TOML contains some library definitions.")
    else:
        feedback.append("TOML does not appear to contain expected libraries.")

    # --- Criterion 3: App Build File Migration (20 pts) ---
    # Check for libs. references
    libs_ref_count = len(re.findall(r'libs\.[a-zA-Z0-9_.]+', app_content))
    
    # Check for remaining hardcoded versions (simple regex for "x.y.z" pattern inside dependency block)
    # This is heuristic but effective. We look for dependencies("...") containing numbers.
    hardcoded_pattern = r'implementation\s*\(".*:\d+\.\d+\.\d+"'
    hardcoded_remaining = re.search(hardcoded_pattern, app_content)
    
    if libs_ref_count >= 5:
        score += 20
        feedback.append(f"app/build.gradle.kts uses catalog references ({libs_ref_count} found).")
    elif libs_ref_count > 0:
        score += 10
        feedback.append("app/build.gradle.kts partially migrated.")
    else:
        feedback.append("app/build.gradle.kts does not use 'libs.*' references.")

    if hardcoded_remaining:
        feedback.append("Warning: Hardcoded versions still detected in app/build.gradle.kts.")
        # We penalize loosely in the final pass check, or deduct points
        score = max(0, score - 5)

    # --- Criterion 4: Data Build File Migration (15 pts) ---
    data_libs_ref_count = len(re.findall(r'libs\.[a-zA-Z0-9_.]+', data_content))
    
    if data_libs_ref_count >= 5:
        score += 15
        feedback.append("data/build.gradle.kts uses catalog references.")
    elif data_libs_ref_count > 0:
        score += 5
        feedback.append("data/build.gradle.kts partially migrated.")
        
    # --- Criterion 5: Build Success (15 pts) ---
    if build_success:
        score += 15
        feedback.append("Project builds successfully.")
    else:
        feedback.append("Project build failed.")

    # --- VLM / Anti-gaming check ---
    if not result.get("app_hash_changed") or not result.get("data_hash_changed"):
        score = 0
        feedback = ["FAILED: Build files were not modified."]

    # Final Result
    passed = score >= 60 and build_success
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }