#!/usr/bin/env python3
"""
Verifier for implement_hilt_dependency_injection task.

Task: Refactor ExpenseTrackerApp to use Dagger Hilt for DI.

Scoring (100 points total):
- Hilt plugin + dependency in build.gradle.kts: 15 pts
- @HiltAndroidApp on Application class: 15 pts
- @Module class with @Provides methods: 20 pts
- @AndroidEntryPoint on Activities: 15 pts
- @Inject fields replace manual construction: 20 pts
- Project compiles successfully: 15 pts

Pass threshold: 70/100
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _read_text(copy_from_env, path):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
    try:
        copy_from_env(path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except Exception:
        return ""
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def _read_json(copy_from_env, path):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def _find_kt_files(copy_from_env, pkg_dir):
    """Try to find Kotlin files in the project directory."""
    files = {}
    candidates = [
        f"{pkg_dir}/ExpenseApp.kt",
        f"{pkg_dir}/ui/MainActivity.kt",
        f"{pkg_dir}/ui/AddExpenseActivity.kt",
        f"{pkg_dir}/ui/SettingsActivity.kt",
        f"{pkg_dir}/di/AppModule.kt",
        f"{pkg_dir}/AppModule.kt",
        f"{pkg_dir}/di/ExpenseModule.kt",
    ]
    for path in candidates:
        content = _read_text(copy_from_env, path)
        if content:
            files[os.path.basename(path)] = content
    return files


def verify_implement_hilt_dependency_injection(traj, env_info, task_info):
    """Verify Hilt DI implementation in ExpenseTrackerApp."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/AndroidStudioProjects/ExpenseTrackerApp')
    pkg_path = metadata.get('package_path', 'com/example/expensetracker')
    pkg_dir = f"{project_dir}/app/src/main/java/{pkg_path}"

    # Read result JSON
    result = _read_json(copy_from_env, "/tmp/task_result.json")

    # Gather file contents (prefer direct read, fall back to result JSON)
    build_gradle = _read_text(copy_from_env, f"{project_dir}/app/build.gradle.kts")
    if not build_gradle:
        build_gradle = result.get('build_gradle_content', '')

    app_kt = _read_text(copy_from_env, f"{pkg_dir}/ExpenseApp.kt")
    if not app_kt:
        app_kt = result.get('app_kt_content', '')

    main_kt = _read_text(copy_from_env, f"{pkg_dir}/ui/MainActivity.kt")
    if not main_kt:
        main_kt = result.get('main_activity_content', '')

    add_kt = _read_text(copy_from_env, f"{pkg_dir}/ui/AddExpenseActivity.kt")
    if not add_kt:
        add_kt = result.get('add_expense_content', '')

    settings_kt = _read_text(copy_from_env, f"{pkg_dir}/ui/SettingsActivity.kt")
    if not settings_kt:
        settings_kt = result.get('settings_activity_content', '')

    # Look for module file — may be in di/ subfolder or elsewhere
    module_kt = result.get('module_content', '')
    if not module_kt:
        for candidate_path in [
            f"{pkg_dir}/di/AppModule.kt",
            f"{pkg_dir}/AppModule.kt",
            f"{pkg_dir}/di/ExpenseModule.kt",
            f"{pkg_dir}/di/HiltModule.kt",
        ]:
            content = _read_text(copy_from_env, candidate_path)
            if content and '@Module' in content:
                module_kt = content
                break
    # Also search any changed kotlin file in result for @Module
    if not module_kt:
        for key in ['main_activity_content', 'add_expense_content', 'settings_activity_content']:
            content = result.get(key, '')
            if '@Module' in content:
                module_kt = content
                break

    score = 0
    feedback = []

    # GATE: At least one file must have changed
    any_change = (
        result.get('build_gradle_changed', False) or
        result.get('app_kt_changed', False) or
        result.get('main_activity_changed', False) or
        result.get('add_expense_changed', False) or
        result.get('settings_activity_changed', False)
    )
    if not any_change and not result:
        return {"passed": False, "score": 0, "feedback": "No files modified — nothing to score"}

    # ================================================================
    # Criterion 1: Hilt plugin + dependency in build.gradle.kts (15 pts)
    # ================================================================
    try:
        has_hilt_plugin = bool(re.search(
            r'com\.google\.dagger\.hilt\.android|dagger\.hilt',
            build_gradle, re.IGNORECASE
        ))
        has_hilt_dep = bool(re.search(
            r'hilt[_-]android|dagger[_-]hilt',
            build_gradle, re.IGNORECASE
        ))
        has_kapt = bool(re.search(r'kapt|ksp', build_gradle, re.IGNORECASE))

        if has_hilt_plugin and has_hilt_dep:
            score += 15
            feedback.append("Criterion1 Hilt gradle: plugin+dep present (15/15)")
        elif has_hilt_plugin or has_hilt_dep:
            score += 8
            feedback.append("Criterion1 Hilt gradle: partial (8/15)")
        elif result.get('build_gradle_changed', False):
            score += 4
            feedback.append("Criterion1 Hilt gradle: build.gradle changed (4/15)")
        else:
            feedback.append("Criterion1 Hilt gradle: no Hilt in build.gradle (0/15)")
    except Exception as e:
        feedback.append(f"Criterion1: error ({e}) (0/15)")

    # ================================================================
    # Criterion 2: @HiltAndroidApp on Application class (15 pts)
    # ================================================================
    try:
        has_hilt_app = bool(re.search(r'@HiltAndroidApp', app_kt))
        has_app_class = bool(re.search(r'class\s+\w+\s*:\s*Application', app_kt))
        # Also check if annotation is in any scanned file
        all_sources = main_kt + add_kt + settings_kt + module_kt
        has_hilt_app_elsewhere = bool(re.search(r'@HiltAndroidApp', all_sources))

        if has_hilt_app and has_app_class:
            score += 15
            feedback.append("Criterion2 @HiltAndroidApp: correctly annotated (15/15)")
        elif has_hilt_app or has_hilt_app_elsewhere:
            score += 10
            feedback.append("Criterion2 @HiltAndroidApp: annotation found (10/15)")
        elif result.get('app_kt_changed', False):
            score += 5
            feedback.append("Criterion2 @HiltAndroidApp: App.kt changed (5/15)")
        else:
            feedback.append("Criterion2 @HiltAndroidApp: not found (0/15)")
    except Exception as e:
        feedback.append(f"Criterion2: error ({e}) (0/15)")

    # ================================================================
    # Criterion 3: @Module class with @Provides methods (20 pts)
    # ================================================================
    try:
        # Check all source files for @Module annotation
        all_sources_for_module = main_kt + add_kt + settings_kt + app_kt + module_kt
        has_module = bool(re.search(r'@Module', all_sources_for_module))
        has_install_in = bool(re.search(r'@InstallIn', all_sources_for_module))
        provides_count = len(re.findall(r'@Provides', all_sources_for_module))
        has_singleton = bool(re.search(r'@Singleton', all_sources_for_module))

        m_score = 0
        if has_module:
            m_score += 8
        if has_install_in:
            m_score += 4
        if provides_count >= 2:
            m_score += 6
        elif provides_count >= 1:
            m_score += 3
        if has_singleton:
            m_score += 2

        score += min(m_score, 20)
        feedback.append(f"Criterion3 @Module: ({min(m_score, 20)}/20) "
                        f"[module={has_module}, installIn={has_install_in}, provides={provides_count}]")
    except Exception as e:
        feedback.append(f"Criterion3: error ({e}) (0/20)")

    # ================================================================
    # Criterion 4: @AndroidEntryPoint on Activities (15 pts)
    # ================================================================
    try:
        main_has_entry = bool(re.search(r'@AndroidEntryPoint', main_kt))
        add_has_entry = bool(re.search(r'@AndroidEntryPoint', add_kt))
        settings_has_entry = bool(re.search(r'@AndroidEntryPoint', settings_kt))
        entry_count = sum([main_has_entry, add_has_entry, settings_has_entry])

        if entry_count == 3:
            score += 15
            feedback.append("Criterion4 @AndroidEntryPoint: all 3 Activities (15/15)")
        elif entry_count == 2:
            score += 10
            feedback.append("Criterion4 @AndroidEntryPoint: 2 Activities (10/15)")
        elif entry_count == 1:
            score += 5
            feedback.append("Criterion4 @AndroidEntryPoint: 1 Activity (5/15)")
        else:
            feedback.append("Criterion4 @AndroidEntryPoint: none found (0/15)")
    except Exception as e:
        feedback.append(f"Criterion4: error ({e}) (0/15)")

    # ================================================================
    # Criterion 5: @Inject fields replace manual construction (20 pts)
    # ================================================================
    try:
        # Count @Inject usages across activities
        inject_in_main = len(re.findall(r'@Inject', main_kt))
        inject_in_add = len(re.findall(r'@Inject', add_kt))
        inject_in_settings = len(re.findall(r'@Inject', settings_kt))
        total_inject = inject_in_main + inject_in_add + inject_in_settings

        # Check that manual construction is removed
        manual_pattern = r'CurrencyService\.getInstance\(\)|ExpenseRepository\(application|NotificationService\(application|SettingsManager\(application'
        manual_in_main = bool(re.search(manual_pattern, main_kt))
        manual_in_add = bool(re.search(manual_pattern, add_kt))
        manual_in_settings = bool(re.search(manual_pattern, settings_kt))
        manual_count = sum([manual_in_main, manual_in_add, manual_in_settings])

        i_score = 0
        if total_inject >= 6:  # 2+ injections per activity
            i_score += 10
        elif total_inject >= 3:
            i_score += 6
        elif total_inject >= 1:
            i_score += 3

        if manual_count == 0 and total_inject >= 3:
            i_score += 10
        elif manual_count <= 1:
            i_score += 5
        # partial credit for removing some manual construction

        score += min(i_score, 20)
        feedback.append(f"Criterion5 @Inject: ({min(i_score, 20)}/20) "
                        f"[inject={total_inject}, manual_remaining={manual_count}]")
    except Exception as e:
        feedback.append(f"Criterion5: error ({e}) (0/20)")

    # ================================================================
    # Criterion 6: Project compiles (15 pts)
    # ================================================================
    try:
        build_success = result.get('build_success', False)
        if not build_success:
            gradle_log = _read_text(copy_from_env, "/tmp/gradle_output.log")
            if gradle_log and "BUILD SUCCESSFUL" in gradle_log:
                build_success = True

        if build_success:
            score += 15
            feedback.append("Criterion6 Build: succeeded (15/15)")
        else:
            feedback.append("Criterion6 Build: failed (0/15)")
    except Exception as e:
        feedback.append(f"Criterion6: error ({e}) (0/15)")

    passed = score >= 70

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": " | ".join(feedback)
    }
