#!/usr/bin/env python3
"""
Verifier for add_hilt_dependency_injection task.

Criteria:
1. Project-level build.gradle has Hilt plugin (10 pts)
2. App-level build.gradle has kapt/ksp and Hilt plugins (10 pts)
3. App-level build.gradle has Hilt dependencies (10 pts)
4. BookTrackerApplication class created with @HiltAndroidApp (15 pts)
5. AndroidManifest.xml registers the Application class (10 pts)
6. MainActivity annotated with @AndroidEntryPoint and uses @Inject (15 pts)
7. BookRepository annotated with @Inject constructor (10 pts)
8. Project builds successfully (20 pts)

Anti-gaming:
- Checks that files were actually modified (hash comparison).
"""

import json
import logging
import os
import re
import tempfile
import hashlib

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _read_text_from_env(copy_from_env, container_path: str) -> str:
    """Copy a text file out of the container and return its contents."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except Exception as exc:
        logger.debug("Could not read %s: %s", container_path, exc)
        return ""
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


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


def calculate_md5(content: str) -> str:
    return hashlib.md5(content.encode('utf-8')).hexdigest()


def verify_add_hilt_dependency_injection(traj, env_info, task_info):
    """Verify Hilt integration in BookTrackerApp."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    project_dir = metadata.get("project_dir", "/home/ga/AndroidStudioProjects/BookTrackerApp")
    app_pkg_path = "com/example/booktracker"

    # Define paths
    root_gradle_path = f"{project_dir}/build.gradle"
    app_gradle_path = f"{project_dir}/app/build.gradle"
    manifest_path = f"{project_dir}/app/src/main/AndroidManifest.xml"
    app_class_path = f"{project_dir}/app/src/main/java/{app_pkg_path}/BookTrackerApplication.kt"
    main_activity_path = f"{project_dir}/app/src/main/java/{app_pkg_path}/MainActivity.kt"
    repo_path = f"{project_dir}/app/src/main/java/{app_pkg_path}/BookRepository.kt"

    # Read current file contents
    root_gradle = _read_text_from_env(copy_from_env, root_gradle_path)
    app_gradle = _read_text_from_env(copy_from_env, app_gradle_path)
    manifest = _read_text_from_env(copy_from_env, manifest_path)
    app_class = _read_text_from_env(copy_from_env, app_class_path)
    main_activity = _read_text_from_env(copy_from_env, main_activity_path)
    repo = _read_text_from_env(copy_from_env, repo_path)
    
    # Read export result
    task_result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    
    # Read initial hashes for anti-gaming
    initial_hashes_content = _read_text_from_env(copy_from_env, "/tmp/initial_hashes.txt")
    initial_hashes = {}
    for line in initial_hashes_content.strip().split('\n'):
        parts = line.split()
        if len(parts) == 2:
            initial_hashes[parts[1]] = parts[0]

    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. Project-level build.gradle has Hilt plugin (10 pts)
    # =========================================================
    # Look for: id 'com.google.dagger.hilt.android' version ... apply false
    if re.search(r"id\s*['\"]com\.google\.dagger\.hilt\.android['\"]\s*version", root_gradle):
        score += 10
        feedback_parts.append("Root build.gradle: Hilt plugin found (+10)")
    else:
        feedback_parts.append("Root build.gradle: Hilt plugin missing (0)")

    # =========================================================
    # 2. App-level build.gradle has kapt/ksp and Hilt plugins (10 pts)
    # =========================================================
    has_kapt = re.search(r"id\s*['\"](org\.jetbrains\.kotlin\.kapt|kotlin-kapt)['\"]", app_gradle)
    has_hilt_plugin = re.search(r"id\s*['\"]com\.google\.dagger\.hilt\.android['\"]", app_gradle)
    
    if has_kapt and has_hilt_plugin:
        score += 10
        feedback_parts.append("App build.gradle: Plugins applied (+10)")
    elif has_hilt_plugin:
        score += 5
        feedback_parts.append("App build.gradle: Hilt plugin applied, missing kapt (+5)")
    else:
        feedback_parts.append("App build.gradle: Plugins missing (0)")

    # =========================================================
    # 3. App-level build.gradle has Hilt dependencies (10 pts)
    # =========================================================
    has_hilt_impl = re.search(r"implementation\s*['\"]com\.google\.dagger:hilt-android", app_gradle)
    has_hilt_compiler = re.search(r"(kapt|ksp)\s*['\"]com\.google\.dagger:hilt-compiler", app_gradle)
    
    if has_hilt_impl and has_hilt_compiler:
        score += 10
        feedback_parts.append("App build.gradle: Dependencies added (+10)")
    elif has_hilt_impl:
        score += 5
        feedback_parts.append("App build.gradle: Implementation added, missing compiler (+5)")
    else:
        feedback_parts.append("App build.gradle: Hilt dependencies missing (0)")

    # =========================================================
    # 4. BookTrackerApplication class created (15 pts)
    # =========================================================
    if app_class:
        if "@HiltAndroidApp" in app_class and "Application()" in app_class:
            score += 15
            feedback_parts.append("BookTrackerApplication: Created correctly (+15)")
        elif "@HiltAndroidApp" in app_class:
            score += 10
            feedback_parts.append("BookTrackerApplication: Annotation present, check inheritance (+10)")
        else:
            score += 5
            feedback_parts.append("BookTrackerApplication: File exists but missing annotation (+5)")
    else:
        feedback_parts.append("BookTrackerApplication: File not found (0)")

    # =========================================================
    # 5. Manifest registers Application (10 pts)
    # =========================================================
    if 'android:name=".BookTrackerApplication"' in manifest or 'android:name="com.example.booktracker.BookTrackerApplication"' in manifest:
        score += 10
        feedback_parts.append("Manifest: Application registered (+10)")
    else:
        feedback_parts.append("Manifest: Application class not registered (0)")

    # =========================================================
    # 6. MainActivity injection (15 pts)
    # =========================================================
    ma_points = 0
    if "@AndroidEntryPoint" in main_activity:
        ma_points += 5
    if "@Inject" in main_activity:
        ma_points += 5
    # check removal of direct instantiation " = BookRepository()"
    if " = BookRepository()" not in main_activity:
        ma_points += 5
    
    score += ma_points
    feedback_parts.append(f"MainActivity: Refactoring status ({ma_points}/15)")

    # =========================================================
    # 7. BookRepository injection (10 pts)
    # =========================================================
    if "@Inject constructor" in repo:
        score += 10
        feedback_parts.append("BookRepository: @Inject constructor found (+10)")
    else:
        feedback_parts.append("BookRepository: Missing @Inject constructor (0)")

    # =========================================================
    # 8. Build Success (20 pts)
    # =========================================================
    if task_result.get("build_success", False):
        score += 20
        feedback_parts.append("Gradle Build: SUCCESS (+20)")
    else:
        feedback_parts.append("Gradle Build: FAILED (0)")

    # =========================================================
    # Anti-Gaming Check
    # =========================================================
    files_changed = False
    
    # Check hashes against initial
    for path, old_hash in initial_hashes.items():
        # Get current content
        if path == root_gradle_path: content = root_gradle
        elif path == app_gradle_path: content = app_gradle
        elif path == manifest_path: content = manifest
        elif path == main_activity_path: content = main_activity
        elif path == repo_path: content = repo
        else: continue
        
        if content:
            new_hash = calculate_md5(content)
            if new_hash != old_hash:
                files_changed = True
                break
    
    # Also check if new file was created (App class)
    if app_class:
        files_changed = True

    if not files_changed:
        score = 0
        feedback_parts.append("ANTI-GAMING: No files were modified!")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }