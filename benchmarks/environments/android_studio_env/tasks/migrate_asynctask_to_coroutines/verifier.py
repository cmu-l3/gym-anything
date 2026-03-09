#!/usr/bin/env python3
"""
Verifier for migrate_asynctask_to_coroutines task.

Task: Replace 4 AsyncTask classes with Kotlin Coroutines in FeedReaderApp.

Scoring (100 points total):
- Coroutines dependency in build.gradle.kts: 15 pts
- AsyncTask classes removed/replaced: 25 pts
- lifecycleScope.launch or coroutine scope in Activities: 20 pts
- Repository suspend functions / withContext: 20 pts
- Project compiles successfully: 20 pts

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


def verify_migrate_asynctask_to_coroutines(traj, env_info, task_info):
    """Verify AsyncTask migration to Kotlin Coroutines in FeedReaderApp."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/AndroidStudioProjects/FeedReaderApp')
    pkg_path = metadata.get('package_path', 'com/example/feedreader')
    pkg_dir = f"{project_dir}/app/src/main/java/{pkg_path}"

    result = _read_json(copy_from_env, "/tmp/task_result.json")

    # Read key files
    build_gradle = _read_text(copy_from_env, f"{project_dir}/app/build.gradle.kts")
    if not build_gradle:
        build_gradle = result.get('build_gradle_content', '')

    fetch_task = _read_text(copy_from_env, f"{pkg_dir}/task/FetchArticlesTask.kt")
    if not fetch_task:
        fetch_task = result.get('fetch_task_content', '')

    save_task = _read_text(copy_from_env, f"{pkg_dir}/task/SaveArticleTask.kt")
    if not save_task:
        save_task = result.get('save_task_content', '')

    search_task = _read_text(copy_from_env, f"{pkg_dir}/task/SearchArticlesTask.kt")
    if not search_task:
        search_task = result.get('search_task_content', '')

    load_task = _read_text(copy_from_env, f"{pkg_dir}/task/LoadSavedTask.kt")
    if not load_task:
        load_task = result.get('load_task_content', '')

    feed_act = _read_text(copy_from_env, f"{pkg_dir}/ui/FeedActivity.kt")
    if not feed_act:
        feed_act = result.get('feed_activity_content', '')

    search_act = _read_text(copy_from_env, f"{pkg_dir}/ui/SearchActivity.kt")
    if not search_act:
        search_act = result.get('search_activity_content', '')

    repo = _read_text(copy_from_env, f"{pkg_dir}/repository/ArticleRepository.kt")
    if not repo:
        repo = result.get('repository_content', '')

    score = 0
    feedback = []

    # GATE: At least something must have changed
    any_change = (
        result.get('build_gradle_changed', False) or
        result.get('feed_activity_changed', False) or
        result.get('fetch_task_changed', False) or
        result.get('repository_changed', False)
    )
    if not any_change and not result:
        return {"passed": False, "score": 0, "feedback": "No files modified"}

    # ================================================================
    # Criterion 1: Coroutines dependency in build.gradle.kts (15 pts)
    # ================================================================
    try:
        has_coroutines = bool(re.search(
            r'kotlinx[_-]coroutines[_-]android|kotlinx\.coroutines',
            build_gradle, re.IGNORECASE
        ))
        has_lifecycle = bool(re.search(
            r'lifecycle[_-]runtime[_-]ktx|lifecycle[_-]viewmodel[_-]ktx',
            build_gradle, re.IGNORECASE
        ))

        if has_coroutines:
            score += 15
            feedback.append("Criterion1 Coroutines dep: found (15/15)")
        elif has_lifecycle:
            score += 8
            feedback.append("Criterion1 Coroutines dep: only lifecycle-ktx (8/15)")
        elif result.get('build_gradle_changed', False):
            score += 4
            feedback.append("Criterion1 Coroutines dep: build.gradle changed (4/15)")
        else:
            feedback.append("Criterion1 Coroutines dep: not added (0/15)")
    except Exception as e:
        feedback.append(f"Criterion1: error ({e}) (0/15)")

    # ================================================================
    # Criterion 2: AsyncTask classes removed/replaced (25 pts)
    # ================================================================
    try:
        # Check how many AsyncTask classes still extend AsyncTask
        all_task_files = fetch_task + save_task + search_task + load_task

        # Count AsyncTask usages remaining
        asynctask_extends = len(re.findall(r':\s*AsyncTask\s*<|extends\s+AsyncTask', all_task_files))
        asynctask_suppress = len(re.findall(r'@Suppress.*DEPRECATION.*AsyncTask|@Suppress.*deprecation', all_task_files, re.IGNORECASE))

        # Files changed/removed
        tasks_changed = sum([
            result.get('fetch_task_changed', False),
            result.get('save_task_changed', False),
            result.get('search_task_changed', False),
            result.get('load_task_changed', False),
        ])

        # Count AsyncTask execute() calls still in Activities
        asynctask_execute = len(re.findall(r'Task\(.*\)\.execute\(|\.execute\(', feed_act + search_act))

        at_score = 0
        if asynctask_extends == 0 and tasks_changed >= 3:
            at_score = 25
        elif asynctask_extends == 0 and tasks_changed >= 1:
            at_score = 18
        elif asynctask_extends <= 1 and tasks_changed >= 2:
            at_score = 15
        elif tasks_changed >= 2:
            at_score = 10
        elif tasks_changed >= 1:
            at_score = 5

        score += at_score
        feedback.append(f"Criterion2 AsyncTask removed: ({at_score}/25) "
                        f"[extends_remaining={asynctask_extends}, tasks_changed={tasks_changed}]")
    except Exception as e:
        feedback.append(f"Criterion2: error ({e}) (0/25)")

    # ================================================================
    # Criterion 3: lifecycleScope.launch in Activities (20 pts)
    # ================================================================
    try:
        activities = feed_act + search_act
        has_lifecycle_scope = bool(re.search(r'lifecycleScope\.launch|viewModelScope\.launch', activities))
        has_launch = bool(re.search(r'\.launch\s*\{|launch\s*\(', activities))
        has_coroutine_import = bool(re.search(
            r'import.*kotlinx\.coroutines|import.*lifecycleScope|import.*launch',
            activities
        ))
        has_withcontext = bool(re.search(r'withContext\s*\(', activities + repo))

        ls_score = 0
        if has_lifecycle_scope:
            ls_score += 12
        elif has_launch and has_coroutine_import:
            ls_score += 8
        elif has_launch:
            ls_score += 5
        if has_withcontext:
            ls_score += 8

        score += min(ls_score, 20)
        feedback.append(f"Criterion3 lifecycleScope: ({min(ls_score, 20)}/20) "
                        f"[lifecycleScope={has_lifecycle_scope}, withContext={has_withcontext}]")
    except Exception as e:
        feedback.append(f"Criterion3: error ({e}) (0/20)")

    # ================================================================
    # Criterion 4: Repository uses suspend / withContext (20 pts)
    # ================================================================
    try:
        has_suspend = bool(re.search(r'\bsuspend\s+fun\b', repo))
        has_withcontext_repo = bool(re.search(r'withContext\s*\(Dispatchers', repo))
        has_dispatchers = bool(re.search(r'Dispatchers\.IO|Dispatchers\.Default', repo))
        repo_changed = result.get('repository_changed', False)

        r_score = 0
        if has_suspend and has_withcontext_repo:
            r_score = 20
        elif has_suspend and has_dispatchers:
            r_score = 16
        elif has_suspend:
            r_score = 12
        elif has_withcontext_repo or has_dispatchers:
            r_score = 8
        elif repo_changed:
            r_score = 4

        score += r_score
        feedback.append(f"Criterion4 Repository suspend: ({r_score}/20) "
                        f"[suspend={has_suspend}, withContext={has_withcontext_repo}]")
    except Exception as e:
        feedback.append(f"Criterion4: error ({e}) (0/20)")

    # ================================================================
    # Criterion 5: Project compiles (20 pts)
    # ================================================================
    try:
        build_success = result.get('build_success', False)
        if not build_success:
            gradle_log = _read_text(copy_from_env, "/tmp/gradle_output.log")
            if gradle_log and "BUILD SUCCESSFUL" in gradle_log:
                build_success = True

        if build_success:
            score += 20
            feedback.append("Criterion5 Build: succeeded (20/20)")
        else:
            feedback.append("Criterion5 Build: failed (0/20)")
    except Exception as e:
        feedback.append(f"Criterion5: error ({e}) (0/20)")

    passed = score >= 70

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": " | ".join(feedback)
    }
