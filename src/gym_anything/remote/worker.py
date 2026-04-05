#!/usr/bin/env python3
"""
Gym-Anything Worker Server

A Flask-based REST API server that manages Gym-Anything environments remotely.
Registers with a master server for load balancing and health monitoring.

Based on remote_server_monitored.py with additions:
- Auto port selection with retry
- Master registration with exponential backoff
- Heartbeat in separate thread (non-blocking)
- UUID-based worker ID

Usage:
    python -m gym_anything.remote.worker --master-url http://master:5000 [--port PORT] [--max-envs N]
"""

from __future__ import annotations

import argparse
import atexit
import json
import logging
import os
import platform
import random
import signal
import socket
import sys
import threading
import time
import uuid
from dataclasses import asdict
from pathlib import Path
from typing import Any, Dict, List, Optional
from urllib.parse import urlparse

import psutil
import requests
from flask import Flask, request, jsonify, send_file, render_template_string
from flask_cors import CORS

from gym_anything.api import from_config, make
from gym_anything.env import GymAnythingEnv
from gym_anything.specs import EnvSpec, TaskSpec

from .dashboard_template import DASHBOARD_TEMPLATE
from .monitoring import SessionManager, get_metrics_collector, track_endpoint
from .worker_reset_policy import (
    DEFAULT_WORKER_RESET_POLICY,
    InvalidResetPolicyError,
    apply_worker_reset_policy,
)
MONITORING_AVAILABLE = True

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


# =============================================================================
# Configuration
# =============================================================================

class WorkerConfig:
    """Worker server configuration."""
    host: str = "0.0.0.0"
    port: int = 0  # 0 = auto-select
    port_range_start: int = 5100
    port_range_end: int = 5999
    port_max_attempts: int = 50

    # Master connection
    master_url: Optional[str] = None
    worker_id: Optional[str] = None

    # Capacity
    max_envs: int = 5
    timeout_seconds: int = 2700  # 45 minutes default
    reset_policy: str = os.environ.get("GYM_ANYTHING_WORKER_RESET_POLICY", DEFAULT_WORKER_RESET_POLICY)

    # Heartbeat
    heartbeat_interval_sec: int = 30

    # Registration retry
    registration_max_attempts: int = 10
    registration_initial_delay: float = 1.0
    registration_max_delay: float = 60.0


config = WorkerConfig()


# =============================================================================
# Port Selection
# =============================================================================

def find_available_port(start_range: int = 5100, end_range: int = 5999,
                        max_attempts: int = 50) -> int:
    """Find an available port with random selection and retry."""
    for attempt in range(max_attempts):
        port = random.randint(start_range, end_range)
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                s.bind(('', port))
                logger.info(f"Found available port: {port} (attempt {attempt + 1})")
                return port
        except OSError:
            continue

    raise RuntimeError(f"Could not find available port in range {start_range}-{end_range} "
                      f"after {max_attempts} attempts")


def try_bind_port(port: int) -> bool:
    """Check if a port is available."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind(('', port))
            return True
    except OSError:
        return False


# =============================================================================
# Retry Helper
# =============================================================================

def retry_with_backoff(func, max_attempts: int = 10, initial_delay: float = 1.0,
                       max_delay: float = 60.0, description: str = "operation"):
    """Retry function with exponential backoff."""
    delay = initial_delay

    for attempt in range(max_attempts):
        try:
            return func()
        except Exception as e:
            if attempt == max_attempts - 1:
                logger.error(f"{description} failed after {max_attempts} attempts: {e}")
                raise

            jitter = random.uniform(0, 0.1 * delay)
            sleep_time = delay + jitter
            logger.warning(f"{description} attempt {attempt + 1}/{max_attempts} failed: {e}. "
                          f"Retrying in {sleep_time:.1f}s...")
            time.sleep(sleep_time)
            delay = min(delay * 2, max_delay)


# =============================================================================
# Flask App
# =============================================================================

app = Flask(__name__)
CORS(app)

# Global environment registry
env_registry: Dict[str, Dict[str, Any]] = {}
registry_lock = threading.Lock()

# Cleanup configuration
CLEANUP_INTERVAL = 60  # Check for idle environments every 60 seconds

# Initialize monitoring (if available)
if MONITORING_AVAILABLE:
    metrics_collector = get_metrics_collector()
    session_manager = SessionManager(sessions_dir="monitoring_sessions", auto_save_interval=300)
else:
    metrics_collector = None
    session_manager = None


# =============================================================================
# Environment Manager
# =============================================================================

class EnvironmentManager:
    """Manages remote environment instances with timeout-based cleanup."""

    def __init__(self, timeout_seconds: int = 2700):
        self.timeout_seconds = timeout_seconds
        self.cleanup_thread: Optional[threading.Thread] = None
        self.stop_event = threading.Event()

    def start_cleanup_thread(self):
        """Start background cleanup thread."""
        self.stop_event.clear()
        self.cleanup_thread = threading.Thread(target=self._cleanup_loop, daemon=True)
        self.cleanup_thread.start()
        logger.info(f"Started cleanup thread with timeout={self.timeout_seconds}s")

    def stop_cleanup_thread(self):
        """Stop background cleanup thread."""
        if self.cleanup_thread:
            self.stop_event.set()
            self.cleanup_thread.join(timeout=5)
            logger.info("Stopped cleanup thread")

    def _cleanup_loop(self):
        """Background loop that cleans up idle environments."""
        while not self.stop_event.is_set():
            try:
                self._cleanup_idle_environments()
            except Exception as e:
                logger.error(f"Error in cleanup loop: {e}", exc_info=True)

            for _ in range(CLEANUP_INTERVAL):
                if self.stop_event.is_set():
                    break
                time.sleep(1)

    def _cleanup_idle_environments(self):
        """Remove environments that have been idle for too long."""
        current_time = time.time()
        to_remove = []

        with registry_lock:
            for env_id, env_data in env_registry.items():
                last_activity = env_data.get("last_activity", 0)
                idle_time = current_time - last_activity

                if idle_time > self.timeout_seconds:
                    to_remove.append(env_id)
                    logger.info(f"Environment {env_id} idle for {idle_time:.1f}s, scheduling cleanup")

        for env_id in to_remove:
            try:
                self.remove_environment(env_id, reason="timeout")
            except Exception as e:
                logger.error(f"Error removing idle environment {env_id}: {e}", exc_info=True)

    def create_environment(self, env_spec_dict: Dict[str, Any],
                          task_spec_dict: Optional[Dict[str, Any]] = None,
                          env_dir: Optional[str] = None,
                          task_id: Optional[str] = None,
                          metadata: Optional[Dict[str, Any]] = None) -> str:
        """Create a new environment instance and return its ID."""
        env_id = str(uuid.uuid4())

        try:
            if env_dir:
                env = from_config(env_dir, task_id=task_id)
            else:
                env_spec = EnvSpec.from_dict(env_spec_dict) if env_spec_dict else None
                task_spec = TaskSpec.from_dict(task_spec_dict) if task_spec_dict else None
                env = make(env_spec, task_spec)

            with registry_lock:
                env_registry[env_id] = {
                    "env": env,
                    "last_activity": time.time(),
                    "created_at": time.time(),
                    "metadata": metadata or {},
                    "env_dir": env_dir,
                    "task_id": task_id,
                }

            if metrics_collector:
                try:
                    metrics_collector.log_env_created(env_id, env_dir, task_id, metadata)
                except Exception:
                    pass

            logger.info(f"Created environment {env_id} (env_dir={env_dir}, task_id={task_id})")
            return env_id

        except Exception as e:
            logger.error(f"Failed to create environment: {e}", exc_info=True)
            raise

    def get_environment(self, env_id: str) -> GymAnythingEnv:
        """Get environment instance and update activity timestamp."""
        with registry_lock:
            if env_id not in env_registry:
                raise ValueError(f"Environment {env_id} not found")

            env_data = env_registry[env_id]
            env_data["last_activity"] = time.time()

            if metrics_collector:
                try:
                    metrics_collector.log_env_activity(env_id)
                except Exception:
                    pass

            return env_data["env"]

    def remove_environment(self, env_id: str, reason: str = "manual"):
        """Remove and close an environment."""
        with registry_lock:
            if env_id not in env_registry:
                logger.warning(f"Environment {env_id} not found for removal")
                return

            env_data = env_registry.pop(env_id)

        try:
            env = env_data["env"]
            env.close()
            logger.info(f"Removed environment {env_id} (reason={reason})")

            if metrics_collector:
                try:
                    metrics_collector.log_env_closed(env_id, reason)
                except Exception:
                    pass

        except Exception as e:
            logger.error(f"Error closing environment {env_id}: {e}", exc_info=True)

    def list_environments(self) -> Dict[str, Dict[str, Any]]:
        """List all active environments with metadata."""
        with registry_lock:
            return {
                env_id: {
                    "last_activity": data["last_activity"],
                    "created_at": data["created_at"],
                    "idle_seconds": time.time() - data["last_activity"],
                    "metadata": data.get("metadata", {}),
                    "env_dir": data.get("env_dir"),
                    "task_id": data.get("task_id"),
                }
                for env_id, data in env_registry.items()
            }

    def get_env_count(self) -> int:
        """Get current environment count."""
        with registry_lock:
            return len(env_registry)

    def get_env_ids(self) -> List[str]:
        """Get list of all environment IDs."""
        with registry_lock:
            return list(env_registry.keys())


# Global environment manager
env_manager = EnvironmentManager()


# =============================================================================
# Master Integration
# =============================================================================

class MasterClient:
    """Handles communication with master server."""

    def __init__(self, master_url: str, worker_id: str, worker_url: str,
                 hostname: str, port: int, max_envs: int):
        # Normalize master URL to just scheme+host+port (strip any path like /dashboard)
        parsed = urlparse(master_url)
        if parsed.port:
            self.master_url = f"{parsed.scheme}://{parsed.hostname}:{parsed.port}"
        else:
            self.master_url = f"{parsed.scheme}://{parsed.hostname}"
        logger.info(f"Master URL normalized: {master_url} -> {self.master_url}")
        self.worker_id = worker_id
        self.worker_url = worker_url
        self.hostname = hostname
        self.port = port
        self.max_envs = max_envs
        self.registered = False
        self.last_heartbeat_error: Optional[str] = None

    def register(self) -> bool:
        """Register with master server."""
        def do_register():
            response = requests.post(
                f"{self.master_url}/workers/register",
                json={
                    "worker_id": self.worker_id,
                    "url": self.worker_url,
                    "hostname": self.hostname,
                    "port": self.port,
                    "max_envs": self.max_envs,
                    "metadata": {
                        "slurm_job_id": os.environ.get("SLURM_JOB_ID"),
                        "slurm_array_task_id": os.environ.get("SLURM_ARRAY_TASK_ID"),
                        "pid": os.getpid(),
                    }
                },
                timeout=30
            )
            response.raise_for_status()
            return response.json()

        try:
            result = retry_with_backoff(
                do_register,
                max_attempts=config.registration_max_attempts,
                initial_delay=config.registration_initial_delay,
                max_delay=config.registration_max_delay,
                description="Master registration"
            )
            self.registered = True
            logger.info(f"Registered with master: {result}")
            return True
        except Exception as e:
            logger.error(f"Failed to register with master: {e}")
            return False

    def send_heartbeat(self) -> bool:
        """Send heartbeat to master with full metrics."""
        if not self.registered:
            return False

        try:
            # Collect stats
            env_count = env_manager.get_env_count()
            env_ids = env_manager.get_env_ids()

            cpu_percent = 0
            memory_percent = 0
            try:
                cpu_percent = psutil.cpu_percent(interval=0.1)
                memory_percent = psutil.virtual_memory().percent
            except Exception:
                pass

            # Collect full metrics from monitoring if available
            full_metrics = None
            if metrics_collector:
                try:
                    full_metrics = metrics_collector.get_stats()
                except Exception:
                    pass

            response = requests.post(
                f"{self.master_url}/workers/heartbeat",
                json={
                    "worker_id": self.worker_id,
                    "env_count": env_count,
                    "env_ids": env_ids,
                    "cpu_percent": cpu_percent,
                    "memory_percent": memory_percent,
                    "status": "healthy",
                    "metrics": full_metrics,  # Full metrics including endpoint stats, activity log, timeline
                },
                timeout=10
            )

            if response.status_code == 404:
                # Master doesn't know us - re-register
                logger.warning("Master returned 404, attempting re-registration")
                self.registered = False
                return self.register()

            response.raise_for_status()
            self.last_heartbeat_error = None
            return True

        except Exception as e:
            self.last_heartbeat_error = str(e)
            logger.warning(f"Heartbeat failed: {e}")
            return False

    def deregister(self, reason: str = "shutdown") -> bool:
        """Deregister from master server."""
        if not self.registered:
            return True

        try:
            response = requests.post(
                f"{self.master_url}/workers/deregister",
                json={
                    "worker_id": self.worker_id,
                    "reason": reason,
                },
                timeout=10
            )
            response.raise_for_status()
            self.registered = False
            logger.info(f"Deregistered from master (reason: {reason})")
            return True
        except Exception as e:
            logger.error(f"Failed to deregister from master: {e}")
            return False


class HeartbeatManager:
    """Manages heartbeat in dedicated thread, never blocked by Flask."""

    def __init__(self, master_client: MasterClient, interval: int = 30):
        self.master_client = master_client
        self.interval = interval
        self._stop_event = threading.Event()
        self._thread: Optional[threading.Thread] = None

    def start(self):
        """Start heartbeat in DAEMON thread."""
        self._stop_event.clear()
        self._thread = threading.Thread(target=self._heartbeat_loop, daemon=True)
        self._thread.start()
        logger.info(f"Started heartbeat thread (interval={self.interval}s)")

    def stop(self):
        """Stop heartbeat thread."""
        self._stop_event.set()
        if self._thread:
            self._thread.join(timeout=5)
        logger.info("Stopped heartbeat thread")

    def _heartbeat_loop(self):
        """Runs independently of Flask threads."""
        while not self._stop_event.wait(timeout=self.interval):
            try:
                self.master_client.send_heartbeat()
            except Exception as e:
                logger.error(f"Heartbeat loop error: {e}")


# Global master client and heartbeat manager
master_client: Optional[MasterClient] = None
heartbeat_manager: Optional[HeartbeatManager] = None


# =============================================================================
# Serialization Helpers
# =============================================================================

def serialize_observation(obs: Dict[str, Any]) -> Dict[str, Any]:
    """Serialize observation for JSON response, marking remote paths."""
    serialized = {}
    for key, value in obs.items():
        if isinstance(value, dict):
            serialized[key] = dict(value)
            if "path" in value:
                serialized[key]["remote"] = True
        else:
            serialized[key] = value
    return serialized


def serialize_response(data: Any) -> Any:
    """Recursively serialize data for JSON response."""
    if isinstance(data, dict):
        return {k: serialize_response(v) for k, v in data.items()}
    elif isinstance(data, (list, tuple)):
        return [serialize_response(item) for item in data]
    elif isinstance(data, Path):
        return str(data)
    elif hasattr(data, '__dict__'):
        return serialize_response(vars(data))
    else:
        return data


# =============================================================================
# API Endpoints
# =============================================================================

@app.route('/health', methods=['GET'])
@track_endpoint
def health_check():
    """Health check endpoint."""
    master_status = "not_configured"
    if master_client:
        if master_client.registered:
            master_status = "registered"
        else:
            master_status = "not_registered"

    return jsonify({
        "status": "healthy",
        "role": "worker",
        "worker_id": config.worker_id,
        "active_environments": env_manager.get_env_count(),
        "max_environments": config.max_envs,
        "timeout_seconds": env_manager.timeout_seconds,
        "master_url": config.master_url,
        "master_status": master_status,
        "monitoring_enabled": MONITORING_AVAILABLE,
    })


@app.route('/worker/info', methods=['GET'])
@track_endpoint
def worker_info():
    """Detailed worker information."""
    return jsonify({
        "worker_id": config.worker_id,
        "hostname": socket.gethostname(),
        "port": config.port,
        "max_envs": config.max_envs,
        "env_count": env_manager.get_env_count(),
        "env_ids": env_manager.get_env_ids(),
        "master_url": config.master_url,
        "master_registered": master_client.registered if master_client else False,
        "cpu_percent": psutil.cpu_percent(interval=0.1),
        "memory_percent": psutil.virtual_memory().percent,
    })


@app.route('/envs/create', methods=['POST'])
@track_endpoint
def create_environment():
    """Create a new environment instance."""
    try:
        # Check capacity
        if env_manager.get_env_count() >= config.max_envs:
            return jsonify({
                "error": "Worker at capacity",
                "current": env_manager.get_env_count(),
                "max": config.max_envs
            }), 503

        data = request.get_json() or {}

        env_spec_dict = data.get("env_spec")
        task_spec_dict = data.get("task_spec")
        env_dir = data.get("env_dir")
        task_id = data.get("task_id")
        metadata = data.get("metadata", {})

        env_id = env_manager.create_environment(
            env_spec_dict=env_spec_dict,
            task_spec_dict=task_spec_dict,
            env_dir=env_dir,
            task_id=task_id,
            metadata=metadata
        )

        return jsonify({"env_id": env_id}), 201

    except Exception as e:
        logger.error(f"Error creating environment: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


@app.route('/envs/<env_id>/reset', methods=['POST'])
@track_endpoint
def reset_environment(env_id: str):
    """Reset an environment with detailed timing logs."""
    reset_start = time.time()
    timings = {}

    # Get tracing info from master (if proxied through master)
    request_id = request.headers.get('X-Request-ID', 'direct')
    master_timestamp = request.headers.get('X-Master-Timestamp')

    # Calculate network latency if master timestamp available
    network_latency = None
    if master_timestamp:
        try:
            master_ts = float(master_timestamp)
            network_latency = reset_start - master_ts
            timings['network_latency'] = network_latency
        except (ValueError, TypeError):
            pass

    logger.info(f"[{env_id}] Reset request received (request_id={request_id}, "
               f"network_latency={network_latency:.3f}s)" if network_latency else
               f"[{env_id}] Reset request received (request_id={request_id})")

    try:
        # Phase 1: Get environment
        t0 = time.time()
        env = env_manager.get_environment(env_id)
        timings['get_env'] = time.time() - t0

        data = request.get_json() or {}
        seed = data.get("seed")
        use_cache = data.get("use_cache", False)
        cache_level = data.get("cache_level", "pre_start")
        use_savevm = data.get("use_savevm", False)
        post_reset_policy = data.get("post_reset_policy", config.reset_policy)

        # Phase 2: Reset environment (this can be slow - VM operations)
        t0 = time.time()
        logger.info(
            f"[{env_id}] Starting env.reset(seed={seed}, use_cache={use_cache}, "
            f"cache_level={cache_level}, use_savevm={use_savevm})..."
        )
        obs = env.reset(
            seed=seed,
            use_cache=use_cache,
            cache_level=cache_level,
            use_savevm=use_savevm,
        )
        timings['env_reset'] = time.time() - t0
        logger.info(f"[{env_id}] env.reset() completed in {timings['env_reset']:.2f}s")

        if metrics_collector:
            try:
                metrics_collector.log_env_reset(env_id)
            except Exception:
                pass

        logger.info(f"[{env_id}] Episode dir: {env.episode_dir}")

        # Phase 3: Apply optional worker-local reset policy
        policy_timings = apply_worker_reset_policy(
            env,
            post_reset_policy,
            logger=logger,
        )
        timings.update(policy_timings)
        logger.info(
            f"[{env_id}] Applied post_reset_policy={post_reset_policy} "
            f"in {policy_timings['apply_reset_policy']:.2f}s"
        )

        # Phase 4: Serialize observation
        t0 = time.time()
        serialized_obs = serialize_observation(obs)
        timings['serialize'] = time.time() - t0

        total_time = time.time() - reset_start
        timings['total'] = total_time

        # Log summary
        logger.info(
            f"[{env_id}] Reset completed in {total_time:.2f}s (request_id={request_id}) | "
            f"env_reset={timings['env_reset']:.2f}s, "
            f"policy={timings['apply_reset_policy']:.2f}s, "
            f"other={total_time - timings['env_reset'] - timings['apply_reset_policy']:.2f}s"
        )

        # Build response with timing header for master correlation
        response = jsonify({
            "observation": serialized_obs,
            "_timings": timings,  # Include timings for debugging
            "_request_id": request_id,
            "_post_reset_policy": post_reset_policy,
        })
        response.headers['X-Worker-Processing-Time'] = f"{total_time:.3f}"
        response.headers['X-Request-ID'] = request_id
        return response

    except InvalidResetPolicyError as e:
        elapsed = time.time() - reset_start
        logger.error(f"[{env_id}] Invalid reset policy after {elapsed:.2f}s: {e}")
        return jsonify({
            "error": str(e),
            "error_type": type(e).__name__,
            "request_id": request_id,
            "elapsed_seconds": elapsed,
            "timings": timings,
        }), 400
    except ValueError as e:
        elapsed = time.time() - reset_start
        logger.error(f"[{env_id}] Reset failed after {elapsed:.2f}s (request_id={request_id}, ValueError): {e}")
        return jsonify({
            "error": str(e),
            "error_type": "ValueError",
            "request_id": request_id,
            "elapsed_seconds": elapsed,
            "timings": timings
        }), 404
    except Exception as e:
        elapsed = time.time() - reset_start
        logger.error(f"[{env_id}] Reset failed after {elapsed:.2f}s (request_id={request_id}): {e}", exc_info=True)
        return jsonify({
            "error": str(e),
            "error_type": type(e).__name__,
            "request_id": request_id,
            "elapsed_seconds": elapsed,
            "timings": timings,
            "hint": "Check worker logs for full traceback"
        }), 500


@app.route('/envs/<env_id>/step', methods=['POST'])
@track_endpoint
def step_environment(env_id: str):
    """Execute a step in the environment."""
    try:
        env = env_manager.get_environment(env_id)
        data = request.get_json() or {}

        actions = data.get("actions", [])
        wait_between_actions = data.get("wait_between_actions", 0.2)
        mark_done = data.get("mark_done", False)

        obs, reward, done, info = env.step(
            actions=actions,
            wait_between_actions=wait_between_actions,
            mark_done=mark_done
        )

        if metrics_collector:
            try:
                action_count = len(actions) if isinstance(actions, list) else 1
                metrics_collector.log_env_step(env_id, action_count)
            except Exception:
                pass

        serialized_obs = serialize_observation(obs)
        serialized_info = serialize_response(info)

        return jsonify({
            "observation": serialized_obs,
            "reward": float(reward),
            "done": bool(done),
            "info": serialized_info,
        })

    except ValueError as e:
        return jsonify({"error": str(e)}), 404
    except Exception as e:
        logger.error(f"Error stepping environment {env_id}: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


@app.route('/envs/<env_id>/close', methods=['POST'])
@track_endpoint
def close_environment(env_id: str):
    """Close an environment and remove it from registry."""
    try:
        env_manager.remove_environment(env_id, reason="manual")
        return jsonify({"status": "closed"})

    except Exception as e:
        logger.error(f"Error closing environment {env_id}: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


@app.route('/envs/<env_id>/capture_observation', methods=['POST'])
@track_endpoint
def capture_observation(env_id: str):
    """Capture current observation without stepping."""
    try:
        env = env_manager.get_environment(env_id)
        obs = env.capture_observation()
        serialized_obs = serialize_observation(obs)

        return jsonify({"observation": serialized_obs})

    except ValueError as e:
        return jsonify({"error": str(e)}), 404
    except Exception as e:
        logger.error(f"Error capturing observation for {env_id}: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


@app.route('/envs/list', methods=['GET'])
@track_endpoint
def list_environments():
    """List all active environments."""
    try:
        envs = env_manager.list_environments()
        return jsonify({"environments": envs})

    except Exception as e:
        logger.error(f"Error listing environments: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


@app.route('/envs/<env_id>/fetch_path', methods=['GET'])
@track_endpoint
def fetch_path(env_id: str):
    """Fetch a file from the environment's episode directory."""
    try:
        env = env_manager.get_environment(env_id)
        remote_path = request.args.get('path')

        if not remote_path:
            return jsonify({"error": "Missing 'path' parameter"}), 400

        file_path = Path(remote_path)

        if not file_path.exists():
            return jsonify({"error": f"File not found: {remote_path}"}), 404

        if not file_path.is_file():
            return jsonify({"error": f"Path is not a file: {remote_path}"}), 400

        return send_file(
            file_path,
            as_attachment=True,
            download_name=file_path.name
        )

    except ValueError as e:
        return jsonify({"error": str(e)}), 404
    except Exception as e:
        logger.error(f"Error fetching path for {env_id}: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


@app.route('/envs/<env_id>/episode_dir', methods=['GET'])
@track_endpoint
def get_episode_dir(env_id: str):
    """Get the episode directory path."""
    try:
        env = env_manager.get_environment(env_id)
        episode_dir = str(env.episode_dir) if env.episode_dir else None

        return jsonify({"episode_dir": episode_dir})

    except ValueError as e:
        return jsonify({"error": str(e)}), 404
    except Exception as e:
        logger.error(f"Error getting episode_dir for {env_id}: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


@app.route('/envs/<env_id>/session_info', methods=['GET'])
@track_endpoint
def get_session_info(env_id: str):
    """Get stable session metadata for the active environment."""
    try:
        env = env_manager.get_environment(env_id)
        session = env.get_session_info()
        return jsonify({"session": session.to_dict() if session else None})

    except ValueError as e:
        return jsonify({"error": str(e)}), 404
    except Exception as e:
        logger.error(f"Error getting session_info for {env_id}: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


@app.route('/envs/<env_id>/save_state', methods=['POST'])
@track_endpoint
def save_state(env_id: str):
    """Save environment state."""
    try:
        env = env_manager.get_environment(env_id)
        data = request.get_json() or {}

        host_snapshot_path = data.get("host_snapshot_path")
        snapshot_path = env.save_state(host_snapshot_path=host_snapshot_path)

        return jsonify({"snapshot_path": str(snapshot_path) if snapshot_path else None})

    except ValueError as e:
        return jsonify({"error": str(e)}), 404
    except Exception as e:
        logger.error(f"Error saving state for {env_id}: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


@app.route('/envs/<env_id>/load_state', methods=['POST'])
@track_endpoint
def load_state(env_id: str):
    """Load environment state from snapshot."""
    try:
        env = env_manager.get_environment(env_id)
        data = request.get_json() or {}

        host_snapshot_path = data.get("host_snapshot_path")
        if not host_snapshot_path:
            return jsonify({"error": "Missing 'host_snapshot_path'"}), 400

        env.load_state(host_snapshot_path=host_snapshot_path)

        return jsonify({"status": "loaded"})

    except ValueError as e:
        return jsonify({"error": str(e)}), 404
    except Exception as e:
        logger.error(f"Error loading state for {env_id}: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


@app.route('/envs/<env_id>/pause_recording', methods=['POST'])
@track_endpoint
def pause_recording(env_id: str):
    """Pause recording for environment."""
    try:
        env = env_manager.get_environment(env_id)
        env.pause_recording()

        return jsonify({"status": "paused"})

    except ValueError as e:
        return jsonify({"error": str(e)}), 404
    except Exception as e:
        logger.error(f"Error pausing recording for {env_id}: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


@app.route('/envs/<env_id>/resume_recording', methods=['POST'])
@track_endpoint
def resume_recording(env_id: str):
    """Resume recording for environment."""
    try:
        env = env_manager.get_environment(env_id)
        env.resume_recording()

        return jsonify({"status": "resumed"})

    except ValueError as e:
        return jsonify({"error": str(e)}), 404
    except Exception as e:
        logger.error(f"Error resuming recording for {env_id}: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


@app.route('/envs/<env_id>/copy_to_env', methods=['POST'])
@track_endpoint
def copy_to_env(env_id: str):
    """Copy file to environment."""
    try:
        env = env_manager.get_environment(env_id)
        data = request.get_json() or {}

        host_src = data.get("host_src")
        container_dst = data.get("container_dst")

        if not host_src or not container_dst:
            return jsonify({"error": "Missing 'host_src' or 'container_dst'"}), 400

        env.copy_to_env(host_src=host_src, container_dst=container_dst)

        return jsonify({"status": "copied"})

    except ValueError as e:
        return jsonify({"error": str(e)}), 404
    except Exception as e:
        logger.error(f"Error copying to env {env_id}: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


@app.route('/envs/<env_id>/copy_from_env', methods=['POST'])
@track_endpoint
def copy_from_env(env_id: str):
    """Copy file from environment."""
    try:
        env = env_manager.get_environment(env_id)
        data = request.get_json() or {}

        container_src = data.get("container_src")
        host_dst = data.get("host_dst")

        if not container_src or not host_dst:
            return jsonify({"error": "Missing 'container_src' or 'host_dst'"}), 400

        env.copy_from_env(container_src=container_src, host_dst=host_dst)

        return jsonify({"status": "copied"})

    except ValueError as e:
        return jsonify({"error": str(e)}), 404
    except Exception as e:
        logger.error(f"Error copying from env {env_id}: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


# =============================================================================
# Dashboard (if monitoring available)
# =============================================================================

@app.route('/dashboard')
def dashboard():
    """Serve the monitoring dashboard."""
    if not MONITORING_AVAILABLE:
        return jsonify({"error": "Monitoring not available"}), 404

    try:
        return render_template_string(DASHBOARD_TEMPLATE)
    except Exception as e:
        logger.error(f"Error loading dashboard template: {e}", exc_info=True)
        return jsonify({"error": "Dashboard template not found"}), 500


@app.route('/api/metrics', methods=['GET'])
@track_endpoint
def get_metrics():
    """Get current metrics snapshot."""
    if not metrics_collector:
        return jsonify({"error": "Monitoring not available"}), 404

    try:
        stats = metrics_collector.get_stats()
        return jsonify(stats)
    except Exception as e:
        logger.error(f"Error getting metrics: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


# =============================================================================
# Shutdown Handling
# =============================================================================

def graceful_shutdown(signum=None, frame=None):
    """Handle graceful shutdown."""
    logger.info("Initiating graceful shutdown...")

    # Deregister from master
    if master_client:
        master_client.deregister(reason="shutdown")

    # Stop heartbeat
    if heartbeat_manager:
        heartbeat_manager.stop()

    # Stop cleanup thread
    env_manager.stop_cleanup_thread()

    # Close all environments
    for env_id in list(env_registry.keys()):
        try:
            env_manager.remove_environment(env_id, reason="shutdown")
        except Exception as e:
            logger.error(f"Error closing env {env_id} during shutdown: {e}")

    # Save session if monitoring available
    if session_manager and metrics_collector:
        try:
            session_manager.save_session(metrics_collector)
            logger.info("Saved final session")
        except Exception as e:
            logger.error(f"Failed to save final session: {e}")

    logger.info("Shutdown complete")


# =============================================================================
# Main
# =============================================================================

def main():
    """Main entry point."""
    global master_client, heartbeat_manager

    parser = argparse.ArgumentParser(description="Gym-Anything Worker Server")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
    parser.add_argument("--port", type=int, default=0,
                       help="Port to bind to (0 = auto-select)")
    parser.add_argument("--master-url", type=str, default=None,
                       help="Master server URL for registration")
    parser.add_argument("--worker-id", type=str, default=None,
                       help="Worker ID (auto-generated if not provided)")
    parser.add_argument("--max-envs", type=int, default=10,
                       help="Maximum concurrent environments")
    parser.add_argument("--timeout", type=int, default=2700,
                       help="Environment idle timeout in seconds")
    parser.add_argument("--heartbeat-interval", type=int, default=30,
                       help="Heartbeat interval in seconds")
    parser.add_argument(
        "--advertise-host",
        type=str,
        default=None,
        help="Hostname or IP advertised to the master. Defaults to --host when it is specific, otherwise the system hostname.",
    )
    parser.add_argument("--debug", action="store_true", help="Enable debug mode")

    args = parser.parse_args()

    # Update config
    config.host = args.host
    config.master_url = args.master_url
    config.max_envs = args.max_envs
    config.timeout_seconds = args.timeout

    # Generate worker ID if not provided
    if args.worker_id:
        config.worker_id = args.worker_id
    else:
        config.worker_id = f"worker-{uuid.uuid4().hex[:12]}"

    # Find available port
    if args.port == 0:
        config.port = find_available_port(
            start_range=config.port_range_start,
            end_range=config.port_range_end,
            max_attempts=config.port_max_attempts
        )
    else:
        if not try_bind_port(args.port):
            logger.warning(f"Port {args.port} not available, finding alternative...")
            config.port = find_available_port(
                start_range=config.port_range_start,
                end_range=config.port_range_end,
                max_attempts=config.port_max_attempts
            )
        else:
            config.port = args.port

    # Update environment manager timeout
    env_manager.timeout_seconds = args.timeout

    # Resolve the externally advertised address separately from the machine hostname.
    hostname = socket.gethostname()
    advertise_host = args.advertise_host
    if not advertise_host:
        advertise_host = args.host if args.host not in {"0.0.0.0", "::"} else hostname
    worker_url = f"http://{advertise_host}:{config.port}"

    # Register signal handlers
    signal.signal(signal.SIGTERM, graceful_shutdown)
    signal.signal(signal.SIGINT, graceful_shutdown)
    atexit.register(graceful_shutdown)

    # Start cleanup thread
    env_manager.start_cleanup_thread()

    # Initialize master client if URL provided
    if args.master_url:
        master_client = MasterClient(
            master_url=args.master_url,
            worker_id=config.worker_id,
            worker_url=worker_url,
            hostname=hostname,
            port=config.port,
            max_envs=config.max_envs
        )

        # Register with master
        if not master_client.register():
            logger.error("Failed to register with master after retries")
            # Continue anyway - heartbeat will retry

        # Start heartbeat
        heartbeat_manager = HeartbeatManager(
            master_client=master_client,
            interval=args.heartbeat_interval
        )
        heartbeat_manager.start()

    # Start auto-save if monitoring available
    if session_manager and metrics_collector:
        session_manager.start_auto_save(metrics_collector)

    logger.info("=" * 70)
    logger.info(f"Starting Gym-Anything Worker Server")
    logger.info(f"  Worker ID: {config.worker_id}")
    logger.info(f"  URL: {worker_url}")
    logger.info(f"  Hostname: {hostname}")
    logger.info(f"  Max Envs: {config.max_envs}")
    logger.info(f"  Timeout: {config.timeout_seconds}s")
    if args.master_url:
        logger.info(f"  Master: {args.master_url}")
        logger.info(f"  Registered: {master_client.registered if master_client else False}")
    else:
        logger.info(f"  Master: (standalone mode)")
    logger.info("=" * 70)

    try:
        app.run(host=config.host, port=config.port, debug=args.debug, threaded=True)
    finally:
        graceful_shutdown()


if __name__ == "__main__":
    main()
