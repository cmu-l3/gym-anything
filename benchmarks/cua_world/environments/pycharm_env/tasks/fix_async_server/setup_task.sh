#!/bin/bash
echo "=== Setting up fix_async_server ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_async_server"
PROJECT_DIR="/home/ga/PycharmProjects/async_scheduler"

rm -rf "$PROJECT_DIR"
rm -f /tmp/${TASK_NAME}_start_ts /tmp/${TASK_NAME}_result.json

mkdir -p "$PROJECT_DIR/server"
mkdir -p "$PROJECT_DIR/tests"

# requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'REQUIREMENTS'
pytest>=7.0
pytest-asyncio>=0.21.0
aiohttp>=3.9.0
REQUIREMENTS

# ============================================================
# server/__init__.py
# ============================================================
touch "$PROJECT_DIR/server/__init__.py"

# ============================================================
# server/models.py — no bugs
# ============================================================
cat > "$PROJECT_DIR/server/models.py" << 'PYEOF'
"""Data models for the job scheduling service."""
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional
import time


class JobStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"


@dataclass
class Job:
    job_id: str
    payload: dict
    status: JobStatus = JobStatus.PENDING
    result: Optional[dict] = None
    error: Optional[str] = None
    created_at: float = field(default_factory=time.time)
    completed_at: Optional[float] = None
PYEOF

# ============================================================
# server/registry.py
# BUG 3: JobRegistry.update_status uses a regular dict without asyncio.Lock
#         — concurrent updates cause race conditions / lost updates
# ============================================================
cat > "$PROJECT_DIR/server/registry.py" << 'PYEOF'
"""In-memory job registry with status tracking."""
import asyncio
from typing import Dict, Optional, List
from server.models import Job, JobStatus


class JobRegistry:
    """Thread-safe (asyncio-safe) registry of all jobs."""

    def __init__(self):
        self._jobs: Dict[str, Job] = {}
        self._status_counts: Dict[str, int] = {
            s.value: 0 for s in JobStatus
        }
        # BUG: No asyncio.Lock — concurrent coroutines updating status
        # will race and produce incorrect counts.
        # Fix: add self._lock = asyncio.Lock() and use `async with self._lock`
        # in update_status and register_job.

    def register_job(self, job: Job) -> None:
        """Register a new job. Must be called before any coroutines start processing it."""
        self._jobs[job.job_id] = job
        self._status_counts[job.status.value] += 1

    async def update_status(
        self,
        job_id: str,
        new_status: JobStatus,
        result: Optional[dict] = None,
        error: Optional[str] = None,
    ) -> None:
        """Update job status and adjust status counters."""
        # BUG: No lock here — two coroutines calling update_status concurrently
        # will both read the old status, both decrement/increment, causing wrong counts.
        job = self._jobs.get(job_id)
        if job is None:
            raise KeyError(f"Job {job_id} not found in registry")
        old_status = job.status
        job.status = new_status
        if result is not None:
            job.result = result
        if error is not None:
            job.error = error
        # Simulate async operation (e.g., persisting to DB)
        await asyncio.sleep(0)
        # Update counters
        self._status_counts[old_status.value] -= 1
        self._status_counts[new_status.value] += 1

    def get_job(self, job_id: str) -> Optional[Job]:
        return self._jobs.get(job_id)

    def get_status_counts(self) -> Dict[str, int]:
        return dict(self._status_counts)

    def list_jobs(self, status: Optional[JobStatus] = None) -> List[Job]:
        if status is None:
            return list(self._jobs.values())
        return [j for j in self._jobs.values() if j.status == status]
PYEOF

# ============================================================
# server/worker.py
# BUG 1: process_job calls time.sleep (blocking) instead of await asyncio.sleep
# BUG 2: run_workers creates coroutines but doesn't schedule them as concurrent tasks
#         (calls them sequentially instead of using asyncio.gather or create_task)
# ============================================================
cat > "$PROJECT_DIR/server/worker.py" << 'PYEOF'
"""Async job workers that process routing jobs."""
import asyncio
import time
from typing import List
from server.models import Job, JobStatus
from server.registry import JobRegistry


async def process_job(job: Job, registry: JobRegistry) -> None:
    """
    Process a single routing job asynchronously.
    Simulates network/IO work with async sleep.
    """
    await registry.update_status(job.job_id, JobStatus.RUNNING)
    try:
        # Simulate job processing (e.g., calling routing API)
        # BUG 1: time.sleep is synchronous and BLOCKS the entire event loop.
        # All other coroutines are frozen while this job "runs".
        # Fix: replace with `await asyncio.sleep(job.payload.get("duration", 0.1))`
        duration = job.payload.get("duration", 0.1)
        time.sleep(duration)  # BUG: blocks event loop

        result = {
            "route": job.payload.get("destination", "UNKNOWN"),
            "estimated_arrival": "2024-02-01T10:00:00Z",
        }
        await registry.update_status(job.job_id, JobStatus.COMPLETED, result=result)
    except Exception as e:
        await registry.update_status(job.job_id, JobStatus.FAILED, error=str(e))


async def run_workers(jobs: List[Job], registry: JobRegistry) -> None:
    """
    Run all jobs concurrently using asyncio.
    """
    # BUG 2: This runs jobs SEQUENTIALLY, not concurrently.
    # `for job in jobs: await process_job(job, registry)` waits for each
    # job to finish before starting the next.
    # Fix: use `await asyncio.gather(*[process_job(j, registry) for j in jobs])`
    # OR: create tasks with asyncio.create_task and await them all.
    for job in jobs:
        await process_job(job, registry)  # BUG: sequential, not concurrent
PYEOF

# ============================================================
# server/client.py
# BUG 4: fetch_job_status missing await on response.json()
# ============================================================
cat > "$PROJECT_DIR/server/client.py" << 'PYEOF'
"""Async HTTP client for querying job status from a remote scheduler API."""
import aiohttp
from typing import Optional


async def fetch_job_status(base_url: str, job_id: str) -> Optional[dict]:
    """
    Fetch job status from a remote scheduler API endpoint.
    GET {base_url}/jobs/{job_id}
    Returns parsed JSON response or None if 404.
    """
    async with aiohttp.ClientSession() as session:
        async with session.get(f"{base_url}/jobs/{job_id}") as response:
            if response.status == 404:
                return None
            response.raise_for_status()
            # BUG 4: response.json() is a coroutine and must be awaited.
            # Without await, this returns a coroutine object, not the dict.
            data = response.json()  # BUG: missing await
            return data
PYEOF

# ============================================================
# tests/__init__.py
# ============================================================
touch "$PROJECT_DIR/tests/__init__.py"

# ============================================================
# tests/conftest.py
# ============================================================
cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
import pytest
import pytest_asyncio
from server.registry import JobRegistry
from server.models import Job, JobStatus


@pytest.fixture
def registry():
    return JobRegistry()


@pytest.fixture
def sample_jobs():
    return [
        Job(job_id=f"JOB-{i:03d}", payload={"destination": f"DEPOT-{i}", "duration": 0.05})
        for i in range(5)
    ]
PYEOF

# ============================================================
# tests/test_registry.py
# ============================================================
cat > "$PROJECT_DIR/tests/test_registry.py" << 'PYEOF'
"""Tests for JobRegistry — these test concurrent update safety."""
import asyncio
import pytest
from server.models import Job, JobStatus
from server.registry import JobRegistry


@pytest.mark.asyncio
async def test_register_and_get_job(registry):
    job = Job(job_id="JOB-001", payload={"destination": "DEPOT-1"})
    registry.register_job(job)
    assert registry.get_job("JOB-001") is not None
    assert registry.get_job("JOB-001").status == JobStatus.PENDING


@pytest.mark.asyncio
async def test_update_status_single(registry):
    job = Job(job_id="JOB-001", payload={})
    registry.register_job(job)
    await registry.update_status("JOB-001", JobStatus.RUNNING)
    assert registry.get_job("JOB-001").status == JobStatus.RUNNING


@pytest.mark.asyncio
async def test_status_counts_after_update(registry):
    job = Job(job_id="JOB-001", payload={})
    registry.register_job(job)
    counts_before = registry.get_status_counts()
    assert counts_before["pending"] == 1

    await registry.update_status("JOB-001", JobStatus.COMPLETED)
    counts_after = registry.get_status_counts()
    assert counts_after["pending"] == 0
    assert counts_after["completed"] == 1


@pytest.mark.asyncio
async def test_concurrent_updates_preserve_counts(registry):
    """
    Register 10 jobs and complete them all concurrently.
    Status counts must be consistent: completed=10, pending=0, running=0.
    This test exposes the race condition in update_status.
    """
    jobs = [Job(job_id=f"J{i}", payload={}) for i in range(10)]
    for job in jobs:
        registry.register_job(job)

    # Concurrently move all to running, then to completed
    async def complete_job(j):
        await registry.update_status(j.job_id, JobStatus.RUNNING)
        await registry.update_status(j.job_id, JobStatus.COMPLETED)

    await asyncio.gather(*[complete_job(j) for j in jobs])

    counts = registry.get_status_counts()
    assert counts["completed"] == 10, \
        f"Expected 10 completed, got {counts}. " \
        f"Race condition in update_status — add asyncio.Lock."
    assert counts["pending"] == 0, f"Pending count should be 0, got {counts}"
    assert counts["running"] == 0, f"Running count should be 0, got {counts}"
PYEOF

# ============================================================
# tests/test_worker.py
# ============================================================
cat > "$PROJECT_DIR/tests/test_worker.py" << 'PYEOF'
"""Tests for async worker concurrency."""
import asyncio
import time
import pytest
from server.models import Job, JobStatus
from server.registry import JobRegistry
from server.worker import process_job, run_workers


@pytest.mark.asyncio
async def test_process_job_completes(registry):
    job = Job(job_id="JOB-001", payload={"destination": "DEPOT-1", "duration": 0.05})
    registry.register_job(job)
    await process_job(job, registry)
    assert registry.get_job("JOB-001").status == JobStatus.COMPLETED


@pytest.mark.asyncio
async def test_process_job_sets_result(registry):
    job = Job(job_id="JOB-001", payload={"destination": "DEPOT-A", "duration": 0.02})
    registry.register_job(job)
    await process_job(job, registry)
    result = registry.get_job("JOB-001").result
    assert result is not None
    assert result["route"] == "DEPOT-A"


@pytest.mark.asyncio
async def test_run_workers_concurrent_timing(registry, sample_jobs):
    """
    5 jobs each taking 0.05s. If concurrent: total ≈ 0.05s.
    If sequential (bug): total ≈ 0.25s.
    This test will FAIL if run_workers is sequential.
    """
    for job in sample_jobs:
        registry.register_job(job)

    start = time.monotonic()
    await run_workers(sample_jobs, registry)
    elapsed = time.monotonic() - start

    # Allow 3x tolerance but 0.25s sequential would fail
    assert elapsed < 0.20, \
        f"run_workers took {elapsed:.3f}s for 5 x 0.05s jobs — " \
        f"jobs are not running concurrently. " \
        f"Fix: use asyncio.gather(*[process_job(j, registry) for j in jobs])"


@pytest.mark.asyncio
async def test_run_workers_all_completed(registry, sample_jobs):
    """All jobs must be COMPLETED after run_workers finishes."""
    for job in sample_jobs:
        registry.register_job(job)
    await run_workers(sample_jobs, registry)
    for job in sample_jobs:
        assert registry.get_job(job.job_id).status == JobStatus.COMPLETED, \
            f"Job {job.job_id} is not COMPLETED"


@pytest.mark.asyncio
async def test_process_job_does_not_block_event_loop(registry):
    """
    process_job must use await asyncio.sleep, not time.sleep.
    A concurrent 0.01s coroutine must complete well before process_job's 0.1s duration.
    If time.sleep is used, the event loop is blocked and the coroutine can't run until
    after the blocking sleep returns (~0.1s). If asyncio.sleep is used, it runs at ~0.01s.
    """
    job = Job(job_id="JOB-BLOCK", payload={"duration": 0.1})
    registry.register_job(job)

    other_done_at = []

    async def other_task():
        await asyncio.sleep(0.01)
        other_done_at.append(time.monotonic())

    start = time.monotonic()
    # Run both concurrently
    await asyncio.gather(process_job(job, registry), other_task())

    assert len(other_done_at) == 1, "other_task() never ran"
    elapsed = other_done_at[0] - start
    assert elapsed < 0.06, (
        f"other_task() completed at {elapsed:.3f}s after start — should be ~0.01s. "
        "process_job is blocking the event loop with time.sleep. "
        "Fix: replace time.sleep(duration) with await asyncio.sleep(duration)"
    )
PYEOF

# ============================================================
# tests/test_client.py
# ============================================================
cat > "$PROJECT_DIR/tests/test_client.py" << 'PYEOF'
"""Tests for async HTTP client."""
import pytest
import asyncio
from unittest.mock import AsyncMock, MagicMock, patch
from server.client import fetch_job_status


@pytest.mark.asyncio
async def test_fetch_job_status_returns_dict():
    """fetch_job_status must return a dict, not a coroutine object."""
    mock_response_data = {"job_id": "JOB-001", "status": "completed"}

    mock_response = AsyncMock()
    mock_response.status = 200
    mock_response.raise_for_status = MagicMock()
    mock_response.json = AsyncMock(return_value=mock_response_data)

    mock_cm = AsyncMock()
    mock_cm.__aenter__ = AsyncMock(return_value=mock_response)
    mock_cm.__aexit__ = AsyncMock(return_value=False)

    mock_session = AsyncMock()
    mock_session.get = MagicMock(return_value=mock_cm)

    mock_session_cm = AsyncMock()
    mock_session_cm.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session_cm.__aexit__ = AsyncMock(return_value=False)

    with patch("server.client.aiohttp.ClientSession", return_value=mock_session_cm):
        result = await fetch_job_status("http://localhost:8080", "JOB-001")

    assert isinstance(result, dict), \
        f"Expected dict, got {type(result).__name__}. " \
        f"Did you forget to 'await response.json()'?"
    assert result["job_id"] == "JOB-001"


@pytest.mark.asyncio
async def test_fetch_job_status_returns_none_on_404():
    """fetch_job_status must return None when server responds 404."""
    mock_response = AsyncMock()
    mock_response.status = 404

    mock_cm = AsyncMock()
    mock_cm.__aenter__ = AsyncMock(return_value=mock_response)
    mock_cm.__aexit__ = AsyncMock(return_value=False)

    mock_session = AsyncMock()
    mock_session.get = MagicMock(return_value=mock_cm)

    mock_session_cm = AsyncMock()
    mock_session_cm.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session_cm.__aexit__ = AsyncMock(return_value=False)

    with patch("server.client.aiohttp.ClientSession", return_value=mock_session_cm):
        result = await fetch_job_status("http://localhost:8080", "NONEXISTENT")

    assert result is None
PYEOF

# pytest.ini for asyncio mode
cat > "$PROJECT_DIR/pytest.ini" << 'INIEOF'
[pytest]
asyncio_mode = auto
INIEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Install dependencies
echo "Installing Python dependencies..."
su - ga -c "pip3 install --quiet pytest pytest-asyncio aiohttp 2>&1 | tail -3" || true

# PyCharm .idea files
mkdir -p "$PROJECT_DIR/.idea"
cat > "$PROJECT_DIR/.idea/misc.xml" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectRootManager" version="2" project-jdk-name="Python 3.11" project-jdk-type="Python SDK" />
</project>
XML

cat > "$PROJECT_DIR/.idea/modules.xml" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectModuleManager">
    <modules>
      <module fileurl="file://$PROJECT_DIR$/async_scheduler.iml" filepath="$PROJECT_DIR$/async_scheduler.iml" />
    </modules>
  </component>
</project>
XML

cat > "$PROJECT_DIR/.idea/async_scheduler.iml" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<module type="PYTHON_MODULE" version="4">
  <component name="NewModuleRootManager">
    <content url="file://$MODULE_DIR$" />
    <orderEntry type="inheritedJdk" />
    <orderEntry type="sourceFolder" forTests="false" />
  </component>
</module>
XML

chown -R ga:ga "$PROJECT_DIR/.idea"

# Record start timestamp
date +%s > /tmp/${TASK_NAME}_start_ts

# Open in PyCharm
echo "Opening project in PyCharm..."
if type setup_pycharm_project &>/dev/null; then
    setup_pycharm_project "$PROJECT_DIR"
else
    su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' >> /home/ga/pycharm.log 2>&1 &"
    sleep 15
fi

sleep 2
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="
