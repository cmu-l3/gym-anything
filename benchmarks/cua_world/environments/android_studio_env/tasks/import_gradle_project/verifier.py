#!/usr/bin/env python3
"""
Verifier for the import_gradle_project task.

Checks that the SunflowerApp Gradle project was successfully imported into
Android Studio by examining the project directory for IDE metadata, Gradle
artefacts, and expected source files.

Scoring (100 points total):
  - Project opened in IDE (.idea/ directory exists):              35 pts
  - Gradle sync completed (.gradle/ directory in project):        30 pts
  - settings.gradle.kts has correct project name:                 15 pts
  - build.gradle.kts exists and is valid:                          8 pts
  - Plant.kt source file exists with expected content:             6 pts
  - PlantRepository.kt exists with expected content:               6 pts

Baseline (no agent action): ~35/100 (static files only)
After agent opens project: 100/100
Pass threshold: 80
"""

import json
import logging
import os
import tempfile

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


def verify_import_gradle_project(traj, env_info, task_info):
    """
    Main verifier entry-point.

    Uses copy_from_env to inspect the container state directly,
    with the export_result.sh JSON as a supplementary signal.
    """
    copy_from_env = env_info.get("copy_from_env")

    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Framework error: copy_from_env not available",
        }

    metadata = task_info.get("metadata", {})
    project_dir = metadata.get("project_dir", "/home/ga/AndroidStudioProjects/SunflowerApp")
    expected_package = metadata.get("expected_package", "com.google.samples.apps.sunflower")
    expected_project_name = metadata.get("expected_project_name", "SunflowerApp")

    score = 0
    feedback_parts = []
    details = {}

    # Read the export_result.sh JSON for supplementary info
    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")

    # ==================================================================
    # 1. Project opened in IDE - .idea/ directory exists (35 points)
    # ==================================================================
    idea_exists = False
    idea_misc = _read_text_from_env(copy_from_env, f"{project_dir}/.idea/misc.xml")
    if idea_misc:
        idea_exists = True
    else:
        idea_ws = _read_text_from_env(copy_from_env, f"{project_dir}/.idea/workspace.xml")
        idea_modules = _read_text_from_env(copy_from_env, f"{project_dir}/.idea/modules.xml")
        idea_gradle = _read_text_from_env(copy_from_env, f"{project_dir}/.idea/gradle.xml")
        if idea_ws or idea_modules or idea_gradle:
            idea_exists = True
    # Fallback: check export result
    if not idea_exists:
        idea_exists = result.get("idea_dir_exists", False)

    details["idea_dir_exists"] = idea_exists

    if idea_exists:
        score += 35
        feedback_parts.append("Project opened in IDE (.idea/ exists): PASS [35/35]")
    else:
        feedback_parts.append("Project NOT opened in IDE (.idea/ missing): FAIL [0/35]")

    # ==================================================================
    # 2. Gradle sync completed - .gradle/ directory exists (30 points)
    # ==================================================================
    gradle_cache_exists = False
    gradle_properties = _read_text_from_env(
        copy_from_env, f"{project_dir}/.gradle/file-system.probe"
    )
    if gradle_properties:
        gradle_cache_exists = True
    else:
        gc = _read_text_from_env(
            copy_from_env, f"{project_dir}/.gradle/buildOutputCleanup/buildOutputCleanup.lock"
        )
        if gc:
            gradle_cache_exists = True

    # Fallback: check export result
    if not gradle_cache_exists:
        gradle_cache_exists = result.get("gradle_cache_exists", False)

    # Also check for build/ directories
    build_dir_exists = result.get("build_dir_exists", False)

    gradle_sync_score = 0
    if gradle_cache_exists:
        gradle_sync_score = 30
        feedback_parts.append("Gradle sync completed (.gradle/ exists): PASS [30/30]")
    elif build_dir_exists:
        gradle_sync_score = 18
        feedback_parts.append("Gradle sync partial (build/ exists but no .gradle/): PARTIAL [18/30]")
    else:
        feedback_parts.append("Gradle sync NOT completed (no .gradle/ or build/): FAIL [0/30]")

    score += gradle_sync_score
    details["gradle_cache_exists"] = gradle_cache_exists
    details["build_dir_exists"] = build_dir_exists

    # ==================================================================
    # 3. settings.gradle.kts has correct project name (15 points)
    # ==================================================================
    settings_content = _read_text_from_env(
        copy_from_env, f"{project_dir}/settings.gradle.kts"
    )
    settings_score = 0

    if settings_content:
        has_project_name = f'rootProject.name = "{expected_project_name}"' in settings_content
        has_app_include = 'include(":app")' in settings_content

        if has_project_name and has_app_include:
            settings_score = 15
            feedback_parts.append("settings.gradle.kts correct (name + :app): PASS [15/15]")
        elif has_project_name or has_app_include:
            settings_score = 10
            feedback_parts.append("settings.gradle.kts partially correct: PARTIAL [10/15]")
        else:
            settings_score = 5
            feedback_parts.append("settings.gradle.kts exists but unexpected content: PARTIAL [5/15]")
    else:
        feedback_parts.append("settings.gradle.kts NOT found: FAIL [0/15]")

    score += settings_score
    details["settings_found"] = bool(settings_content)
    details["settings_has_project_name"] = (
        f'rootProject.name = "{expected_project_name}"' in settings_content
        if settings_content
        else False
    )

    # ==================================================================
    # 4. build.gradle.kts exists and is valid (8 points)
    # ==================================================================
    top_build_gradle = _read_text_from_env(
        copy_from_env, f"{project_dir}/build.gradle.kts"
    )
    app_build_gradle = _read_text_from_env(
        copy_from_env, f"{project_dir}/app/build.gradle.kts"
    )

    build_gradle_valid = False
    build_gradle_score = 0

    if top_build_gradle:
        has_android_plugin = "com.android.application" in top_build_gradle
        has_kotlin_plugin = "kotlin" in top_build_gradle.lower()
        if has_android_plugin and has_kotlin_plugin:
            build_gradle_score = 8
            build_gradle_valid = True
            feedback_parts.append("build.gradle.kts valid (Android + Kotlin plugins): PASS [8/8]")
        elif has_android_plugin or has_kotlin_plugin:
            build_gradle_score = 5
            build_gradle_valid = True
            feedback_parts.append("build.gradle.kts partially valid: PARTIAL [5/8]")
        else:
            build_gradle_score = 2
            feedback_parts.append("build.gradle.kts exists but missing expected plugins: PARTIAL [2/8]")
    else:
        feedback_parts.append("build.gradle.kts NOT found: FAIL [0/8]")

    score += build_gradle_score
    details["build_gradle_valid"] = build_gradle_valid
    details["top_build_gradle_found"] = bool(top_build_gradle)
    details["app_build_gradle_found"] = bool(app_build_gradle)

    # ==================================================================
    # 5. Plant.kt exists with expected content (6 points)
    # ==================================================================
    plant_kt_path = (
        f"{project_dir}/app/src/main/java/"
        f"{expected_package.replace('.', '/')}/data/Plant.kt"
    )
    plant_kt_content = _read_text_from_env(copy_from_env, plant_kt_path)
    plant_kt_score = 0

    if plant_kt_content:
        has_plantid = "plantId" in plant_kt_content
        has_name = "val name" in plant_kt_content or "name: String" in plant_kt_content
        has_description = "description" in plant_kt_content
        has_data_class = "data class Plant" in plant_kt_content
        has_package = expected_package in plant_kt_content

        checks_passed = sum([has_plantid, has_name, has_description, has_data_class, has_package])
        details["plant_kt_checks"] = {
            "plantId": has_plantid,
            "name_field": has_name,
            "description_field": has_description,
            "data_class": has_data_class,
            "package": has_package,
        }

        if checks_passed >= 4:
            plant_kt_score = 6
            feedback_parts.append(f"Plant.kt valid ({checks_passed}/5 checks): PASS [6/6]")
        elif checks_passed >= 2:
            plant_kt_score = 4
            feedback_parts.append(f"Plant.kt partially valid ({checks_passed}/5 checks): PARTIAL [4/6]")
        else:
            plant_kt_score = 2
            feedback_parts.append(f"Plant.kt exists but unexpected content ({checks_passed}/5): PARTIAL [2/6]")
    else:
        feedback_parts.append("Plant.kt NOT found: FAIL [0/6]")

    score += plant_kt_score
    details["plant_kt_found"] = bool(plant_kt_content)

    # ==================================================================
    # 6. PlantRepository.kt exists with expected content (6 points)
    # ==================================================================
    repo_kt_path = (
        f"{project_dir}/app/src/main/java/"
        f"{expected_package.replace('.', '/')}/data/PlantRepository.kt"
    )
    repo_kt_content = _read_text_from_env(copy_from_env, repo_kt_path)
    repo_kt_score = 0

    if repo_kt_content:
        has_class = "class PlantRepository" in repo_kt_content
        has_getplants = "getPlants" in repo_kt_content
        has_getplant = "getPlant" in repo_kt_content
        has_singleton = "getInstance" in repo_kt_content
        has_package = expected_package in repo_kt_content

        checks_passed = sum([has_class, has_getplants, has_getplant, has_singleton, has_package])
        details["repo_kt_checks"] = {
            "class_decl": has_class,
            "getPlants": has_getplants,
            "getPlant": has_getplant,
            "singleton": has_singleton,
            "package": has_package,
        }

        if checks_passed >= 4:
            repo_kt_score = 6
            feedback_parts.append(f"PlantRepository.kt valid ({checks_passed}/5 checks): PASS [6/6]")
        elif checks_passed >= 2:
            repo_kt_score = 4
            feedback_parts.append(f"PlantRepository.kt partially valid ({checks_passed}/5 checks): PARTIAL [4/6]")
        else:
            repo_kt_score = 2
            feedback_parts.append(f"PlantRepository.kt exists but unexpected ({checks_passed}/5): PARTIAL [2/6]")
    else:
        feedback_parts.append("PlantRepository.kt NOT found: FAIL [0/6]")

    score += repo_kt_score
    details["repo_kt_found"] = bool(repo_kt_content)

    # ==================================================================
    # Final assessment
    # ==================================================================
    passed = score >= 80

    if score == 100:
        feedback_parts.append("Perfect score - project fully imported and synced!")
    elif passed:
        feedback_parts.append("Project import verified successfully.")
    else:
        feedback_parts.append("Project import incomplete - check that the project was opened in Android Studio and Gradle sync finished.")

    details["total_score"] = score

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": " | ".join(feedback_parts),
        "details": details,
    }
