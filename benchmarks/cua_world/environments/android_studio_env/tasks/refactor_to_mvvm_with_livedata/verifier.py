#!/usr/bin/env python3
"""
Verifier for refactor_to_mvvm_with_livedata task.

Task: Refactor TaskManagerApp God Activities to MVVM architecture.

Scoring (100 points total):
- ViewModel deps in build.gradle.kts: 10 pts
- At least one ViewModel class created: 20 pts
- LiveData<> fields exposed from ViewModel: 20 pts
- Activities observe() LiveData: 15 pts
- Repository NOT directly instantiated in Activities: 20 pts
- Project compiles: 15 pts

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


def verify_refactor_to_mvvm_with_livedata(traj, env_info, task_info):
    """Verify MVVM refactoring in TaskManagerApp."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/AndroidStudioProjects/TaskManagerApp')
    pkg_path = metadata.get('package_path', 'com/example/taskmanager')
    pkg_dir = f"{project_dir}/app/src/main/java/{pkg_path}"

    result = _read_json(copy_from_env, "/tmp/task_result.json")

    # Read file contents
    build_gradle = _read_text(copy_from_env, f"{project_dir}/app/build.gradle.kts")
    if not build_gradle:
        build_gradle = result.get('build_gradle_content', '')

    list_act = _read_text(copy_from_env, f"{pkg_dir}/ui/TaskListActivity.kt")
    if not list_act:
        list_act = result.get('list_activity_content', '')

    add_act = _read_text(copy_from_env, f"{pkg_dir}/ui/AddTaskActivity.kt")
    if not add_act:
        add_act = result.get('add_activity_content', '')

    detail_act = _read_text(copy_from_env, f"{pkg_dir}/ui/TaskDetailActivity.kt")
    if not detail_act:
        detail_act = result.get('detail_activity_content', '')

    # Get ViewModel contents from result (export scans for *ViewModel*.kt)
    vm_contents = result.get('viewmodel_contents', '')
    vm_count = result.get('viewmodel_count', 0)

    # Also try direct reads for common ViewModel paths
    if not vm_contents:
        for candidate in [
            f"{pkg_dir}/viewmodel/TaskListViewModel.kt",
            f"{pkg_dir}/viewmodel/AddTaskViewModel.kt",
            f"{pkg_dir}/viewmodel/TaskDetailViewModel.kt",
            f"{pkg_dir}/ui/TaskListViewModel.kt",
            f"{pkg_dir}/TaskListViewModel.kt",
        ]:
            content = _read_text(copy_from_env, candidate)
            if content and 'ViewModel' in content:
                vm_contents += f"\n{content}"
                vm_count += 1

    all_activities = list_act + add_act + detail_act

    score = 0
    feedback = []

    # GATE: At least one file must have changed
    any_change = (
        result.get('build_gradle_changed', False) or
        result.get('list_activity_changed', False) or
        result.get('add_activity_changed', False) or
        result.get('detail_activity_changed', False)
    )
    if not any_change and not result:
        return {"passed": False, "score": 0, "feedback": "No files modified"}

    # ================================================================
    # Criterion 1: ViewModel deps in build.gradle.kts (10 pts)
    # ================================================================
    try:
        has_lifecycle_vm = bool(re.search(
            r'lifecycle[_-]viewmodel|lifecycle[_-]livedata',
            build_gradle, re.IGNORECASE
        ))
        has_activity_ktx = bool(re.search(r'activity[_-]ktx', build_gradle, re.IGNORECASE))
        has_viewmodel_ktx = bool(re.search(r'viewmodel[_-]ktx', build_gradle, re.IGNORECASE))

        if has_lifecycle_vm:
            score += 10
            feedback.append("Criterion1 ViewModel deps: present (10/10)")
        elif result.get('build_gradle_changed', False):
            score += 4
            feedback.append("Criterion1 ViewModel deps: build.gradle changed (4/10)")
        else:
            feedback.append("Criterion1 ViewModel deps: missing (0/10)")
    except Exception as e:
        feedback.append(f"Criterion1: error ({e}) (0/10)")

    # ================================================================
    # Criterion 2: At least one ViewModel class created (20 pts)
    # ================================================================
    try:
        # Check all sources for ViewModel subclass
        all_sources = vm_contents + list_act + add_act + detail_act
        vm_class_matches = re.findall(
            r'class\s+\w+ViewModel\s*(?:\([^)]*\))?\s*:\s*ViewModel\s*\(\s*\)',
            all_sources
        )
        vm_count_from_src = len(vm_class_matches)
        # Also check for extends ViewModel
        viewmodel_extends = bool(re.search(r':\s*ViewModel\(\)', all_sources))

        if vm_count_from_src >= 3 or (vm_count >= 3 and viewmodel_extends):
            score += 20
            feedback.append(f"Criterion2 ViewModel classes: {max(vm_count_from_src, vm_count)} found (20/20)")
        elif vm_count_from_src >= 2 or (vm_count >= 2 and viewmodel_extends):
            score += 16
            feedback.append(f"Criterion2 ViewModel classes: {max(vm_count_from_src, vm_count)} found (16/20)")
        elif vm_count_from_src >= 1 or viewmodel_extends:
            score += 10
            feedback.append(f"Criterion2 ViewModel classes: 1 found (10/20)")
        elif vm_count >= 1:
            score += 7
            feedback.append("Criterion2 ViewModel classes: file found but no ViewModel subclass (7/20)")
        else:
            feedback.append("Criterion2 ViewModel classes: none found (0/20)")
    except Exception as e:
        feedback.append(f"Criterion2: error ({e}) (0/20)")

    # ================================================================
    # Criterion 3: LiveData<> fields in ViewModel (20 pts)
    # ================================================================
    try:
        has_live_data = bool(re.search(r'LiveData\s*<|MutableLiveData\s*<', vm_contents + list_act + add_act))
        has_mutable = bool(re.search(r'MutableLiveData\s*<', vm_contents))
        livedata_count = len(re.findall(r'LiveData\s*<', vm_contents))

        ld_score = 0
        if has_live_data and has_mutable:
            ld_score = 20
        elif has_live_data:
            ld_score = 14
        elif bool(re.search(r'LiveData', vm_contents + all_activities)):
            ld_score = 8

        score += ld_score
        feedback.append(f"Criterion3 LiveData: ({ld_score}/20) "
                        f"[LiveData={has_live_data}, MutableLiveData={has_mutable}, count={livedata_count}]")
    except Exception as e:
        feedback.append(f"Criterion3: error ({e}) (0/20)")

    # ================================================================
    # Criterion 4: Activities observe() LiveData (15 pts)
    # ================================================================
    try:
        observe_in_list = bool(re.search(r'\.observe\s*\(', list_act))
        observe_in_add = bool(re.search(r'\.observe\s*\(', add_act))
        observe_in_detail = bool(re.search(r'\.observe\s*\(', detail_act))
        total_observe = sum([observe_in_list, observe_in_add, observe_in_detail])

        has_viewmodels_delegate = bool(re.search(r'by\s+viewModels\(\)', all_activities))
        has_viewmodel_provider = bool(re.search(r'ViewModelProvider', all_activities))

        obs_score = 0
        if total_observe >= 3:
            obs_score = 12
        elif total_observe >= 2:
            obs_score = 9
        elif total_observe >= 1:
            obs_score = 6
        if has_viewmodels_delegate or has_viewmodel_provider:
            obs_score += 3

        score += min(obs_score, 15)
        feedback.append(f"Criterion4 observe(): ({min(obs_score, 15)}/15) "
                        f"[activities_observing={total_observe}, viewModels()={has_viewmodels_delegate}]")
    except Exception as e:
        feedback.append(f"Criterion4: error ({e}) (0/15)")

    # ================================================================
    # Criterion 5: Repository NOT directly in Activities (20 pts)
    # ================================================================
    try:
        # Original bad pattern: private val repository = TaskRepository()
        repo_in_list = bool(re.search(r'val\s+repository\s*=\s*TaskRepository\(\)', list_act))
        repo_in_add = bool(re.search(r'val\s+repository\s*=\s*TaskRepository\(\)', add_act))
        repo_in_detail = bool(re.search(r'val\s+repository\s*=\s*TaskRepository\(\)', detail_act))
        repos_in_activities = sum([repo_in_list, repo_in_add, repo_in_detail])

        # Also check that activities changed
        acts_changed = sum([
            result.get('list_activity_changed', False),
            result.get('add_activity_changed', False),
            result.get('detail_activity_changed', False),
        ])

        if repos_in_activities == 0 and acts_changed >= 2:
            score += 20
            feedback.append("Criterion5 Repository out of Activities: all removed (20/20)")
        elif repos_in_activities == 0 and acts_changed >= 1:
            score += 15
            feedback.append("Criterion5 Repository out of Activities: removed, 1+ act changed (15/20)")
        elif repos_in_activities == 0:
            score += 10
            feedback.append("Criterion5 Repository out of Activities: not found (10/20)")
        elif repos_in_activities == 1:
            score += 12
            feedback.append(f"Criterion5 Repository out of Activities: 1 remaining (12/20)")
        elif repos_in_activities == 2:
            score += 6
            feedback.append(f"Criterion5 Repository out of Activities: 2 remaining (6/20)")
        else:
            feedback.append("Criterion5 Repository out of Activities: all 3 still in Activities (0/20)")
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
