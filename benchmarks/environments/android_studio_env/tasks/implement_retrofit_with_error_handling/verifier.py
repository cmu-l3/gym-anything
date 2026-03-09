#!/usr/bin/env python3
"""
Verifier for implement_retrofit_with_error_handling task.

Task: Replace hardcoded crypto data with real Retrofit networking in CryptoTrackerApp.

Scoring (100 points total):
- Retrofit + OkHttp deps in build.gradle.kts: 15 pts
- INTERNET permission in AndroidManifest.xml: 10 pts
- @GET interface with @SerializedName DTO: 20 pts
- ApiClient / OkHttpClient singleton: 15 pts
- Error handling (at least 2 exception types): 15 pts
- Hardcoded data removed from Activity: 10 pts
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


def verify_implement_retrofit_with_error_handling(traj, env_info, task_info):
    """Verify Retrofit implementation in CryptoTrackerApp."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/AndroidStudioProjects/CryptoTrackerApp')
    pkg_path = metadata.get('package_path', 'com/example/cryptotracker')
    pkg_dir = f"{project_dir}/app/src/main/java/{pkg_path}"

    result = _read_json(copy_from_env, "/tmp/task_result.json")

    # Read file contents
    build_gradle = _read_text(copy_from_env, f"{project_dir}/app/build.gradle.kts")
    if not build_gradle:
        build_gradle = result.get('build_gradle_content', '')

    manifest = _read_text(copy_from_env, f"{project_dir}/app/src/main/AndroidManifest.xml")
    if not manifest:
        manifest = result.get('manifest_content', '')

    activity = _read_text(copy_from_env, f"{pkg_dir}/ui/CryptoListActivity.kt")
    if not activity:
        activity = result.get('activity_content', '')

    api_interface = result.get('api_interface_content', '')
    if not api_interface:
        # Try common locations
        for path in [
            f"{pkg_dir}/network/CoinGeckoApi.kt",
            f"{pkg_dir}/api/CoinGeckoApi.kt",
            f"{pkg_dir}/CoinGeckoApi.kt",
        ]:
            content = _read_text(copy_from_env, path)
            if content and '@GET' in content:
                api_interface = content
                break

    api_client = result.get('api_client_content', '')
    if not api_client:
        for path in [
            f"{pkg_dir}/network/ApiClient.kt",
            f"{pkg_dir}/api/ApiClient.kt",
            f"{pkg_dir}/ApiClient.kt",
        ]:
            content = _read_text(copy_from_env, path)
            if content and ('OkHttp' in content or 'Retrofit' in content):
                api_client = content
                break

    dto_content = result.get('dto_content', '')
    if not dto_content:
        for path in [
            f"{pkg_dir}/network/CoinResponse.kt",
            f"{pkg_dir}/model/CoinResponse.kt",
            f"{pkg_dir}/CoinResponse.kt",
        ]:
            content = _read_text(copy_from_env, path)
            if content and 'SerializedName' in content:
                dto_content = content
                break

    score = 0
    feedback = []

    # GATE: At least one file must have changed
    any_change = (
        result.get('build_gradle_changed', False) or
        result.get('activity_changed', False) or
        result.get('manifest_changed', False)
    )
    if not any_change and not result:
        return {"passed": False, "score": 0, "feedback": "No files modified"}

    # ================================================================
    # Criterion 1: Retrofit + OkHttp deps in build.gradle.kts (15 pts)
    # ================================================================
    try:
        has_retrofit = bool(re.search(r'retrofit', build_gradle, re.IGNORECASE))
        has_okhttp = bool(re.search(r'okhttp|logging.interceptor', build_gradle, re.IGNORECASE))
        has_gson = bool(re.search(r'gson|converter.gson', build_gradle, re.IGNORECASE))

        dep_count = sum([has_retrofit, has_okhttp, has_gson])
        if dep_count >= 3:
            score += 15
            feedback.append("Criterion1 Retrofit deps: all present (15/15)")
        elif dep_count >= 2:
            score += 10
            feedback.append(f"Criterion1 Retrofit deps: {dep_count}/3 (10/15)")
        elif dep_count >= 1:
            score += 6
            feedback.append(f"Criterion1 Retrofit deps: {dep_count}/3 (6/15)")
        elif result.get('build_gradle_changed', False):
            score += 3
            feedback.append("Criterion1 Retrofit deps: build.gradle changed (3/15)")
        else:
            feedback.append("Criterion1 Retrofit deps: not added (0/15)")
    except Exception as e:
        feedback.append(f"Criterion1: error ({e}) (0/15)")

    # ================================================================
    # Criterion 2: INTERNET permission in AndroidManifest.xml (10 pts)
    # ================================================================
    try:
        has_internet = bool(re.search(r'android\.permission\.INTERNET', manifest))
        if has_internet:
            score += 10
            feedback.append("Criterion2 INTERNET perm: present (10/10)")
        elif result.get('manifest_changed', False):
            score += 4
            feedback.append("Criterion2 INTERNET perm: manifest changed but no permission (4/10)")
        else:
            feedback.append("Criterion2 INTERNET perm: missing (0/10)")
    except Exception as e:
        feedback.append(f"Criterion2: error ({e}) (0/10)")

    # ================================================================
    # Criterion 3: @GET interface + @SerializedName DTO (20 pts)
    # ================================================================
    try:
        # Check all source for @GET annotation
        all_sources = api_interface + dto_content + activity + api_client
        has_get_annotation = bool(re.search(r'@GET\s*\(', all_sources))
        has_serialized_name = bool(re.search(r'@SerializedName', all_sources))
        has_interface = bool(re.search(r'interface\s+\w+Api', all_sources))
        has_query = bool(re.search(r'@Query', all_sources))

        api_score = 0
        if has_get_annotation:
            api_score += 8
        if has_serialized_name:
            api_score += 7
        if has_interface:
            api_score += 3
        if has_query:
            api_score += 2

        score += min(api_score, 20)
        feedback.append(f"Criterion3 @GET+DTO: ({min(api_score, 20)}/20) "
                        f"[@GET={has_get_annotation}, @SerializedName={has_serialized_name}, "
                        f"interface={has_interface}]")
    except Exception as e:
        feedback.append(f"Criterion3: error ({e}) (0/20)")

    # ================================================================
    # Criterion 4: ApiClient / OkHttpClient singleton (15 pts)
    # ================================================================
    try:
        has_okhttp_client = bool(re.search(r'OkHttpClient', api_client + activity + api_interface))
        has_retrofit_builder = bool(re.search(r'Retrofit\.Builder\(\)|Retrofit\.builder\(\)', api_client + activity))
        has_base_url = bool(re.search(r'baseUrl|base_url|coingecko', api_client + activity, re.IGNORECASE))
        has_companion_obj = bool(re.search(r'companion\s+object|object\s+\w+Client', api_client))

        client_score = 0
        if has_okhttp_client:
            client_score += 5
        if has_retrofit_builder:
            client_score += 5
        if has_base_url:
            client_score += 3
        if has_companion_obj:
            client_score += 2

        score += min(client_score, 15)
        feedback.append(f"Criterion4 ApiClient: ({min(client_score, 15)}/15) "
                        f"[OkHttp={has_okhttp_client}, Retrofit.Builder={has_retrofit_builder}]")
    except Exception as e:
        feedback.append(f"Criterion4: error ({e}) (0/15)")

    # ================================================================
    # Criterion 5: Error handling (15 pts)
    # ================================================================
    try:
        has_unknown_host = bool(re.search(r'UnknownHostException', activity))
        has_http_exception = bool(re.search(r'HttpException', activity))
        has_timeout = bool(re.search(r'SocketTimeoutException|TimeoutException', activity))
        has_try_catch = bool(re.search(r'\btry\s*\{', activity))
        has_catch = bool(re.search(r'\bcatch\s*\(', activity))
        has_on_failure = bool(re.search(r'onFailure|\.catch\s*\{|Result\.failure', activity))

        error_types = sum([has_unknown_host, has_http_exception, has_timeout])
        err_score = 0
        if error_types >= 3:
            err_score = 15
        elif error_types >= 2:
            err_score = 11
        elif error_types >= 1:
            err_score = 7
        elif has_try_catch and has_catch:
            err_score = 5
        elif has_on_failure:
            err_score = 4

        score += err_score
        feedback.append(f"Criterion5 Error handling: ({err_score}/15) "
                        f"[UnknownHost={has_unknown_host}, HTTP={has_http_exception}, "
                        f"Timeout={has_timeout}]")
    except Exception as e:
        feedback.append(f"Criterion5: error ({e}) (0/15)")

    # ================================================================
    # Criterion 6: Hardcoded data removed from Activity (10 pts)
    # ================================================================
    try:
        # Original hardcoded pattern: listOf(CoinData("bitcoin", ...
        has_hardcoded = bool(re.search(
            r'CoinData\s*\(\s*"bitcoin"|CoinData\s*\(\s*"ethereum"|listOf\s*\(\s*CoinData',
            activity
        ))
        activity_changed = result.get('activity_changed', False)

        if not has_hardcoded and activity_changed:
            score += 10
            feedback.append("Criterion6 Hardcoded removed: yes (10/10)")
        elif not has_hardcoded:
            score += 7
            feedback.append("Criterion6 Hardcoded removed: not found in activity (7/10)")
        else:
            feedback.append("Criterion6 Hardcoded removed: still present (0/10)")
    except Exception as e:
        feedback.append(f"Criterion6: error ({e}) (0/10)")

    # ================================================================
    # Criterion 7: Project compiles (15 pts)
    # ================================================================
    try:
        build_success = result.get('build_success', False)
        if not build_success:
            gradle_log = _read_text(copy_from_env, "/tmp/gradle_output.log")
            if gradle_log and "BUILD SUCCESSFUL" in gradle_log:
                build_success = True

        if build_success:
            score += 15
            feedback.append("Criterion7 Build: succeeded (15/15)")
        else:
            feedback.append("Criterion7 Build: failed (0/15)")
    except Exception as e:
        feedback.append(f"Criterion7: error ({e}) (0/15)")

    passed = score >= 70

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": " | ".join(feedback)
    }
