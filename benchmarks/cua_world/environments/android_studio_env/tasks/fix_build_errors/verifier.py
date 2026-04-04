#!/usr/bin/env python3
"""
Verifier for fix_build_errors task.

The BrokenApp project has 4 intentional errors:
1. Missing import in MainActivity.kt (Bundle not imported)
2. Type mismatch in Plant.kt (growZoneNumber is String but compared as Int)
3. Missing retrofit2 dependency in build.gradle.kts
4. Syntax error in PlantRepository.kt (unclosed brace in addPlant function)

Scoring (100 points total):
- MainActivity.kt: has `import android.os.Bundle` (15 pts)
- Plant.kt: growZoneNumber has correct Int type (15 pts)
- PlantRepository.kt: syntax error fixed (closing brace present) (15 pts)
- build.gradle.kts: retrofit2 dependency added (15 pts)
- Build succeeds (gradle assembleDebug or compileDebugKotlin) (40 pts)
"""

import json
import logging
import os
import re
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


def verify_fix_build_errors(traj, env_info, task_info):
    """Verify that all build errors in BrokenApp have been fixed."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available - framework error"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/AndroidStudioProjects/BrokenApp')
    expected_package = metadata.get('expected_package', 'com.google.samples.apps.sunflower')

    pkg_path = expected_package.replace('.', '/')

    # Read files directly from the container via copy_from_env
    main_activity_content = _read_text_from_env(
        copy_from_env,
        f"{project_dir}/app/src/main/java/{pkg_path}/MainActivity.kt"
    )
    plant_kt_content = _read_text_from_env(
        copy_from_env,
        f"{project_dir}/app/src/main/java/{pkg_path}/data/Plant.kt"
    )
    plant_repo_content = _read_text_from_env(
        copy_from_env,
        f"{project_dir}/app/src/main/java/{pkg_path}/data/PlantRepository.kt"
    )
    build_gradle_content = _read_text_from_env(
        copy_from_env,
        f"{project_dir}/app/build.gradle.kts"
    )

    # Read the export result JSON as supplementary data (for build success flag)
    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")

    # Fall back to export JSON content if direct reads returned empty
    if not main_activity_content:
        main_activity_content = result.get('main_activity_content', '')
    if not plant_kt_content:
        plant_kt_content = result.get('plant_kt_content', '')
    if not plant_repo_content:
        plant_repo_content = result.get('plant_repo_content', '')
    if not build_gradle_content:
        build_gradle_content = result.get('build_gradle_content', '')

    feedback_parts = []
    score = 0
    details = {}

    # ================================================================
    # Criterion 1: MainActivity.kt - import android.os.Bundle (15 pts)
    # ================================================================
    details['main_activity_exists'] = bool(main_activity_content)

    has_bundle_import = bool(re.search(
        r'^\s*import\s+android\.os\.Bundle\s*$',
        main_activity_content,
        re.MULTILINE
    ))

    if has_bundle_import:
        score += 15
        feedback_parts.append("MainActivity.kt: Bundle import added (15/15)")
        details['bundle_import_fixed'] = True
    else:
        feedback_parts.append("MainActivity.kt: Missing 'import android.os.Bundle' (0/15)")
        details['bundle_import_fixed'] = False

    # ================================================================
    # Criterion 2: Plant.kt - growZoneNumber type fix (15 pts)
    # ================================================================
    details['plant_kt_exists'] = bool(plant_kt_content)

    grow_zone_int = bool(re.search(
        r'val\s+growZoneNumber\s*:\s*Int\b',
        plant_kt_content
    ))
    grow_zone_still_string = bool(re.search(
        r'val\s+growZoneNumber\s*:\s*String\b',
        plant_kt_content
    ))

    if grow_zone_int and not grow_zone_still_string:
        score += 15
        feedback_parts.append("Plant.kt: growZoneNumber type fixed to Int (15/15)")
        details['grow_zone_type_fixed'] = True
    elif grow_zone_still_string:
        feedback_parts.append("Plant.kt: growZoneNumber still declared as String (0/15)")
        details['grow_zone_type_fixed'] = False
    else:
        if result.get('plant_kt_changed', False):
            score += 8
            feedback_parts.append("Plant.kt: modified but growZoneNumber type unclear (8/15)")
            details['grow_zone_type_fixed'] = 'partial'
        else:
            feedback_parts.append("Plant.kt: not modified - type mismatch not fixed (0/15)")
            details['grow_zone_type_fixed'] = False

    # ================================================================
    # Criterion 3: PlantRepository.kt - syntax error fixed (15 pts)
    # ================================================================
    details['plant_repo_exists'] = bool(plant_repo_content)

    syntax_fixed = False

    if plant_repo_content:
        open_braces = plant_repo_content.count('{')
        close_braces = plant_repo_content.count('}')
        braces_balanced = (open_braces == close_braces)

        # Check that addPlant function body is properly closed before removePlant
        addplant_match = re.search(
            r'fun\s+addPlant\s*\(.*?\)\s*\{.*?\}[^}]*fun\s+removePlant',
            plant_repo_content,
            re.DOTALL
        )

        if braces_balanced and addplant_match:
            syntax_fixed = True
        elif braces_balanced:
            syntax_fixed = True

    if syntax_fixed:
        score += 15
        feedback_parts.append("PlantRepository.kt: syntax error fixed (15/15)")
        details['syntax_error_fixed'] = True
    elif result.get('plant_repo_changed', False):
        score += 8
        feedback_parts.append("PlantRepository.kt: modified but syntax fix unclear (8/15)")
        details['syntax_error_fixed'] = 'partial'
    else:
        feedback_parts.append("PlantRepository.kt: not modified - syntax error not fixed (0/15)")
        details['syntax_error_fixed'] = False

    # ================================================================
    # Criterion 4: build.gradle.kts - retrofit2 dependency added (15 pts)
    # ================================================================
    details['build_gradle_exists'] = bool(build_gradle_content)

    has_retrofit = bool(re.search(
        r'^\s*implementation\s*\(\s*"com\.squareup\.retrofit2:retrofit:[^"]+"\s*\)',
        build_gradle_content,
        re.MULTILINE
    ))

    has_gson_converter = bool(re.search(
        r'^\s*implementation\s*\(\s*"com\.squareup\.retrofit2:converter-gson:[^"]+"\s*\)',
        build_gradle_content,
        re.MULTILINE
    ))

    if has_retrofit:
        if has_gson_converter:
            score += 15
            feedback_parts.append("build.gradle.kts: retrofit2 + converter-gson dependencies added (15/15)")
            details['retrofit_dependency_added'] = True
            details['gson_converter_added'] = True
        else:
            score += 10
            feedback_parts.append("build.gradle.kts: retrofit2 added but converter-gson may be missing (10/15)")
            details['retrofit_dependency_added'] = True
            details['gson_converter_added'] = False
    elif result.get('build_gradle_changed', False):
        score += 5
        feedback_parts.append("build.gradle.kts: modified but retrofit2 dependency not found (5/15)")
        details['retrofit_dependency_added'] = False
    else:
        feedback_parts.append("build.gradle.kts: not modified - retrofit2 dependency not added (0/15)")
        details['retrofit_dependency_added'] = False

    # ================================================================
    # Criterion 5: Build succeeds (40 pts)
    # ================================================================
    build_success = result.get('build_success', False)

    # Also check by reading the gradle output log directly
    if not build_success:
        gradle_log = _read_text_from_env(copy_from_env, "/tmp/gradle_output.log")
        if gradle_log and "BUILD SUCCESSFUL" in gradle_log:
            build_success = True

    details['build_success'] = build_success

    if build_success:
        score += 40
        feedback_parts.append("Build: succeeded (40/40)")
    else:
        build_output = result.get('build_output', '')
        if 'BUILD FAILED' in build_output:
            error_count = build_output.lower().count('error')
            feedback_parts.append(f"Build: FAILED (~{error_count} errors remaining) (0/40)")
        else:
            feedback_parts.append("Build: did not succeed (0/40)")
        details['build_output_tail'] = build_output[-500:] if build_output else ''

    # ================================================================
    # Final scoring
    # ================================================================
    passed = score >= 70

    if passed:
        if score == 100:
            feedback_parts.append("All build errors fixed perfectly!")
        elif score >= 85:
            feedback_parts.append("Most build errors fixed successfully")
        else:
            feedback_parts.append("Build errors substantially addressed")
    else:
        feedback_parts.append("Task NOT completed - more fixes needed")

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
