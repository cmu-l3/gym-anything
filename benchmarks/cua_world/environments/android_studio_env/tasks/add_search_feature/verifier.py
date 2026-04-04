#!/usr/bin/env python3
"""
Verifier for add_search_feature task.

The agent must add search/filter functionality to SunflowerApp:
1. Add SearchView/EditText to activity_main.xml layout
2. Create a PlantFilter.kt utility class
3. Update MainActivity.kt with search handling logic
4. Add search-related string resources
5. Project compiles

Scoring (100 points total):
- Layout has search input widget: 15 pts
- PlantFilter.kt exists with filter logic: 20 pts
- MainActivity handles search input: 20 pts
- String resources for search: 10 pts
- Project compiles: 35 pts

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


def verify_add_search_feature(traj, env_info, task_info):
    """Verify search feature was added to SunflowerApp."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/AndroidStudioProjects/SunflowerApp')
    pkg_path = metadata.get('package_path', 'com/google/samples/apps/sunflower')
    src_dir = f"{project_dir}/app/src/main/java/{pkg_path}"
    res_dir = f"{project_dir}/app/src/main/res"

    main_kt = _read_text(copy_from_env, f"{src_dir}/MainActivity.kt")
    layout = _read_text(copy_from_env, f"{res_dir}/layout/activity_main.xml")
    strings = _read_text(copy_from_env, f"{res_dir}/values/strings.xml")

    # Try multiple possible filter file names
    filter_kt = ""
    for name in ["PlantFilter.kt", "SearchHelper.kt", "PlantSearch.kt", "FilterUtils.kt"]:
        filter_kt = _read_text(copy_from_env, f"{src_dir}/{name}")
        if filter_kt:
            break
        filter_kt = _read_text(copy_from_env, f"{src_dir}/data/{name}")
        if filter_kt:
            break
        filter_kt = _read_text(copy_from_env, f"{src_dir}/util/{name}")
        if filter_kt:
            break

    result = _read_json(copy_from_env, "/tmp/task_result.json")
    if not main_kt: main_kt = result.get('main_content', '')
    if not layout: layout = result.get('layout_content', '')
    if not strings: strings = result.get('strings_content', '')
    if not filter_kt: filter_kt = result.get('filter_content', '')

    score = 0
    feedback = []

    # GATE: no changes means no work
    any_change = (
        result.get('main_changed', False) or
        result.get('layout_changed', False) or
        result.get('filter_exists', False)
    )
    has_search_in_layout = bool(re.search(r'SearchView|search|EditText', layout, re.IGNORECASE))
    has_filter_class = bool(filter_kt)

    if not any_change and not has_search_in_layout and not has_filter_class:
        return {"passed": False, "score": 0, "feedback": "No changes detected"}

    # ================================================================
    # Criterion 1: Layout has search input (15 pts)
    # ================================================================
    try:
        has_searchview = bool(re.search(
            r'<\s*(androidx\.appcompat\.widget\.)?SearchView|<\s*EditText[^>]*search',
            layout,
            re.IGNORECASE
        ))
        has_search_id = bool(re.search(r'android:id="@\+id/\w*search\w*"', layout, re.IGNORECASE))
        has_query_hint = bool(re.search(r'queryHint|android:hint', layout))

        if has_searchview or (has_search_id and has_query_hint):
            score += 15
            feedback.append("Layout: search input found (15/15)")
        elif has_searchview or has_search_id:
            score += 10
            feedback.append("Layout: search input partial (10/15)")
        elif result.get('layout_changed', False):
            score += 3
            feedback.append("Layout: modified but no search widget found (3/15)")
        else:
            feedback.append("Layout: no search input (0/15)")
    except Exception as e:
        feedback.append(f"Layout: error ({e}) (0/15)")

    # ================================================================
    # Criterion 2: PlantFilter.kt exists with filter logic (20 pts)
    # ================================================================
    try:
        if filter_kt:
            has_class = bool(re.search(r'class\s+\w*(Filter|Search)\w*', filter_kt, re.IGNORECASE))
            has_filter_method = bool(re.search(r'fun\s+filter', filter_kt, re.IGNORECASE))
            has_plant_param = bool(re.search(r'List<Plant>', filter_kt))
            has_query_param = bool(re.search(r'query\s*:', filter_kt, re.IGNORECASE))
            uses_contains = bool(re.search(r'contains\s*\(', filter_kt, re.IGNORECASE))

            f_score = 0
            if has_class: f_score += 5
            if has_filter_method: f_score += 5
            if has_plant_param: f_score += 4
            if has_query_param: f_score += 3
            if uses_contains: f_score += 3

            score += min(f_score, 20)
            feedback.append(f"PlantFilter: found ({min(f_score, 20)}/20)")
        else:
            # Check if filter logic was inlined in MainActivity
            has_inline_filter = bool(re.search(r'\.filter\s*\{.*name.*contains', main_kt, re.DOTALL | re.IGNORECASE))
            if has_inline_filter:
                score += 12
                feedback.append("PlantFilter: logic inlined in MainActivity (12/20)")
            else:
                feedback.append("PlantFilter: not found (0/20)")
    except Exception as e:
        feedback.append(f"PlantFilter: error ({e}) (0/20)")

    # ================================================================
    # Criterion 3: MainActivity handles search (20 pts)
    # ================================================================
    try:
        has_search_listener = bool(re.search(
            r'setOnQueryTextListener|addTextChangedListener|TextWatcher|OnQueryTextListener',
            main_kt
        ))
        has_filter_call = bool(re.search(r'filter|search', main_kt, re.IGNORECASE))
        has_display_update = bool(re.search(r'displayPlants|adapter|notifyDataSetChanged|submitList', main_kt, re.IGNORECASE))
        has_findview_search = bool(re.search(r'findViewById.*search|binding.*search', main_kt, re.IGNORECASE))

        m_score = 0
        if has_search_listener: m_score += 8
        if has_filter_call: m_score += 5
        if has_display_update: m_score += 4
        if has_findview_search: m_score += 3

        score += min(m_score, 20)
        feedback.append(f"MainActivity search: ({min(m_score, 20)}/20)")
    except Exception as e:
        feedback.append(f"MainActivity: error ({e}) (0/20)")

    # ================================================================
    # Criterion 4: String resources (10 pts)
    # ================================================================
    try:
        has_search_string = bool(re.search(r'search', strings, re.IGNORECASE))
        has_hint_string = bool(re.search(r'hint|placeholder', strings, re.IGNORECASE))

        if has_search_string:
            score += 10
            feedback.append("Strings: search resource found (10/10)")
        elif result.get('strings_changed', False):
            score += 5
            feedback.append("Strings: modified (5/10)")
        else:
            feedback.append("Strings: no search resource (0/10)")
    except Exception as e:
        feedback.append(f"Strings: error ({e}) (0/10)")

    # ================================================================
    # Criterion 5: Project compiles (35 pts)
    # ================================================================
    try:
        build_success = result.get('build_success', False)
        if not build_success:
            gradle_log = _read_text(copy_from_env, "/tmp/gradle_output.log")
            if gradle_log and "BUILD SUCCESSFUL" in gradle_log:
                build_success = True

        if build_success:
            score += 35
            feedback.append("Build: succeeded (35/35)")
        else:
            feedback.append("Build: failed (0/35)")
    except Exception as e:
        feedback.append(f"Build: error ({e}) (0/35)")

    passed = score >= 70

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": " | ".join(feedback)
    }
