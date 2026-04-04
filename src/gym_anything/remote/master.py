#!/usr/bin/env python3
"""
Gym-Anything Master Server

Central entry point for distributed Gym-Anything environments.
Routes requests to worker servers with load balancing and health monitoring.

Features:
- Async request proxying (handles 100s of concurrent requests)
- Worker registration and health monitoring
- Load-balanced environment creation
- Sticky routing (env_id -> worker)
- Aggregated dashboard and metrics

Usage:
    python -m gym_anything.remote.master --host 0.0.0.0 --port 5000
"""

from __future__ import annotations

import argparse
import asyncio
import copy
import json
import logging
import os
import random
import socket
import time
import uuid
from dataclasses import dataclass, field, asdict
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, NamedTuple

import httpx
from quart import Quart, request, Response, jsonify, render_template_string
from quart_cors import cors
from hypercorn.config import Config as HypercornConfig
from hypercorn.asyncio import serve as hypercorn_serve

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


# =============================================================================
# Configuration
# =============================================================================

@dataclass
class MasterConfig:
    """Master server configuration."""
    host: str = "0.0.0.0"
    port: int = 5000

    # Health check settings
    heartbeat_timeout_sec: int = 90       # Mark unhealthy if no heartbeat
    dead_timeout_sec: int = 300           # Mark dead and orphan envs
    health_check_interval_sec: int = 30   # How often to check worker health

    # Load balancing
    default_max_envs_per_worker: int = 10

    # Proxy settings
    proxy_timeout_sec: float = 600.0  # 10 minutes - reset can be slow
    proxy_connect_timeout_sec: float = 30.0
    max_connections: int = 500
    max_keepalive_connections: int = 100


# =============================================================================
# Data Classes
# =============================================================================

@dataclass
class CircuitBreakerState:
    """Circuit breaker state for a worker."""
    consecutive_failures: int = 0
    last_failure_time: float = 0.0
    circuit_open: bool = False
    circuit_open_until: float = 0.0

    # Configuration
    failure_threshold: int = 5      # Open circuit after N consecutive failures
    recovery_timeout: float = 30.0  # Seconds before trying again


@dataclass
class WorkerInfo:
    """Information about a registered worker."""
    worker_id: str
    url: str
    hostname: str
    port: int
    max_envs: int
    registered_at: float = field(default_factory=time.time)
    last_heartbeat: float = field(default_factory=time.time)
    status: str = "healthy"  # healthy, unhealthy, dead, draining
    env_count: int = 0
    env_ids: List[str] = field(default_factory=list)
    pending_count: int = 0  # Reservations for env creation in progress
    error_count: int = 0
    total_requests: int = 0
    cpu_percent: float = 0.0
    memory_percent: float = 0.0
    metadata: Dict[str, Any] = field(default_factory=dict)
    circuit_breaker: CircuitBreakerState = field(default_factory=CircuitBreakerState)
    # Full metrics from worker (endpoint stats, activity log, timeline, env details)
    metrics: Optional[Dict[str, Any]] = None

    @property
    def effective_count(self) -> int:
        """Total slots used: actual envs + pending reservations."""
        return self.env_count + self.pending_count

    def has_capacity(self) -> bool:
        """Check if worker has capacity for new env (including pending)."""
        return self.effective_count < self.max_envs

    def to_dict(self) -> Dict[str, Any]:
        result = {
            "worker_id": self.worker_id,
            "url": self.url,
            "hostname": self.hostname,
            "port": self.port,
            "max_envs": self.max_envs,
            "registered_at": self.registered_at,
            "last_heartbeat": self.last_heartbeat,
            "status": self.status,
            "env_count": self.env_count,
            "pending_count": self.pending_count,
            "effective_count": self.effective_count,
            "env_ids": self.env_ids,
            "error_count": self.error_count,
            "total_requests": self.total_requests,
            "cpu_percent": self.cpu_percent,
            "memory_percent": self.memory_percent,
            "load_percent": (self.effective_count / self.max_envs * 100) if self.max_envs > 0 else 0,
            "uptime_sec": time.time() - self.registered_at,
            "last_heartbeat_ago_sec": time.time() - self.last_heartbeat,
            "metadata": self.metadata,
            "circuit_open": self.circuit_breaker.circuit_open,
            "consecutive_failures": self.circuit_breaker.consecutive_failures,
        }
        # Include worker metrics if available
        if self.metrics:
            result["metrics"] = self.metrics
        return result

    def is_available(self) -> bool:
        """Check if worker is available for new requests."""
        # Check status
        if self.status not in ("healthy", "draining"):
            return False

        # Check circuit breaker
        if self.circuit_breaker.circuit_open:
            if time.time() > self.circuit_breaker.circuit_open_until:
                # Recovery timeout passed, try again (half-open state)
                return True
            return False

        return True

    def record_success(self):
        """Record successful request - reset circuit breaker."""
        self.circuit_breaker.consecutive_failures = 0
        self.circuit_breaker.circuit_open = False
        self.total_requests += 1

    def record_failure(self):
        """Record failed request - may open circuit breaker."""
        self.error_count += 1
        self.circuit_breaker.consecutive_failures += 1
        self.circuit_breaker.last_failure_time = time.time()

        if self.circuit_breaker.consecutive_failures >= self.circuit_breaker.failure_threshold:
            self.circuit_breaker.circuit_open = True
            self.circuit_breaker.circuit_open_until = time.time() + self.circuit_breaker.recovery_timeout
            logger.warning(f"Circuit breaker OPENED for worker {self.worker_id} "
                          f"after {self.circuit_breaker.consecutive_failures} failures")


# =============================================================================
# Worker Slot (Immutable snapshot for safe async operations)
# =============================================================================

class WorkerSlot(NamedTuple):
    """Immutable snapshot of a reserved worker slot.

    Returned by reserve_slot_for_new_env() and get_worker_for_env() to avoid
    returning mutable WorkerInfo references that could be modified by other coroutines.
    """
    worker_id: str
    url: str
    hostname: str
    port: int
    effective_count: int
    max_envs: int
    pending_count: int
    status: str = "healthy"  # Worker status for routing decisions


# =============================================================================
# Worker Registry
# =============================================================================

class WorkerRegistry:
    """Async-safe registry of workers with health monitoring.

    Uses asyncio.Lock for proper async concurrency. All public methods
    that access shared state are async and must be awaited.
    """

    def __init__(self, config: MasterConfig):
        self.config = config
        self._workers: Dict[str, WorkerInfo] = {}
        self._env_to_worker: Dict[str, str] = {}  # env_id -> worker_id
        self._lock = asyncio.Lock()  # Async lock for proper coroutine yielding
        self._health_check_task: Optional[asyncio.Task] = None
        # Track pending reservation timestamps for stale cleanup
        self._pending_timestamps: Dict[str, List[float]] = {}  # worker_id -> [timestamps]

    async def register_worker(self, worker_id: str, url: str, hostname: str,
                              port: int, max_envs: int, metadata: Dict = None) -> WorkerInfo:
        """Register a new worker or update existing."""
        async with self._lock:
            if worker_id in self._workers:
                # Update existing worker
                worker = self._workers[worker_id]
                worker.url = url
                worker.hostname = hostname
                worker.port = port
                worker.max_envs = max_envs
                worker.last_heartbeat = time.time()
                worker.status = "healthy"
                if metadata:
                    worker.metadata.update(metadata)
                logger.info(f"Updated worker {worker_id} at {url}")
            else:
                # New worker
                worker = WorkerInfo(
                    worker_id=worker_id,
                    url=url,
                    hostname=hostname,
                    port=port,
                    max_envs=max_envs,
                    metadata=metadata or {}
                )
                self._workers[worker_id] = worker
                self._pending_timestamps[worker_id] = []
                logger.info(f"Registered new worker {worker_id} at {url}")

            # Return a copy to avoid external mutation
            return worker

    async def update_heartbeat(self, worker_id: str, env_count: int, env_ids: List[str],
                               cpu_percent: float = 0, memory_percent: float = 0,
                               metrics: Optional[Dict[str, Any]] = None) -> bool:
        """Update worker heartbeat and sync env mappings."""
        async with self._lock:
            if worker_id not in self._workers:
                return False

            worker = self._workers[worker_id]
            worker.last_heartbeat = time.time()
            worker.env_count = env_count
            worker.cpu_percent = cpu_percent
            worker.memory_percent = memory_percent
            # Store full metrics from worker (deep copy to avoid reference issues)
            if metrics:
                worker.metrics = copy.deepcopy(metrics)

            # Sync env_to_worker mapping
            old_env_ids = set(worker.env_ids)
            new_env_ids = set(env_ids)

            # Remove mappings for envs that no longer exist on worker
            for env_id in old_env_ids - new_env_ids:
                self._env_to_worker.pop(env_id, None)
                logger.debug(f"Removed stale env mapping: {env_id}")

            # Add mappings for new envs (worker reports envs we didn't know about)
            for env_id in new_env_ids - old_env_ids:
                if env_id not in self._env_to_worker:
                    self._env_to_worker[env_id] = worker_id
                    logger.debug(f"Added missing env mapping: {env_id} -> {worker_id}")

            worker.env_ids = list(env_ids)  # Copy the list

            # Mark healthy if was unhealthy
            if worker.status == "unhealthy":
                worker.status = "healthy"
                logger.info(f"Worker {worker_id} recovered to healthy")

            return True

    async def deregister_worker(self, worker_id: str, reason: str = "manual") -> bool:
        """Remove a worker from registry."""
        async with self._lock:
            if worker_id not in self._workers:
                return False

            worker = self._workers.pop(worker_id)
            self._pending_timestamps.pop(worker_id, None)

            # Remove all env mappings for this worker
            for env_id in worker.env_ids:
                self._env_to_worker.pop(env_id, None)

            logger.info(f"Deregistered worker {worker_id} (reason: {reason})")
            return True

    async def get_worker(self, worker_id: str) -> Optional[Dict[str, Any]]:
        """Get worker by ID. Returns a dict snapshot, not the mutable object."""
        async with self._lock:
            worker = self._workers.get(worker_id)
            if worker:
                return worker.to_dict()
            return None

    async def get_worker_for_env(self, env_id: str) -> Optional[WorkerSlot]:
        """Get worker that owns an environment. Returns immutable WorkerSlot."""
        async with self._lock:
            worker_id = self._env_to_worker.get(env_id)
            if worker_id and worker_id in self._workers:
                worker = self._workers[worker_id]
                return WorkerSlot(
                    worker_id=worker.worker_id,
                    url=worker.url,
                    hostname=worker.hostname,
                    port=worker.port,
                    effective_count=worker.effective_count,
                    max_envs=worker.max_envs,
                    pending_count=worker.pending_count,
                    status=worker.status
                )
            return None

    async def get_worker_status(self, worker_id: str) -> Optional[str]:
        """Get worker status. Quick check for routing decisions."""
        async with self._lock:
            worker = self._workers.get(worker_id)
            return worker.status if worker else None

    async def register_env(self, env_id: str, worker_id: str):
        """Register env to worker mapping after successful creation."""
        async with self._lock:
            self._env_to_worker[env_id] = worker_id
            if worker_id in self._workers:
                worker = self._workers[worker_id]
                if env_id not in worker.env_ids:
                    worker.env_ids.append(env_id)
                    worker.env_count = len(worker.env_ids)

    async def unregister_env(self, env_id: str):
        """Remove env mapping after close."""
        async with self._lock:
            worker_id = self._env_to_worker.pop(env_id, None)
            if worker_id and worker_id in self._workers:
                worker = self._workers[worker_id]
                if env_id in worker.env_ids:
                    worker.env_ids.remove(env_id)
                    worker.env_count = len(worker.env_ids)

    async def reserve_slot_for_new_env(self) -> Optional[WorkerSlot]:
        """Atomically select and reserve a slot on a least-loaded worker.

        Returns an immutable WorkerSlot to prevent external modification.

        This prevents race conditions by incrementing pending_count while
        holding the lock. The reservation must be:
        - Converted to actual env with confirm_reservation() on success
        - Released with release_reservation() on failure

        Selection strategy:
        1. Filter to healthy workers with capacity
        2. Find the minimum load percentage
        3. Randomly select among workers within 10% of minimum load
           (provides load balancing while avoiding thundering herd)

        Only selects workers that are:
        - status == "healthy" (NOT draining, unhealthy, or dead)
        - is_available() (circuit breaker not open)
        - has_capacity() (env_count + pending_count < max_envs)
        """
        async with self._lock:
            available = [
                w for w in self._workers.values()
                if w.status == "healthy"  # Draining workers don't accept new envs
                   and w.is_available()   # Circuit breaker check
                   and w.has_capacity()   # Uses effective_count (includes pending)
            ]

            if not available:
                return None

            # Calculate load percentage for each worker
            def load_pct(w):
                return w.effective_count / w.max_envs if w.max_envs > 0 else 0

            # Find minimum load
            min_load = min(load_pct(w) for w in available)

            # Select workers within 10% of minimum load (or equal if all are equal)
            # This provides some load balancing while randomizing among similar workers
            load_threshold = min_load + 0.10  # 10% tolerance
            candidates = [w for w in available if load_pct(w) <= load_threshold]

            # Randomly select among candidates to avoid thundering herd
            worker = random.choice(candidates)

            # ATOMICALLY reserve the slot
            worker.pending_count += 1

            # Track reservation timestamp for stale cleanup
            if worker.worker_id not in self._pending_timestamps:
                self._pending_timestamps[worker.worker_id] = []
            self._pending_timestamps[worker.worker_id].append(time.time())

            logger.debug(f"Reserved slot on {worker.worker_id} "
                        f"(selected from {len(candidates)} candidates, "
                        f"pending={worker.pending_count}, effective={worker.effective_count}/{worker.max_envs})")

            # Return immutable snapshot
            return WorkerSlot(
                worker_id=worker.worker_id,
                url=worker.url,
                hostname=worker.hostname,
                port=worker.port,
                effective_count=worker.effective_count,
                max_envs=worker.max_envs,
                pending_count=worker.pending_count,
                status=worker.status
            )

    async def release_reservation(self, worker_id: str) -> bool:
        """Release a pending reservation (call on env creation failure)."""
        async with self._lock:
            if worker_id not in self._workers:
                return False
            worker = self._workers[worker_id]
            if worker.pending_count > 0:
                worker.pending_count -= 1
                # Remove oldest timestamp
                if worker_id in self._pending_timestamps and self._pending_timestamps[worker_id]:
                    self._pending_timestamps[worker_id].pop(0)
                logger.debug(f"Released reservation on {worker_id} (pending={worker.pending_count})")
            else:
                logger.warning(f"Tried to release reservation on {worker_id} but pending_count=0")
            return True

    async def confirm_reservation(self, worker_id: str, env_id: str) -> bool:
        """Convert pending reservation to actual env (call on success)."""
        async with self._lock:
            if worker_id not in self._workers:
                return False
            worker = self._workers[worker_id]

            # Decrement pending, add actual env
            if worker.pending_count > 0:
                worker.pending_count -= 1
                # Remove oldest timestamp
                if worker_id in self._pending_timestamps and self._pending_timestamps[worker_id]:
                    self._pending_timestamps[worker_id].pop(0)
            else:
                logger.warning(f"Confirming env {env_id} on {worker_id} but pending_count=0 "
                              "(heartbeat may have synced first)")

            if env_id not in worker.env_ids:
                worker.env_ids.append(env_id)
                worker.env_count = len(worker.env_ids)

            self._env_to_worker[env_id] = worker_id
            logger.debug(f"Confirmed env {env_id} on {worker_id} "
                        f"(envs={worker.env_count}, pending={worker.pending_count})")
            return True

    async def reset_pending_counts(self):
        """Reset all pending counts to 0 (for recovery from stuck state)."""
        async with self._lock:
            for worker in self._workers.values():
                if worker.pending_count > 0:
                    logger.warning(f"Resetting pending_count={worker.pending_count} on {worker.worker_id}")
                    worker.pending_count = 0
            self._pending_timestamps.clear()

    async def cleanup_stale_pending(self):
        """Clean up stale pending reservations.

        Cleans up based on:
        1. If effective_count exceeds max_envs
        2. If pending reservations are older than proxy_timeout (time-based)
        """
        stale_timeout = self.config.proxy_timeout_sec + 30  # Give some buffer
        now = time.time()

        async with self._lock:
            for worker_id, timestamps in list(self._pending_timestamps.items()):
                if worker_id not in self._workers:
                    del self._pending_timestamps[worker_id]
                    continue

                worker = self._workers[worker_id]

                # Time-based cleanup: remove reservations older than timeout
                stale_count = 0
                while timestamps and (now - timestamps[0]) > stale_timeout:
                    timestamps.pop(0)
                    stale_count += 1

                if stale_count > 0 and worker.pending_count >= stale_count:
                    worker.pending_count -= stale_count
                    logger.warning(f"Cleaned up {stale_count} stale pending on {worker_id} "
                                  f"(older than {stale_timeout:.0f}s)")

                # Safety check: if effective count exceeds capacity, pending is stale
                if worker.pending_count > 0 and worker.effective_count > worker.max_envs:
                    overage = worker.effective_count - worker.max_envs
                    reduction = min(worker.pending_count, overage)
                    worker.pending_count -= reduction
                    # Also remove from timestamps
                    for _ in range(min(reduction, len(timestamps))):
                        timestamps.pop(0)
                    logger.warning(f"Cleaned up {reduction} over-capacity pending on {worker_id}")

    async def record_request_success(self, worker_id: str):
        """Record successful request - reset circuit breaker. Thread-safe."""
        async with self._lock:
            if worker_id in self._workers:
                worker = self._workers[worker_id]
                worker.circuit_breaker.consecutive_failures = 0
                worker.circuit_breaker.circuit_open = False
                worker.total_requests += 1

    async def record_request_failure(self, worker_id: str):
        """Record failed request - may open circuit breaker. Thread-safe."""
        async with self._lock:
            if worker_id in self._workers:
                worker = self._workers[worker_id]
                worker.error_count += 1
                worker.circuit_breaker.consecutive_failures += 1
                worker.circuit_breaker.last_failure_time = time.time()

                if worker.circuit_breaker.consecutive_failures >= worker.circuit_breaker.failure_threshold:
                    worker.circuit_breaker.circuit_open = True
                    worker.circuit_breaker.circuit_open_until = time.time() + worker.circuit_breaker.recovery_timeout
                    logger.warning(f"Circuit breaker OPENED for worker {worker_id} "
                                  f"after {worker.circuit_breaker.consecutive_failures} failures")

    async def drain_worker(self, worker_id: str) -> bool:
        """Set worker to draining state - stop accepting new envs."""
        async with self._lock:
            if worker_id not in self._workers:
                return False
            worker = self._workers[worker_id]
            worker.status = "draining"
            logger.info(f"Worker {worker_id} set to DRAINING - no new envs will be routed")
            return True

    async def undrain_worker(self, worker_id: str) -> bool:
        """Restore worker from draining to healthy state."""
        async with self._lock:
            if worker_id not in self._workers:
                return False
            worker = self._workers[worker_id]
            if worker.status == "draining":
                worker.status = "healthy"
                logger.info(f"Worker {worker_id} restored to HEALTHY")
            return True

    async def get_all_workers(self) -> List[Dict[str, Any]]:
        """Get all workers as dict snapshots."""
        async with self._lock:
            return [w.to_dict() for w in self._workers.values()]

    async def get_healthy_workers(self) -> List[Dict[str, Any]]:
        """Get healthy workers as dict snapshots."""
        async with self._lock:
            return [w.to_dict() for w in self._workers.values() if w.status == "healthy"]

    async def get_worker_count(self) -> int:
        """Get total worker count."""
        async with self._lock:
            return len(self._workers)

    async def get_healthy_worker_count(self) -> int:
        """Get healthy worker count."""
        async with self._lock:
            return len([w for w in self._workers.values() if w.status == "healthy"])

    async def check_worker_health(self):
        """Check and update worker health status based on heartbeat."""
        now = time.time()
        async with self._lock:
            for worker in self._workers.values():
                time_since_heartbeat = now - worker.last_heartbeat

                if worker.status == "draining":
                    continue  # Don't change draining status

                if time_since_heartbeat > self.config.dead_timeout_sec:
                    if worker.status != "dead":
                        worker.status = "dead"
                        logger.warning(f"Worker {worker.worker_id} marked DEAD "
                                      f"(no heartbeat for {time_since_heartbeat:.0f}s)")
                        # Orphan environments
                        for env_id in worker.env_ids:
                            self._env_to_worker.pop(env_id, None)
                        worker.env_ids = []
                        worker.env_count = 0
                        worker.pending_count = 0
                        # Clear pending timestamps
                        self._pending_timestamps.pop(worker.worker_id, None)

                elif time_since_heartbeat > self.config.heartbeat_timeout_sec:
                    if worker.status == "healthy":
                        worker.status = "unhealthy"
                        logger.warning(f"Worker {worker.worker_id} marked UNHEALTHY "
                                      f"(no heartbeat for {time_since_heartbeat:.0f}s)")

    async def get_stats(self) -> Dict[str, Any]:
        """Get registry statistics with aggregated metrics from all workers.

        OPTIMIZED: Minimizes lock time by copying data under lock,
        then processing outside the lock.
        """
        # Step 1: Quick snapshot under lock (minimal time)
        async with self._lock:
            # Deep copy worker data to avoid holding references
            workers_snapshot = []
            for w in self._workers.values():
                workers_snapshot.append({
                    "worker_id": w.worker_id,
                    "hostname": w.hostname,
                    "url": w.url,
                    "port": w.port,
                    "status": w.status,
                    "env_count": w.env_count,
                    "pending_count": w.pending_count,
                    "max_envs": w.max_envs,
                    "error_count": w.error_count,
                    "total_requests": w.total_requests,
                    "cpu_percent": w.cpu_percent,
                    "memory_percent": w.memory_percent,
                    "registered_at": w.registered_at,
                    "last_heartbeat": w.last_heartbeat,
                    "env_ids": list(w.env_ids),
                    "metadata": dict(w.metadata) if w.metadata else {},
                    "circuit_open": w.circuit_breaker.circuit_open,
                    "consecutive_failures": w.circuit_breaker.consecutive_failures,
                    "metrics": copy.deepcopy(w.metrics) if w.metrics else None,
                })
            env_mappings_snapshot = dict(self._env_to_worker)
        # Lock released here - all processing below is lock-free

        # Step 2: Process snapshots (no lock held)
        workers = workers_snapshot

        # Aggregate by hostname
        hostname_stats = {}
        for w in workers:
            h = w["hostname"]
            if h not in hostname_stats:
                hostname_stats[h] = {
                    "hostname": h,
                    "worker_count": 0,
                    "env_count": 0,
                    "capacity": 0,
                    "error_count": 0,
                    "healthy_count": 0,
                    "unhealthy_count": 0,
                    "total_requests": 0,
                    "endpoint_stats": {},
                }
            hostname_stats[h]["worker_count"] += 1
            hostname_stats[h]["env_count"] += w["env_count"]
            hostname_stats[h]["capacity"] += w["max_envs"]
            hostname_stats[h]["error_count"] += w["error_count"]
            hostname_stats[h]["total_requests"] += w["total_requests"]
            if w["status"] == "healthy":
                hostname_stats[h]["healthy_count"] += 1
            else:
                hostname_stats[h]["unhealthy_count"] += 1

            # Aggregate endpoint stats from worker metrics
            if w["metrics"] and "endpoints" in w["metrics"]:
                for ep_stat in w["metrics"]["endpoints"].get("stats", []):
                    ep_name = ep_stat.get("name", "unknown")
                    if ep_name not in hostname_stats[h]["endpoint_stats"]:
                        hostname_stats[h]["endpoint_stats"][ep_name] = {
                            "name": ep_name,
                            "request_count": 0,
                            "error_count": 0,
                            "total_latency": 0.0,
                        }
                    hostname_stats[h]["endpoint_stats"][ep_name]["request_count"] += ep_stat.get("request_count", 0)
                    hostname_stats[h]["endpoint_stats"][ep_name]["error_count"] += ep_stat.get("error_count", 0)
                    hostname_stats[h]["endpoint_stats"][ep_name]["total_latency"] += ep_stat.get("avg_latency", 0) * ep_stat.get("request_count", 0)

        # Convert endpoint_stats dict to list with computed averages
        for h_stats in hostname_stats.values():
            ep_list = []
            for ep_data in h_stats["endpoint_stats"].values():
                if ep_data["request_count"] > 0:
                    ep_data["avg_latency"] = ep_data["total_latency"] / ep_data["request_count"]
                else:
                    ep_data["avg_latency"] = 0
                del ep_data["total_latency"]
                ep_list.append(ep_data)
            h_stats["endpoint_stats"] = sorted(ep_list, key=lambda x: x["request_count"], reverse=True)

        # Aggregate all activity logs, endpoint stats, and compute totals
        all_activity_logs = []
        all_endpoint_stats = {}
        total_envs_created = 0
        total_envs_closed = 0
        total_requests = 0
        total_errors = 0
        all_active_envs = []
        all_timelines = []

        for w in workers:
            if not w["metrics"]:
                continue

            # Collect activity logs
            if "activity_log" in w["metrics"]:
                for log in w["metrics"]["activity_log"]:
                    log_copy = dict(log)
                    log_copy["worker_id"] = w["worker_id"]
                    log_copy["hostname"] = w["hostname"]
                    all_activity_logs.append(log_copy)

            # Aggregate endpoint stats
            if "endpoints" in w["metrics"]:
                total_requests += w["metrics"]["endpoints"].get("total_requests", 0)
                total_errors += w["metrics"]["endpoints"].get("total_errors", 0)
                for ep_stat in w["metrics"]["endpoints"].get("stats", []):
                    ep_name = ep_stat.get("name", "unknown")
                    if ep_name not in all_endpoint_stats:
                        all_endpoint_stats[ep_name] = {
                            "name": ep_name,
                            "request_count": 0,
                            "success_count": 0,
                            "error_count": 0,
                            "latencies": [],
                        }
                    all_endpoint_stats[ep_name]["request_count"] += ep_stat.get("request_count", 0)
                    all_endpoint_stats[ep_name]["success_count"] += ep_stat.get("success_count", 0)
                    all_endpoint_stats[ep_name]["error_count"] += ep_stat.get("error_count", 0)
                    if ep_stat.get("request_count", 0) > 0:
                        all_endpoint_stats[ep_name]["latencies"].append({
                            "avg": ep_stat.get("avg_latency", 0),
                            "p50": ep_stat.get("p50_latency", 0),
                            "p95": ep_stat.get("p95_latency", 0),
                            "p99": ep_stat.get("p99_latency", 0),
                            "count": ep_stat.get("request_count", 0)
                        })

            # Aggregate environment stats
            if "environments" in w["metrics"]:
                total_envs_created += w["metrics"]["environments"].get("total_created", 0)
                total_envs_closed += w["metrics"]["environments"].get("total_closed", 0)
                for env in w["metrics"]["environments"].get("active", []):
                    env_copy = dict(env)
                    env_copy["worker_id"] = w["worker_id"]
                    env_copy["hostname"] = w["hostname"]
                    all_active_envs.append(env_copy)

            # Collect timeline data
            if "timeline" in w["metrics"]:
                for point in w["metrics"]["timeline"]:
                    point_copy = dict(point)
                    point_copy["worker_id"] = w["worker_id"]
                    all_timelines.append(point_copy)

        # Compute final endpoint stats with averages
        endpoint_stats_list = []
        for ep_name, ep_data in all_endpoint_stats.items():
            total_count = sum(lat["count"] for lat in ep_data["latencies"])
            if total_count > 0:
                avg_latency = sum(lat["avg"] * lat["count"] for lat in ep_data["latencies"]) / total_count
                p50_latency = max((lat["p50"] for lat in ep_data["latencies"]), default=0)
                p95_latency = max((lat["p95"] for lat in ep_data["latencies"]), default=0)
                p99_latency = max((lat["p99"] for lat in ep_data["latencies"]), default=0)
            else:
                avg_latency = p50_latency = p95_latency = p99_latency = 0

            endpoint_stats_list.append({
                "name": ep_name,
                "request_count": ep_data["request_count"],
                "success_count": ep_data["success_count"],
                "error_count": ep_data["error_count"],
                "error_rate": ep_data["error_count"] / ep_data["request_count"] if ep_data["request_count"] > 0 else 0,
                "avg_latency": avg_latency,
                "p50_latency": p50_latency,
                "p95_latency": p95_latency,
                "p99_latency": p99_latency,
            })

        # Sort activity logs by timestamp (most recent first)
        all_activity_logs.sort(key=lambda x: x.get("timestamp", 0), reverse=True)
        all_activity_logs = all_activity_logs[:100]

        # Sort endpoint stats by request count
        endpoint_stats_list.sort(key=lambda x: x["request_count"], reverse=True)

        # Build worker dicts for response (already have the data)
        worker_dicts = []
        for w in workers:
            effective_count = w["env_count"] + w["pending_count"]
            worker_dicts.append({
                "worker_id": w["worker_id"],
                "url": w["url"],
                "hostname": w["hostname"],
                "port": w["port"],
                "max_envs": w["max_envs"],
                "registered_at": w["registered_at"],
                "last_heartbeat": w["last_heartbeat"],
                "status": w["status"],
                "env_count": w["env_count"],
                "pending_count": w["pending_count"],
                "effective_count": effective_count,
                "env_ids": w["env_ids"],
                "error_count": w["error_count"],
                "total_requests": w["total_requests"],
                "cpu_percent": w["cpu_percent"],
                "memory_percent": w["memory_percent"],
                "load_percent": (effective_count / w["max_envs"] * 100) if w["max_envs"] > 0 else 0,
                "uptime_sec": time.time() - w["registered_at"],
                "last_heartbeat_ago_sec": time.time() - w["last_heartbeat"],
                "metadata": w["metadata"],
                "circuit_open": w["circuit_open"],
                "consecutive_failures": w["consecutive_failures"],
            })
            if w["metrics"]:
                worker_dicts[-1]["metrics"] = w["metrics"]

        return {
            "total_workers": len(workers),
            "healthy_workers": len([w for w in workers if w["status"] == "healthy"]),
            "unhealthy_workers": len([w for w in workers if w["status"] == "unhealthy"]),
            "dead_workers": len([w for w in workers if w["status"] == "dead"]),
            "draining_workers": len([w for w in workers if w["status"] == "draining"]),
            "total_envs": sum(w["env_count"] for w in workers),
            "total_capacity": sum(w["max_envs"] for w in workers),
            "workers": worker_dicts,
            "hostname_stats": list(hostname_stats.values()),
            "env_mappings": env_mappings_snapshot,
            "aggregated": {
                "total_requests": total_requests,
                "total_errors": total_errors,
                "error_rate": total_errors / total_requests if total_requests > 0 else 0,
                "total_envs_created": total_envs_created,
                "total_envs_closed": total_envs_closed,
                "endpoint_stats": endpoint_stats_list,
                "activity_log": all_activity_logs,
                "active_envs": all_active_envs,
                "timeline": all_timelines,
            }
        }


# =============================================================================
# Quart Application
# =============================================================================

app = Quart(__name__)
app = cors(app)  # Enable CORS

# Global state
config = MasterConfig()
registry = WorkerRegistry(config)
http_client: Optional[httpx.AsyncClient] = None
start_time = time.time()


@app.before_serving
async def startup():
    """Initialize async HTTP client."""
    global http_client
    http_client = httpx.AsyncClient(
        timeout=httpx.Timeout(config.proxy_timeout_sec, connect=config.proxy_connect_timeout_sec),
        limits=httpx.Limits(
            max_connections=config.max_connections,
            max_keepalive_connections=config.max_keepalive_connections
        )
    )

    # Start health check background task
    asyncio.create_task(health_check_loop())

    logger.info("Master server started")


@app.after_serving
async def shutdown():
    """Clean up resources."""
    global http_client
    if http_client:
        await http_client.aclose()
    logger.info("Master server shutdown")


async def health_check_loop():
    """Background task to check worker health and clean up stale reservations."""
    while True:
        try:
            await registry.check_worker_health()
            # Clean up any stale pending counts (stuck reservations)
            await registry.cleanup_stale_pending()
        except Exception as e:
            logger.error(f"Health check error: {e}")
        await asyncio.sleep(config.health_check_interval_sec)


# =============================================================================
# Proxy Helper
# =============================================================================

async def proxy_request_to_worker(worker_slot: WorkerSlot, path: str) -> Response:
    """Proxy current request to a worker with circuit breaker support.

    Args:
        worker_slot: Immutable WorkerSlot with worker_id and url
        path: Path to proxy to on the worker

    Returns:
        Response from the worker or error response
    """
    # Generate request ID for tracing across master/worker logs
    request_id = f"{uuid.uuid4().hex[:8]}"

    target_url = f"{worker_slot.url}{path}"
    worker_id = worker_slot.worker_id

    # Timing: when did master START processing this request?
    master_received_at = time.time()

    # Forward headers (exclude hop-by-hop)
    excluded_headers = {'host', 'content-length', 'transfer-encoding', 'connection'}
    headers = {
        k: v for k, v in request.headers
        if k.lower() not in excluded_headers
    }

    # Add tracing headers for worker correlation
    headers['X-Request-ID'] = request_id
    headers['X-Master-Timestamp'] = str(master_received_at)

    # Get request body
    body = await request.get_data()
    body_ready_at = time.time()

    # Time spent in master before sending to worker
    master_prep_time = body_ready_at - master_received_at

    # Log for slow operations (reset, step)
    is_slow_op = '/reset' in path or '/step' in path
    if is_slow_op:
        logger.info(f"[PROXY:{request_id}] Starting {request.method} {path} -> {worker_id} "
                   f"(master_prep={master_prep_time:.3f}s, timeout={config.proxy_timeout_sec}s)")

    try:
        # Make async request to worker
        http_call_start = time.time()
        resp = await http_client.request(
            method=request.method,
            url=target_url,
            headers=headers,
            content=body,
            params=request.args,
        )
        http_call_end = time.time()

        # Timing breakdown
        total_elapsed = http_call_end - master_received_at
        network_and_worker_time = http_call_end - http_call_start

        # Track success - reset circuit breaker (async, thread-safe)
        await registry.record_request_success(worker_id)

        # Get worker-side timing from response headers if available
        worker_processing_time = resp.headers.get('X-Worker-Processing-Time')

        if is_slow_op:
            timing_info = (
                f"[PROXY:{request_id}] Completed {path} -> {worker_id} in {total_elapsed:.2f}s | "
                f"master_prep={master_prep_time:.3f}s, "
                f"network+worker={network_and_worker_time:.2f}s"
            )
            if worker_processing_time:
                timing_info += f", worker_reported={worker_processing_time}s"
            logger.info(timing_info)

        # Build response
        excluded_response_headers = {'content-encoding', 'content-length',
                                     'transfer-encoding', 'connection'}
        response_headers = {
            k: v for k, v in resp.headers.items()
            if k.lower() not in excluded_response_headers
        }

        return Response(
            resp.content,
            status=resp.status_code,
            headers=response_headers
        )

    except httpx.TimeoutException as e:
        total_elapsed = time.time() - master_received_at
        network_time = time.time() - body_ready_at
        await registry.record_request_failure(worker_id)
        logger.error(
            f"[PROXY:{request_id}] TIMEOUT after {total_elapsed:.2f}s proxying {path} to {worker_id}\n"
            f"  Timing breakdown:\n"
            f"    - Master prep (before HTTP call): {master_prep_time:.3f}s\n"
            f"    - Waiting for worker response: {network_time:.2f}s\n"
            f"  Timeout setting: {config.proxy_timeout_sec}s\n"
            f"  Target URL: {target_url}\n"
            f"  Diagnosis: If master_prep is high -> master is overloaded/blocked\n"
            f"             If waiting time ≈ timeout -> worker is slow or stuck\n"
            f"  Check worker logs for request_id={request_id}"
        )
        return jsonify({
            "error": "Worker timeout",
            "request_id": request_id,
            "worker_id": worker_id,
            "path": path,
            "timing": {
                "total_elapsed": round(total_elapsed, 3),
                "master_prep": round(master_prep_time, 3),
                "waiting_for_worker": round(network_time, 3),
                "timeout_setting": config.proxy_timeout_sec,
            },
            "diagnosis": "Check worker logs for request_id to see if request was received and where it got stuck"
        }), 504

    except httpx.ConnectError as e:
        total_elapsed = time.time() - master_received_at
        await registry.record_request_failure(worker_id)
        logger.error(
            f"[PROXY:{request_id}] Connection error after {total_elapsed:.2f}s to {worker_id}: {e}\n"
            f"  Target URL: {target_url}\n"
            f"  Master prep time: {master_prep_time:.3f}s"
        )
        return jsonify({
            "error": "Worker unreachable",
            "request_id": request_id,
            "worker_id": worker_id,
            "target_url": target_url,
            "elapsed_seconds": round(total_elapsed, 3)
        }), 503

    except Exception as e:
        total_elapsed = time.time() - master_received_at
        await registry.record_request_failure(worker_id)
        logger.error(f"[PROXY:{request_id}] Error after {total_elapsed:.2f}s proxying to {worker_id}: {e}")
        return jsonify({
            "error": str(e),
            "error_type": type(e).__name__,
            "request_id": request_id,
            "worker_id": worker_id,
            "elapsed_seconds": round(total_elapsed, 3)
        }), 500


# =============================================================================
# Worker Management Endpoints
# =============================================================================

@app.route('/workers/register', methods=['POST'])
async def register_worker_endpoint():
    """Register a worker with the master."""
    try:
        data = await request.get_json()

        worker_id = data.get("worker_id")
        url = data.get("url")
        hostname = data.get("hostname", "unknown")
        port = data.get("port", 0)
        max_envs = data.get("max_envs", config.default_max_envs_per_worker)
        metadata = data.get("metadata", {})

        if not worker_id or not url:
            return jsonify({"error": "Missing worker_id or url"}), 400

        worker = await registry.register_worker(
            worker_id=worker_id,
            url=url,
            hostname=hostname,
            port=port,
            max_envs=max_envs,
            metadata=metadata
        )

        return jsonify({
            "status": "registered",
            "worker_id": worker.worker_id,
            "master_time": time.time()
        }), 201

    except Exception as e:
        logger.error(f"Registration error: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/workers/heartbeat', methods=['POST'])
async def worker_heartbeat():
    """Receive heartbeat from a worker."""
    try:
        data = await request.get_json()

        worker_id = data.get("worker_id")
        env_count = data.get("env_count", 0)
        env_ids = data.get("env_ids", [])
        cpu_percent = data.get("cpu_percent", 0)
        memory_percent = data.get("memory_percent", 0)
        metrics = data.get("metrics")  # Full metrics from worker

        if not worker_id:
            return jsonify({"error": "Missing worker_id"}), 400

        success = await registry.update_heartbeat(
            worker_id=worker_id,
            env_count=env_count,
            env_ids=env_ids,
            cpu_percent=cpu_percent,
            memory_percent=memory_percent,
            metrics=metrics
        )

        if not success:
            # Worker not registered - tell it to re-register
            return jsonify({"error": "Worker not registered", "action": "reregister"}), 404

        return jsonify({
            "status": "ok",
            "master_time": time.time()
        })

    except Exception as e:
        logger.error(f"Heartbeat error: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/workers/deregister', methods=['POST'])
async def deregister_worker_endpoint():
    """Deregister a worker."""
    try:
        data = await request.get_json()

        worker_id = data.get("worker_id")
        reason = data.get("reason", "manual")

        if not worker_id:
            return jsonify({"error": "Missing worker_id"}), 400

        success = await registry.deregister_worker(worker_id, reason)

        if not success:
            return jsonify({"error": "Worker not found"}), 404

        return jsonify({"status": "deregistered"})

    except Exception as e:
        logger.error(f"Deregistration error: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/workers/drain', methods=['POST'])
async def drain_worker_endpoint():
    """Set worker to draining state - stops accepting new environments.

    Draining workers:
    - Continue serving existing environments
    - Don't accept new environment creations
    - Will eventually become idle and can be safely removed
    """
    try:
        data = await request.get_json()

        worker_id = data.get("worker_id")
        if not worker_id:
            return jsonify({"error": "Missing worker_id"}), 400

        success = await registry.drain_worker(worker_id)

        if not success:
            return jsonify({"error": "Worker not found"}), 404

        worker = await registry.get_worker(worker_id)
        return jsonify({
            "status": "draining",
            "worker_id": worker_id,
            "env_count": worker.get("env_count", 0) if worker else 0,
            "message": "Worker will not accept new environments"
        })

    except Exception as e:
        logger.error(f"Drain worker error: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/workers/undrain', methods=['POST'])
async def undrain_worker_endpoint():
    """Restore worker from draining to healthy state."""
    try:
        data = await request.get_json()

        worker_id = data.get("worker_id")
        if not worker_id:
            return jsonify({"error": "Missing worker_id"}), 400

        success = await registry.undrain_worker(worker_id)

        if not success:
            return jsonify({"error": "Worker not found"}), 404

        return jsonify({
            "status": "healthy",
            "worker_id": worker_id,
            "message": "Worker restored to healthy state"
        })

    except Exception as e:
        logger.error(f"Undrain worker error: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/workers/list', methods=['GET'])
async def list_workers():
    """List all registered workers."""
    try:
        stats = await registry.get_stats()
        return jsonify(stats)
    except Exception as e:
        logger.error(f"List workers error: {e}")
        return jsonify({"error": str(e)}), 500


# =============================================================================
# Environment Endpoints (Proxied)
# =============================================================================

@app.route('/envs/create', methods=['POST'])
async def create_environment():
    """Create environment on least-loaded worker with atomic slot reservation."""
    worker = None
    try:
        # ATOMIC: Select worker AND reserve slot in one operation
        # This prevents race conditions under heavy load
        worker = await registry.reserve_slot_for_new_env()

        if not worker:
            # Get counts for error message (these are quick operations)
            all_workers = await registry.get_all_workers()
            healthy_workers = await registry.get_healthy_workers()
            return jsonify({
                "error": "No healthy workers with capacity available",
                "total_workers": len(all_workers),
                "healthy_workers": len(healthy_workers)
            }), 503

        logger.info(f"Routing env creation to worker {worker.worker_id} "
                   f"(effective: {worker.effective_count}/{worker.max_envs}, "
                   f"pending: {worker.pending_count})")

        # Proxy to worker (reservation held during this async call)
        response = await proxy_request_to_worker(worker, "/envs/create")

        # Handle response
        if response.status_code == 201:
            response_data = response.get_json()
            if asyncio.iscoroutine(response_data):
                response_data = await response_data
            env_id = response_data.get("env_id") if response_data else None
            if env_id:
                # SUCCESS: Convert reservation to actual env
                await registry.confirm_reservation(worker.worker_id, env_id)
                logger.info(f"Created env {env_id} on worker {worker.worker_id}")
            else:
                # Got 201 but no env_id - release reservation
                await registry.release_reservation(worker.worker_id)
                logger.warning(f"Worker returned 201 but no env_id, releasing reservation")
        else:
            # FAILURE: Release the reservation
            await registry.release_reservation(worker.worker_id)
            logger.warning(f"Env creation failed (status={response.status_code}), released reservation")

        return response

    except Exception as e:
        # FAILURE: Release reservation on any exception
        if worker:
            await registry.release_reservation(worker.worker_id)
        logger.error(f"Create environment error: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/envs/<env_id>/close', methods=['POST'])
async def close_environment(env_id: str):
    """Close environment and clean up mapping."""
    try:
        worker = await registry.get_worker_for_env(env_id)

        if not worker:
            return jsonify({"error": f"Environment {env_id} not found"}), 404

        # Proxy to worker
        response = await proxy_request_to_worker(worker, f"/envs/{env_id}/close")

        # Clean up mapping regardless of response
        await registry.unregister_env(env_id)

        return response

    except Exception as e:
        logger.error(f"Close environment error: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/envs/<env_id>/<path:subpath>', methods=['GET', 'POST', 'PUT', 'DELETE'])
async def route_env_request(env_id: str, subpath: str):
    """Route environment request to appropriate worker."""
    try:
        worker = await registry.get_worker_for_env(env_id)

        if not worker:
            return jsonify({"error": f"Environment {env_id} not found"}), 404

        if worker.status not in ("healthy", "draining"):
            return jsonify({
                "error": f"Worker {worker.worker_id} is {worker.status}",
                "worker_id": worker.worker_id
            }), 503

        return await proxy_request_to_worker(worker, f"/envs/{env_id}/{subpath}")

    except Exception as e:
        logger.error(f"Route env request error: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/envs/list', methods=['GET'])
async def list_environments():
    """List all environments across all workers."""
    try:
        stats = await registry.get_stats()

        # Build environment list from all workers
        all_envs = {}
        for worker_data in stats["workers"]:
            for env_id in worker_data.get("env_ids", []):
                all_envs[env_id] = {
                    "worker_id": worker_data["worker_id"],
                    "worker_url": worker_data["url"],
                    "worker_status": worker_data["status"],
                }

        return jsonify({
            "environments": all_envs,
            "total": len(all_envs)
        })

    except Exception as e:
        logger.error(f"List environments error: {e}")
        return jsonify({"error": str(e)}), 500


# =============================================================================
# Health and Metrics Endpoints
# =============================================================================

@app.route('/health', methods=['GET'])
async def health_check():
    """Master health check with cluster status."""
    try:
        stats = await registry.get_stats()

        return jsonify({
            "status": "healthy",
            "role": "master",
            "uptime_sec": time.time() - start_time,
            "total_workers": stats["total_workers"],
            "healthy_workers": stats["healthy_workers"],
            "unhealthy_workers": stats["unhealthy_workers"],
            "dead_workers": stats["dead_workers"],
            "total_envs": stats["total_envs"],
            "total_capacity": stats["total_capacity"],
        })

    except Exception as e:
        logger.error(f"Health check error: {e}")
        return jsonify({"status": "error", "error": str(e)}), 500


@app.route('/api/metrics', methods=['GET'])
async def get_metrics():
    """Get aggregated metrics from all workers."""
    try:
        stats = await registry.get_stats()

        return jsonify({
            "master": {
                "uptime_sec": time.time() - start_time,
                "start_time": start_time,
            },
            "cluster": stats,
        })

    except Exception as e:
        logger.error(f"Get metrics error: {e}")
        return jsonify({"error": str(e)}), 500


# =============================================================================
# Dashboard
# =============================================================================

# Import dashboard template from separate file
try:
    from .dashboard_template import DASHBOARD_TEMPLATE
except ImportError:
    # Fallback minimal template
    DASHBOARD_TEMPLATE = """
<!DOCTYPE html>
<html><head><title>Gym-Anything Master</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
</head><body class="bg-dark text-light p-4">
<h1>Gym-Anything Master Dashboard</h1>
<p>Dashboard template not found. Please ensure dashboard_template.py exists.</p>
<pre id="metrics"></pre>
<script>
async function refresh() {
    const r = await fetch('/api/metrics');
    document.getElementById('metrics').textContent = JSON.stringify(await r.json(), null, 2);
    setTimeout(refresh, 5000);
}
refresh();
</script>
</body></html>
"""


@app.route('/dashboard')
async def dashboard():
    """Serve the master dashboard."""
    return await render_template_string(DASHBOARD_TEMPLATE)


@app.route('/')
async def index():
    """Redirect to dashboard."""
    return await dashboard()


# =============================================================================
# Main
# =============================================================================

def find_available_port(start_range: int = 5000, end_range: int = 5999,
                        max_attempts: int = 50) -> int:
    """Find an available port with random selection and retry."""
    for attempt in range(max_attempts):
        port = random.randint(start_range, end_range)
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.bind(('', port))
                return port
        except OSError:
            continue
    raise RuntimeError(f"Could not find available port after {max_attempts} attempts")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description="Gym-Anything Master Server")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
    parser.add_argument("--port", type=int, default=5000, help="Port to bind to")
    parser.add_argument("--auto-port", action="store_true",
                       help="Auto-select available port if specified port is taken")
    parser.add_argument("--heartbeat-timeout", type=int, default=90,
                       help="Seconds without heartbeat before marking worker unhealthy")
    parser.add_argument("--dead-timeout", type=int, default=300,
                       help="Seconds without heartbeat before marking worker dead")
    parser.add_argument("--proxy-timeout", type=int, default=600,
                       help="Seconds to wait for worker response when proxying (default: 600)")
    parser.add_argument("--workers", type=int, default=1,
                       help="Number of worker processes (default: 1, must be 1 for stateful registry)")
    parser.add_argument("--dev", action="store_true",
                       help="Use development server (single-threaded, for debugging only)")

    args = parser.parse_args()

    # Update config
    config.host = args.host
    config.port = args.port
    config.heartbeat_timeout_sec = args.heartbeat_timeout
    config.dead_timeout_sec = args.dead_timeout
    config.proxy_timeout_sec = args.proxy_timeout

    # Find available port if needed
    port = args.port
    if args.auto_port:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.bind(('', port))
        except OSError:
            port = find_available_port()
            logger.info(f"Port {args.port} in use, using {port} instead")

    logger.info("=" * 70)
    logger.info(f"Starting Gym-Anything Master Server on {args.host}:{port}")
    logger.info(f"Dashboard: http://{args.host}:{port}/dashboard")
    logger.info(f"Heartbeat timeout: {config.heartbeat_timeout_sec}s")
    logger.info(f"Dead timeout: {config.dead_timeout_sec}s")
    logger.info(f"Proxy timeout: {config.proxy_timeout_sec}s")

    if args.dev:
        logger.info("Mode: DEVELOPMENT (single-threaded, not for production!)")
        logger.info("=" * 70)
        app.run(host=args.host, port=port)
    else:
        # Warn if using multiple workers with in-memory registry
        if args.workers > 1:
            logger.warning("WARNING: Using multiple workers with in-memory registry!")
            logger.warning("Each worker has separate state - worker registration may not work correctly.")
            logger.warning("Use --workers=1 (default) for correct behavior.")

        logger.info(f"Mode: PRODUCTION (hypercorn, async with {args.workers} process(es))")
        logger.info("=" * 70)

        # Configure hypercorn for production
        hypercorn_config = HypercornConfig()
        hypercorn_config.bind = [f"{args.host}:{port}"]
        hypercorn_config.workers = args.workers
        hypercorn_config.accesslog = "-"  # Log to stdout
        hypercorn_config.errorlog = "-"
        hypercorn_config.keep_alive_timeout = 120
        hypercorn_config.graceful_timeout = 30

        # Run with hypercorn - uses asyncio event loop for true async concurrency
        asyncio.run(hypercorn_serve(app, hypercorn_config))


if __name__ == "__main__":
    main()
