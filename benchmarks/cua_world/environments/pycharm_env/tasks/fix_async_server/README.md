# fix_async_server

## Overview

**Occupation**: Software Developers
**Industry**: Computer Systems Design and Related Services
**Difficulty**: Very Hard

A Python asyncio-based job scheduling service (`async_scheduler`) that tracks package routing jobs is broken in production. Jobs that should run concurrently are running sequentially, some jobs never complete, and under load the job status counters become inconsistent. The CI pipeline is failing.

The agent must run the failing tests, identify all async/concurrency bugs in the service code, and fix them. No information about which bugs exist or where they are is given.

---

## Goal

All tests in `tests/` must pass with `pytest exit code 0`.

The project is pre-opened in PyCharm. The agent must NOT modify the test files or change the public API (function signatures in `server/`).

---

## Starting State

The project is at `/home/ga/PycharmProjects/async_scheduler/` and contains:

```
async_scheduler/
├── server/
│   ├── models.py      # Job, JobStatus dataclasses — no bugs
│   ├── registry.py    # Bug 3: no asyncio.Lock in update_status
│   ├── worker.py      # Bug 1: time.sleep; Bug 2: sequential loop instead of gather
│   └── client.py      # Bug 4: missing await on response.json()
├── tests/
│   ├── conftest.py
│   ├── test_registry.py  # 4 tests — test_concurrent_updates_preserve_counts fails
│   ├── test_worker.py    # 5 tests — test_run_workers_concurrent_timing,
│   │                     #           test_process_job_does_not_block_event_loop fail
│   └── test_client.py    # 2 tests — test_fetch_job_status_returns_dict fails
├── pytest.ini            # asyncio_mode = auto
└── requirements.txt
```

---

## Bugs (Ground Truth — do not reveal in task description)

| Bug | File | Location | Description | Fix |
|-----|------|----------|-------------|-----|
| 1 | `server/worker.py` | `process_job` | `time.sleep(duration)` blocks the event loop | `await asyncio.sleep(duration)` |
| 2 | `server/worker.py` | `run_workers` | Sequential `for job in jobs: await process_job(...)` | `await asyncio.gather(*[process_job(j, registry) for j in jobs])` |
| 3 | `server/registry.py` | `JobRegistry.update_status` | No `asyncio.Lock`; concurrent calls corrupt status counters | Add `self._lock = asyncio.Lock()` and `async with self._lock` |
| 4 | `server/client.py` | `fetch_job_status` | `data = response.json()` — missing `await` | `data = await response.json()` |

---

## Verification Strategy

**Criterion 1 (25 pts)**: `bug1_blocking_sleep_fixed` — `time.sleep` removed; `await asyncio.sleep` present; `test_process_job_does_not_block_event_loop` passes
**Criterion 2 (25 pts)**: `bug2_sequential_workers_fixed` — `asyncio.gather` or `create_task` used; `test_run_workers_concurrent_timing` passes (5 jobs × 0.05s completes in <0.20s)
**Criterion 3 (25 pts)**: `bug3_registry_lock_added` — `asyncio.Lock()` in `JobRegistry`; `test_concurrent_updates_preserve_counts` passes
**Criterion 4 (25 pts)**: `bug4_await_response_json_fixed` — `await response.json()` present; `test_fetch_job_status_returns_dict` passes

**Pass threshold**: 65/100 (must fix at least 2-3 bugs)

---

## Key Test Details

- `test_run_workers_concurrent_timing`: runs 5 jobs each taking 0.05s; expects completion in <0.20s (3× overhead); sequential execution would take ~0.25s and fail
- `test_process_job_does_not_block_event_loop`: runs `process_job` and a simple 0.01s coroutine concurrently; the coroutine must be able to run while the job is "processing" — this requires non-blocking sleep
- `test_concurrent_updates_preserve_counts`: 10 jobs updated to running then completed concurrently; expects `completed==10, pending==0, running==0` — race conditions without Lock produce wrong counts
- `test_fetch_job_status_returns_dict`: uses `AsyncMock` for `response.json`; without `await`, returns a coroutine object instead of the dict

---

## Edge Cases

- Bug 3 (Lock) and Bug 1 (blocking sleep) interact: if sleep is still blocking, the race condition test may pass "accidentally" since concurrent tasks can't run anyway. Fix bugs independently.
- The timing test (Bug 2) has a 3× tolerance buffer to avoid flakiness on slow CI machines
- Bug 4 can be discovered without running tests by code review — `response.json()` is a coroutine in `aiohttp`
