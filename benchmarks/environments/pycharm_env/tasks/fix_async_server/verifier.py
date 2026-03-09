import json
import os
import tempfile


def verify_fix_async_server(traj, env_info, task_info):
    """
    Verify that the agent fixed all 4 async/concurrency bugs:
      Bug 1 (25 pts): time.sleep replaced with await asyncio.sleep in worker.py
      Bug 2 (25 pts): run_workers uses asyncio.gather for concurrency (not sequential loop)
      Bug 3 (25 pts): JobRegistry.update_status uses asyncio.Lock to prevent race conditions
      Bug 4 (25 pts): fetch_job_status uses await response.json()
    Pass threshold: 65 (must fix at least 2-3 bugs)
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env not available",
        }

    task_name = "fix_async_server"
    result_path = f"/tmp/{task_name}_result.json"

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env(result_path, tmp_path)
            with open(tmp_path, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export_result.sh may not have run",
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result JSON malformed: {e}",
        }

    score = 0
    parts = []
    issues = []

    # Bug 1: blocking sleep
    if result.get("bug1_blocking_sleep_fixed", False):
        score += 25
        parts.append("Bug 1 fixed: time.sleep replaced with await asyncio.sleep (25/25)")
    else:
        issues.append(
            "Bug 1 NOT fixed: process_job still uses time.sleep(duration) which blocks the "
            "entire event loop. Replace with: await asyncio.sleep(duration)"
        )

    # Bug 2: sequential workers
    if result.get("bug2_sequential_workers_fixed", False):
        score += 25
        parts.append("Bug 2 fixed: run_workers uses asyncio.gather for concurrent execution (25/25)")
    else:
        issues.append(
            "Bug 2 NOT fixed: run_workers still awaits jobs sequentially in a for loop. "
            "Replace with: await asyncio.gather(*[process_job(j, registry) for j in jobs])"
        )

    # Bug 3: missing lock
    if result.get("bug3_registry_lock_added", False):
        score += 25
        parts.append("Bug 3 fixed: JobRegistry.update_status uses asyncio.Lock (25/25)")
    else:
        issues.append(
            "Bug 3 NOT fixed: JobRegistry has no asyncio.Lock — concurrent calls to "
            "update_status race and produce incorrect status counts. "
            "Add self._lock = asyncio.Lock() and use 'async with self._lock' in update_status."
        )

    # Bug 4: missing await on response.json()
    if result.get("bug4_await_response_json_fixed", False):
        score += 25
        parts.append("Bug 4 fixed: fetch_job_status awaits response.json() (25/25)")
    else:
        issues.append(
            "Bug 4 NOT fixed: fetch_job_status calls response.json() without await — "
            "returns a coroutine object instead of the dict. "
            "Fix: data = await response.json()"
        )

    score = min(score, 100)
    passed = score >= 65

    tests_passed = result.get("tests_passed", 0)
    tests_failed = result.get("tests_failed", 0)
    summary = f"Score: {score}/100 | Tests: {tests_passed} passing, {tests_failed} failing"

    all_feedback = parts + issues
    return {
        "passed": passed,
        "score": score,
        "feedback": f"{summary} | " + " | ".join(all_feedback) if all_feedback else summary,
    }
