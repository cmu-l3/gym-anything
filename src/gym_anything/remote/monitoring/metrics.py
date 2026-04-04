"""
Core metrics collection for Gym-Anything Remote Server monitoring.

This module provides thread-safe metrics collection with support for:
- Environment lifecycle tracking
- Endpoint request statistics
- Performance metrics
- Historical timeline data
"""

from __future__ import annotations

import threading
import time
from collections import defaultdict, deque
from dataclasses import dataclass, field, asdict
from datetime import datetime
from typing import Any, Dict, List, Optional, Deque
import numpy as np


@dataclass
class EnvironmentMetrics:
    """Metrics for a single environment instance."""
    env_id: str
    env_dir: Optional[str] = None
    task_id: Optional[str] = None
    created_at: float = field(default_factory=time.time)
    last_activity: float = field(default_factory=time.time)
    reset_count: int = 0
    step_count: int = 0
    action_count: int = 0
    status: str = "active"  # active, closed, timeout
    close_reason: Optional[str] = None
    closed_at: Optional[float] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary with computed fields."""
        data = asdict(self)
        data['idle_time'] = time.time() - self.last_activity
        data['lifetime'] = (self.closed_at or time.time()) - self.created_at
        data['is_responsive'] = data['idle_time'] < 600  # 10 minutes
        return data


@dataclass
class EndpointMetrics:
    """Metrics for a single API endpoint."""
    name: str
    request_count: int = 0
    success_count: int = 0
    error_count: int = 0
    total_latency: float = 0.0
    latencies: Deque[float] = field(default_factory=lambda: deque(maxlen=1000))
    errors: List[Dict[str, Any]] = field(default_factory=list)
    last_accessed: Optional[float] = None
    
    def add_success(self, latency: float):
        """Record a successful request."""
        self.request_count += 1
        self.success_count += 1
        self.total_latency += latency
        self.latencies.append(latency)
        self.last_accessed = time.time()
    
    def add_error(self, error_msg: str, latency: float):
        """Record a failed request."""
        self.request_count += 1
        self.error_count += 1
        self.total_latency += latency
        self.latencies.append(latency)
        self.last_accessed = time.time()
        
        # Keep last 100 errors
        self.errors.append({
            'timestamp': time.time(),
            'error': error_msg[:200]  # Truncate long errors
        })
        if len(self.errors) > 100:
            self.errors = self.errors[-100:]
    
    def get_stats(self) -> Dict[str, Any]:
        """Compute statistical summary."""
        latencies_list = list(self.latencies)
        
        if not latencies_list:
            return {
                'name': self.name,
                'request_count': self.request_count,
                'success_count': self.success_count,
                'error_count': self.error_count,
                'error_rate': 0.0,
                'avg_latency': 0.0,
                'min_latency': 0.0,
                'max_latency': 0.0,
                'p50_latency': 0.0,
                'p95_latency': 0.0,
                'p99_latency': 0.0,
                'last_accessed': self.last_accessed,
                'recent_errors': self.errors[-5:] if self.errors else []
            }
        
        latencies_sorted = sorted(latencies_list)
        
        return {
            'name': self.name,
            'request_count': self.request_count,
            'success_count': self.success_count,
            'error_count': self.error_count,
            'error_rate': self.error_count / self.request_count if self.request_count > 0 else 0.0,
            'avg_latency': self.total_latency / self.request_count if self.request_count > 0 else 0.0,
            'min_latency': min(latencies_list),
            'max_latency': max(latencies_list),
            'p50_latency': latencies_sorted[len(latencies_sorted) // 2],
            'p95_latency': latencies_sorted[int(len(latencies_sorted) * 0.95)],
            'p99_latency': latencies_sorted[int(len(latencies_sorted) * 0.99)],
            'last_accessed': self.last_accessed,
            'recent_errors': self.errors[-5:] if self.errors else []
        }


@dataclass
class TimelinePoint:
    """A point in the timeline for graphing."""
    timestamp: float
    active_envs: int
    requests_per_minute: float = 0.0
    cumulative_envs: int = 0


class MetricsCollector:
    """Thread-safe metrics collector for remote server monitoring."""
    
    def __init__(self):
        self.lock = threading.Lock()
        
        # Server metadata
        self.start_time = time.time()
        self.session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # Environment tracking
        self.environments: Dict[str, EnvironmentMetrics] = {}
        self.total_envs_created = 0
        self.closed_envs: List[EnvironmentMetrics] = []
        
        # Endpoint tracking
        self.endpoints: Dict[str, EndpointMetrics] = defaultdict(
            lambda: EndpointMetrics(name="unknown")
        )
        
        # Activity log (last 1000 events)
        self.activity_log: Deque[Dict[str, Any]] = deque(maxlen=1000)
        
        # Timeline data (one point per minute, keep last 24 hours)
        self.timeline: Deque[TimelinePoint] = deque(maxlen=24 * 60)
        self._last_timeline_update = time.time()
        
        # Request rate tracking (for timeline)
        self._request_timestamps: Deque[float] = deque(maxlen=10000)
        
        # Cleanup tracking
        self.cleanup_count = 0
        self.cleanup_by_reason = defaultdict(int)
    
    def log_env_created(self, env_id: str, env_dir: Optional[str] = None, 
                        task_id: Optional[str] = None, metadata: Optional[Dict] = None):
        """Log environment creation."""
        try:
            with self.lock:
                env_metrics = EnvironmentMetrics(
                    env_id=env_id,
                    env_dir=env_dir,
                    task_id=task_id
                )
                self.environments[env_id] = env_metrics
                self.total_envs_created += 1
                
                self._add_activity_log("env_created", {
                    'env_id': env_id,
                    'env_dir': env_dir,
                    'task_id': task_id
                })
                
                self._update_timeline()
        except Exception:
            pass  # Fail-safe
    
    def log_env_closed(self, env_id: str, reason: str = "manual"):
        """Log environment closure."""
        try:
            with self.lock:
                if env_id in self.environments:
                    env = self.environments[env_id]
                    env.status = "closed"
                    env.close_reason = reason
                    env.closed_at = time.time()
                    
                    self.closed_envs.append(env)
                    del self.environments[env_id]
                    
                    self.cleanup_by_reason[reason] += 1
                    if reason == "timeout":
                        self.cleanup_count += 1
                    
                    self._add_activity_log("env_closed", {
                        'env_id': env_id,
                        'reason': reason,
                        'lifetime': env.closed_at - env.created_at,
                        'steps': env.step_count
                    })
                    
                    self._update_timeline()
        except Exception:
            pass  # Fail-safe
    
    def log_env_activity(self, env_id: str):
        """Update last activity timestamp for environment."""
        try:
            with self.lock:
                if env_id in self.environments:
                    self.environments[env_id].last_activity = time.time()
        except Exception:
            pass  # Fail-safe
    
    def log_env_reset(self, env_id: str):
        """Log environment reset."""
        try:
            with self.lock:
                if env_id in self.environments:
                    self.environments[env_id].reset_count += 1
                    self._add_activity_log("env_reset", {'env_id': env_id})
        except Exception:
            pass  # Fail-safe
    
    def log_env_step(self, env_id: str, action_count: int = 1):
        """Log environment step."""
        try:
            with self.lock:
                if env_id in self.environments:
                    env = self.environments[env_id]
                    env.step_count += 1
                    env.action_count += action_count
                    env.last_activity = time.time()
        except Exception:
            pass  # Fail-safe
    
    def log_request_start(self, endpoint: str):
        """Log request start (for rate tracking)."""
        try:
            with self.lock:
                self._request_timestamps.append(time.time())
        except Exception:
            pass  # Fail-safe
    
    def log_request_success(self, endpoint: str, latency: float):
        """Log successful request."""
        try:
            with self.lock:
                if endpoint not in self.endpoints:
                    self.endpoints[endpoint] = EndpointMetrics(name=endpoint)
                self.endpoints[endpoint].add_success(latency)
                self._update_timeline()
        except Exception:
            pass  # Fail-safe
    
    def log_request_error(self, endpoint: str, error_msg: str, latency: float = 0.0):
        """Log failed request."""
        try:
            with self.lock:
                if endpoint not in self.endpoints:
                    self.endpoints[endpoint] = EndpointMetrics(name=endpoint)
                self.endpoints[endpoint].add_error(error_msg, latency)
                
                self._add_activity_log("request_error", {
                    'endpoint': endpoint,
                    'error': error_msg[:200]
                })
                
                self._update_timeline()
        except Exception:
            pass  # Fail-safe
    
    def _add_activity_log(self, event_type: str, details: Dict[str, Any]):
        """Add entry to activity log."""
        self.activity_log.append({
            'timestamp': time.time(),
            'event_type': event_type,
            'details': details
        })
    
    def _update_timeline(self):
        """Update timeline data (called periodically)."""
        now = time.time()
        
        # Update every minute
        if now - self._last_timeline_update < 60:
            return
        
        self._last_timeline_update = now
        
        # Calculate requests per minute
        recent_requests = [ts for ts in self._request_timestamps if now - ts < 60]
        rpm = len(recent_requests)
        
        point = TimelinePoint(
            timestamp=now,
            active_envs=len(self.environments),
            requests_per_minute=rpm,
            cumulative_envs=self.total_envs_created
        )
        
        self.timeline.append(point)
    
    def get_stats(self) -> Dict[str, Any]:
        """Get complete statistics snapshot."""
        try:
            with self.lock:
                # Force timeline update
                self._update_timeline()
                
                # Active environment stats
                active_envs = [env.to_dict() for env in self.environments.values()]
                responsive_count = sum(1 for env in active_envs if env['is_responsive'])
                
                # Endpoint stats
                endpoint_stats = [ep.get_stats() for ep in self.endpoints.values()]
                endpoint_stats.sort(key=lambda x: x['request_count'], reverse=True)
                
                # Timeline data
                timeline_data = [
                    {
                        'timestamp': int(p.timestamp * 1000),  # JS milliseconds
                        'active_envs': p.active_envs,
                        'requests_per_minute': p.requests_per_minute,
                        'cumulative_envs': p.cumulative_envs
                    }
                    for p in self.timeline
                ]
                
                # Activity log
                activity_log = [
                    {
                        'timestamp': log['timestamp'],
                        'event_type': log['event_type'],
                        'details': log['details']
                    }
                    for log in list(self.activity_log)[-50:]  # Last 50
                ]
                activity_log.reverse()  # Most recent first
                
                # Closure statistics
                total_closed = len(self.closed_envs)
                closure_stats = {
                    'total': total_closed,
                    'by_reason': dict(self.cleanup_by_reason)
                }
                
                # Server stats
                uptime = time.time() - self.start_time
                total_requests = sum(ep.request_count for ep in self.endpoints.values())
                total_errors = sum(ep.error_count for ep in self.endpoints.values())
                
                # Peak usage
                peak_active_envs = max((p.active_envs for p in self.timeline), default=len(self.environments))
                
                return {
                    'server': {
                        'session_id': self.session_id,
                        'start_time': self.start_time,
                        'uptime': uptime,
                        'uptime_formatted': self._format_duration(uptime)
                    },
                    'environments': {
                        'active_count': len(self.environments),
                        'responsive_count': responsive_count,
                        'total_created': self.total_envs_created,
                        'total_closed': total_closed,
                        'closure_stats': closure_stats,
                        'peak_concurrent': peak_active_envs,
                        'active': active_envs
                    },
                    'endpoints': {
                        'total_requests': total_requests,
                        'total_errors': total_errors,
                        'error_rate': total_errors / total_requests if total_requests > 0 else 0.0,
                        'stats': endpoint_stats
                    },
                    'activity_log': activity_log,
                    'timeline': timeline_data,
                    'cleanup': {
                        'timeout_cleanups': self.cleanup_count,
                        'by_reason': dict(self.cleanup_by_reason)
                    }
                }
        except Exception as e:
            # Return minimal stats if error
            return {
                'error': str(e),
                'server': {'uptime': time.time() - self.start_time},
                'environments': {'active_count': 0, 'total_created': 0}
            }
    
    def _format_duration(self, seconds: float) -> str:
        """Format duration in human-readable format."""
        days = int(seconds // 86400)
        hours = int((seconds % 86400) // 3600)
        minutes = int((seconds % 3600) // 60)
        secs = int(seconds % 60)
        
        parts = []
        if days > 0:
            parts.append(f"{days}d")
        if hours > 0:
            parts.append(f"{hours}h")
        if minutes > 0:
            parts.append(f"{minutes}m")
        if secs > 0 or not parts:
            parts.append(f"{secs}s")
        
        return " ".join(parts)
    
    def to_dict(self) -> Dict[str, Any]:
        """Export all data for serialization."""
        with self.lock:
            return {
                'session_id': self.session_id,
                'start_time': self.start_time,
                'total_envs_created': self.total_envs_created,
                'cleanup_count': self.cleanup_count,
                'cleanup_by_reason': dict(self.cleanup_by_reason),
                'active_environments': {
                    env_id: env.to_dict() 
                    for env_id, env in self.environments.items()
                },
                'closed_environments': [env.to_dict() for env in self.closed_envs[-100:]],  # Last 100
                'endpoints': {
                    name: ep.get_stats() 
                    for name, ep in self.endpoints.items()
                },
                'activity_log': list(self.activity_log),
                'timeline': [
                    {'timestamp': p.timestamp, 'active_envs': p.active_envs, 
                     'requests_per_minute': p.requests_per_minute, 'cumulative_envs': p.cumulative_envs}
                    for p in self.timeline
                ]
            }
    
    def from_dict(self, data: Dict[str, Any]):
        """Import data from serialized format."""
        try:
            with self.lock:
                self.session_id = data.get('session_id', self.session_id)
                self.start_time = data.get('start_time', self.start_time)
                self.total_envs_created = data.get('total_envs_created', 0)
                self.cleanup_count = data.get('cleanup_count', 0)
                self.cleanup_by_reason = defaultdict(int, data.get('cleanup_by_reason', {}))
                
                # Restore active environments
                for env_id, env_data in data.get('active_environments', {}).items():
                    env = EnvironmentMetrics(
                        env_id=env_data['env_id'],
                        env_dir=env_data.get('env_dir'),
                        task_id=env_data.get('task_id'),
                        created_at=env_data['created_at'],
                        last_activity=env_data['last_activity'],
                        reset_count=env_data.get('reset_count', 0),
                        step_count=env_data.get('step_count', 0),
                        action_count=env_data.get('action_count', 0)
                    )
                    self.environments[env_id] = env
                
                # Restore timeline
                for point_data in data.get('timeline', []):
                    point = TimelinePoint(
                        timestamp=point_data['timestamp'],
                        active_envs=point_data['active_envs'],
                        requests_per_minute=point_data.get('requests_per_minute', 0.0),
                        cumulative_envs=point_data.get('cumulative_envs', 0)
                    )
                    self.timeline.append(point)
                
                # Restore activity log
                for log_entry in data.get('activity_log', []):
                    self.activity_log.append(log_entry)
                
        except Exception:
            pass  # Fail-safe


# Global instance
_metrics_collector: Optional[MetricsCollector] = None


def get_metrics_collector() -> MetricsCollector:
    """Get or create global metrics collector instance."""
    global _metrics_collector
    if _metrics_collector is None:
        _metrics_collector = MetricsCollector()
    return _metrics_collector

