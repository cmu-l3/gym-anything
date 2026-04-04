#!/usr/bin/env python3
"""
Standalone Dashboard Server for Gym-Anything Remote Servers

This server runs independently and aggregates metrics from multiple
remote servers. It also handles long-timeout cleanup (2 hours) to
properly clean Docker resources.

Usage:
    python -m gym_anything.remote.dashboard_app --servers http://server1:5000,http://server2:5000
"""

from __future__ import annotations

import argparse
import json
import logging
import threading
import time
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

import requests
from flask import Flask, render_template_string, jsonify, request as flask_request
from flask_cors import CORS

from .dashboard_template import DASHBOARD_TEMPLATE

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


app = Flask(__name__)
CORS(app)

# Configuration
CLEANUP_CHECK_INTERVAL = 600  # Check every 30 seconds (change to 300 for production)
CLEANUP_IDLE_THRESHOLD = 7200  # 2 hours in seconds
METRICS_POLL_INTERVAL = 10  # Poll remote servers every 10 seconds


class RemoteServerMonitor:
    """Monitors and aggregates metrics from remote servers."""
    
    def __init__(self, server_urls: List[str]):
        self.server_urls = server_urls
        self.servers_data: Dict[str, Dict[str, Any]] = {}
        self.lock = threading.Lock()
        self.poll_thread: Optional[threading.Thread] = None
        self.cleanup_thread: Optional[threading.Thread] = None
        self.stop_event = threading.Event()
        
        # Track recently cleaned environments (to avoid re-cleaning)
        self.recently_cleaned: Dict[str, float] = {}  # env_id -> timestamp
        self.cleaned_lock = threading.Lock()
        
        # Initialize server data
        for url in server_urls:
            self.servers_data[url] = {
                'status': 'unknown',
                'metrics': {},
                'last_update': 0,
                'error': None
            }
    
    def start(self):
        """Start monitoring threads."""
        self.stop_event.clear()
        
        # Start polling thread
        self.poll_thread = threading.Thread(target=self._poll_loop, daemon=True)
        self.poll_thread.start()
        logger.info("Started metrics polling thread")
        
        # Start cleanup thread
        self.cleanup_thread = threading.Thread(target=self._cleanup_loop, daemon=True)
        self.cleanup_thread.start()
        logger.info(f"Started cleanup thread (threshold={CLEANUP_IDLE_THRESHOLD}s / {CLEANUP_IDLE_THRESHOLD/3600:.1f}h)")
    
    def stop(self):
        """Stop monitoring threads."""
        self.stop_event.set()
        if self.poll_thread:
            self.poll_thread.join(timeout=5)
        if self.cleanup_thread:
            self.cleanup_thread.join(timeout=5)
        logger.info("Stopped monitoring threads")
    
    def _poll_loop(self):
        """Background loop to poll metrics from remote servers."""
        while not self.stop_event.is_set():
            try:
                for server_url in self.server_urls:
                    self._poll_server(server_url)
            except Exception as e:
                logger.error(f"Error in poll loop: {e}", exc_info=True)
            
            # Sleep with periodic checks
            for _ in range(METRICS_POLL_INTERVAL):
                if self.stop_event.is_set():
                    break
                time.sleep(1)
    
    def _poll_server(self, server_url: str):
        """Poll metrics from a single remote server."""
        try:
            response = requests.get(
                f"{server_url}/api/metrics",
                timeout=5
            )
            response.raise_for_status()
            metrics = response.json()
            
            with self.lock:
                self.servers_data[server_url] = {
                    'status': 'healthy',
                    'metrics': metrics,
                    'last_update': time.time(),
                    'error': None
                }
            
        except requests.exceptions.RequestException as e:
            logger.warning(f"Failed to poll {server_url}: {e}")
            with self.lock:
                self.servers_data[server_url]['status'] = 'error'
                self.servers_data[server_url]['error'] = str(e)
    
    def _cleanup_loop(self):
        """Background loop to cleanup idle environments."""
        while not self.stop_event.is_set():
            try:
                self._cleanup_idle_environments()
            except Exception as e:
                logger.error(f"Error in cleanup loop: {e}", exc_info=True)
            
            # Sleep with periodic checks
            for _ in range(CLEANUP_CHECK_INTERVAL):
                if self.stop_event.is_set():
                    break
                time.sleep(1)
    
    def _cleanup_idle_environments(self):
        """Check all servers and cleanup idle environments."""
        current_time = time.time()
        
        # Clean up old entries from recently_cleaned (> 5 minutes old)
        with self.cleaned_lock:
            self.recently_cleaned = {
                env_id: ts for env_id, ts in self.recently_cleaned.items()
                if current_time - ts < 300
            }
        
        with self.lock:
            servers_data_copy = dict(self.servers_data)
        
        logger.info(f"Running cleanup check (threshold: {CLEANUP_IDLE_THRESHOLD}s / {CLEANUP_IDLE_THRESHOLD/3600:.1f}h)")
        
        cleaned_count = 0
        skipped_count = 0
        
        for server_url, data in servers_data_copy.items():
            if data['status'] != 'healthy':
                logger.debug(f"Skipping unhealthy server: {server_url}")
                continue
            
            metrics = data.get('metrics', {})
            active_envs = metrics.get('environments', {}).get('active', [])
            
            logger.info(f"Checking {len(active_envs)} active environments on {server_url}")
            
            for env in active_envs:
                env_id = env.get('env_id')
                idle_time = env.get('idle_time', 0)
                
                # Skip if recently cleaned
                with self.cleaned_lock:
                    if env_id in self.recently_cleaned:
                        skipped_count += 1
                        logger.debug(f"Skipping {env_id[:8]} (recently cleaned)")
                        continue
                
                if idle_time > CLEANUP_IDLE_THRESHOLD:
                    logger.warning(
                        f"🚨 Environment {env_id[:8]} on {server_url} idle for "
                        f"{idle_time:.1f}s ({idle_time/3600:.1f}h) > threshold {CLEANUP_IDLE_THRESHOLD}s ({CLEANUP_IDLE_THRESHOLD/3600:.1f}h)"
                    )
                    self._cleanup_environment(server_url, env_id, idle_time)
                    cleaned_count += 1
                    
                    # Mark as recently cleaned
                    with self.cleaned_lock:
                        self.recently_cleaned[env_id] = current_time
        
        if cleaned_count > 0 or skipped_count > 0:
            logger.info(f"Cleanup summary: {cleaned_count} cleaned, {skipped_count} skipped (recently cleaned)")
    
    def _cleanup_environment(self, server_url: str, env_id: str, idle_time: float):
        """Cleanup a specific environment with Docker resource removal."""
        logger.info(f"=" * 60)
        logger.info(f"Starting cleanup for {env_id}")
        logger.info(f"Server: {server_url}")
        logger.info(f"Idle time: {idle_time:.1f}s ({idle_time/3600:.2f}h)")
        logger.info(f"=" * 60)
        
        try:
            # First, try to close gracefully
            logger.info(f"Step 1: Sending close request to {server_url}/envs/{env_id}/close")
            response = requests.post(
                f"{server_url}/envs/{env_id}/close",
                timeout=30
            )
            
            if response.status_code == 200:
                logger.info(f"✅ Successfully closed environment {env_id}")
            else:
                logger.warning(
                    f"⚠️  Close failed for {env_id}: "
                    f"HTTP {response.status_code} - {response.text[:200]}"
                )
            
            # Try to force cleanup Docker resources
            logger.info(f"Step 2: Sending force cleanup request")
            try:
                cleanup_response = requests.post(
                    f"{server_url}/envs/{env_id}/force_cleanup",
                    timeout=30
                )
                if cleanup_response.status_code == 200:
                    result = cleanup_response.json()
                    logger.info(f"✅ Force cleanup successful for {env_id}")
                    logger.info(f"   Details: {result.get('details', {})}")
                else:
                    logger.warning(
                        f"⚠️  Force cleanup HTTP error: "
                        f"{cleanup_response.status_code} - {cleanup_response.text[:200]}"
                    )
            except requests.exceptions.RequestException as e:
                logger.error(f"❌ Force cleanup request failed: {e}")
            except Exception as e:
                logger.error(f"❌ Force cleanup error: {e}")
                
        except requests.exceptions.RequestException as e:
            logger.error(f"❌ Close request failed: {e}")
        except Exception as e:
            logger.error(f"❌ Cleanup error: {e}", exc_info=True)
        
        logger.info(f"Finished cleanup attempt for {env_id}")
        logger.info(f"=" * 60)
    
    def get_aggregated_metrics(self) -> Dict[str, Any]:
        """Get aggregated metrics from all servers."""
        with self.lock:
            servers_data_copy = dict(self.servers_data)
        
        # Aggregate metrics
        total_active_envs = 0
        total_created_envs = 0
        total_requests = 0
        total_errors = 0
        all_active_envs = []
        all_endpoints = defaultdict(lambda: {
            'request_count': 0,
            'error_count': 0,
            'total_latency': 0.0,
            'latencies': []
        })
        all_activity = []
        
        for server_url, data in servers_data_copy.items():
            if data['status'] != 'healthy':
                continue
            
            metrics = data.get('metrics', {})
            
            # Environment metrics
            env_metrics = metrics.get('environments', {})
            total_active_envs += env_metrics.get('active_count', 0)
            total_created_envs += env_metrics.get('total_created', 0)
            
            # Add server URL to each active env
            for env in env_metrics.get('active', []):
                env['server_url'] = server_url
                env['server_short'] = server_url.split('://')[-1].split(':')[0]
                all_active_envs.append(env)
            
            # Endpoint metrics
            endpoint_metrics = metrics.get('endpoints', {})
            total_requests += endpoint_metrics.get('total_requests', 0)
            total_errors += endpoint_metrics.get('total_errors', 0)
            
            for ep_stat in endpoint_metrics.get('stats', []):
                ep_name = ep_stat['name']
                all_endpoints[ep_name]['request_count'] += ep_stat.get('request_count', 0)
                all_endpoints[ep_name]['error_count'] += ep_stat.get('error_count', 0)
                all_endpoints[ep_name]['total_latency'] += (
                    ep_stat.get('avg_latency', 0) * ep_stat.get('request_count', 1)
                )
                all_endpoints[ep_name]['latencies'].extend(
                    [ep_stat.get('avg_latency', 0)] * min(ep_stat.get('request_count', 0), 10)
                )
            
            # Activity log
            for activity in metrics.get('activity_log', [])[:20]:  # Top 20 per server
                activity['server_url'] = server_url
                activity['server_short'] = server_url.split('://')[-1].split(':')[0]
                all_activity.append(activity)
        
        # Process endpoint stats
        endpoint_stats = []
        for name, data in all_endpoints.items():
            req_count = data['request_count']
            avg_latency = data['total_latency'] / req_count if req_count > 0 else 0
            latencies = sorted(data['latencies']) if data['latencies'] else [0]
            
            endpoint_stats.append({
                'name': name,
                'request_count': req_count,
                'success_count': req_count - data['error_count'],
                'error_count': data['error_count'],
                'avg_latency': avg_latency,
                'min_latency': min(latencies),
                'max_latency': max(latencies),
                'p50_latency': latencies[len(latencies) // 2] if latencies else 0,
                'p95_latency': latencies[int(len(latencies) * 0.95)] if latencies else 0,
                'p99_latency': latencies[int(len(latencies) * 0.99)] if latencies else 0,
                'error_rate': data['error_count'] / req_count if req_count > 0 else 0,
                'recent_errors': []
            })
        endpoint_stats.sort(key=lambda x: x['request_count'], reverse=True)
        
        # Sort activity by timestamp
        all_activity.sort(key=lambda x: x.get('timestamp', 0), reverse=True)
        
        # Calculate uptime (from first server that's healthy)
        uptime = 0
        uptime_formatted = "0s"
        session_id = "aggregated"
        for data in servers_data_copy.values():
            if data['status'] == 'healthy':
                server_metrics = data.get('metrics', {}).get('server', {})
                if 'uptime' in server_metrics:
                    uptime = max(uptime, server_metrics.get('uptime', 0))
                    uptime_formatted = server_metrics.get('uptime_formatted', '0s')
                if 'session_id' in server_metrics and session_id == "aggregated":
                    session_id = f"multi-{server_metrics.get('session_id', 'unknown')[:8]}"
        
        # Calculate responsive count
        responsive_count = sum(1 for env in all_active_envs if env.get('is_responsive', True))
        
        # Calculate closed count
        total_closed = 0
        for data in servers_data_copy.values():
            if data['status'] == 'healthy':
                total_closed += data.get('metrics', {}).get('environments', {}).get('total_closed', 0)
        
        # Peak concurrent (max from any server)
        peak_concurrent = max(
            (data.get('metrics', {}).get('environments', {}).get('peak_concurrent', 0)
             for data in servers_data_copy.values() if data['status'] == 'healthy'),
            default=total_active_envs
        )
        
        # Aggregated timeline (use from first healthy server for now)
        timeline_data = []
        for data in servers_data_copy.values():
            if data['status'] == 'healthy' and data.get('metrics', {}).get('timeline'):
                timeline_data = data['metrics']['timeline']
                break
        
        return {
            'server': {
                'session_id': session_id,
                'start_time': time.time() - uptime,
                'uptime': uptime,
                'uptime_formatted': uptime_formatted
            },
            'servers': {
                'total': len(self.server_urls),
                'healthy': sum(1 for d in servers_data_copy.values() if d['status'] == 'healthy'),
                'details': [
                    {
                        'url': url,
                        'status': data['status'],
                        'last_update': data['last_update'],
                        'error': data.get('error'),
                        'active_envs': data.get('metrics', {}).get('environments', {}).get('active_count', 0)
                    }
                    for url, data in servers_data_copy.items()
                ]
            },
            'environments': {
                'active_count': total_active_envs,
                'responsive_count': responsive_count,
                'total_created': total_created_envs,
                'total_closed': total_closed,
                'peak_concurrent': peak_concurrent,
                'active': all_active_envs,
                'closure_stats': {
                    'total': total_closed,
                    'by_reason': {}
                }
            },
            'endpoints': {
                'total_requests': total_requests,
                'total_errors': total_errors,
                'error_rate': total_errors / total_requests if total_requests > 0 else 0,
                'stats': endpoint_stats
            },
            'activity_log': all_activity[:50],  # Top 50 overall
            'timeline': timeline_data,
            'cleanup': {
                'threshold_seconds': CLEANUP_IDLE_THRESHOLD,
                'threshold_formatted': f"{CLEANUP_IDLE_THRESHOLD / 3600:.1f}h",
                'check_interval': CLEANUP_CHECK_INTERVAL,
                'timeout_cleanups': 0,
                'by_reason': {}
            }
        }
    
    def add_server(self, server_url: str):
        """Add a new server to monitor."""
        if server_url not in self.server_urls:
            self.server_urls.append(server_url)
            with self.lock:
                self.servers_data[server_url] = {
                    'status': 'unknown',
                    'metrics': {},
                    'last_update': 0,
                    'error': None
                }
            logger.info(f"Added server: {server_url}")
    
    def remove_server(self, server_url: str):
        """Remove a server from monitoring."""
        if server_url in self.server_urls:
            self.server_urls.remove(server_url)
            with self.lock:
                self.servers_data.pop(server_url, None)
            logger.info(f"Removed server: {server_url}")


# Global monitor instance
monitor: Optional[RemoteServerMonitor] = None


# ============================================================================
# Dashboard Endpoints
# ============================================================================

@app.route('/')
@app.route('/dashboard')
def dashboard():
    """Serve the dashboard UI."""
    try:
        return render_template_string(DASHBOARD_TEMPLATE)
    except Exception as e:
        logger.error(f"Error loading dashboard template: {e}", exc_info=True)
        return jsonify({"error": "Dashboard template not found"}), 500


@app.route('/api/metrics', methods=['GET'])
def get_metrics():
    """Get aggregated metrics from all servers."""
    try:
        if monitor is None:
            return jsonify({"error": "Monitor not initialized"}), 500
        
        metrics = monitor.get_aggregated_metrics()
        return jsonify(metrics)
    except Exception as e:
        logger.error(f"Error getting metrics: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


@app.route('/api/servers', methods=['GET'])
def list_servers():
    """List all monitored servers."""
    try:
        if monitor is None:
            return jsonify({"error": "Monitor not initialized"}), 500
        
        with monitor.lock:
            servers = [
                {
                    'url': url,
                    'status': data['status'],
                    'last_update': data['last_update'],
                    'error': data.get('error')
                }
                for url, data in monitor.servers_data.items()
            ]
        
        return jsonify({"servers": servers})
    except Exception as e:
        logger.error(f"Error listing servers: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


@app.route('/api/servers/add', methods=['POST'])
def add_server():
    """Add a new server to monitor."""
    try:
        if monitor is None:
            return jsonify({"error": "Monitor not initialized"}), 500
        
        data = flask_request.get_json() or {}
        server_url = data.get('server_url')
        
        if not server_url:
            return jsonify({"error": "Missing server_url"}), 400
        
        monitor.add_server(server_url)
        return jsonify({"status": "added", "server_url": server_url})
    except Exception as e:
        logger.error(f"Error adding server: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


@app.route('/api/servers/remove', methods=['POST'])
def remove_server():
    """Remove a server from monitoring."""
    try:
        if monitor is None:
            return jsonify({"error": "Monitor not initialized"}), 500
        
        data = flask_request.get_json() or {}
        server_url = data.get('server_url')
        
        if not server_url:
            return jsonify({"error": "Missing server_url"}), 400
        
        monitor.remove_server(server_url)
        return jsonify({"status": "removed", "server_url": server_url})
    except Exception as e:
        logger.error(f"Error removing server: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint."""
    if monitor is None:
        return jsonify({"status": "error", "message": "Monitor not initialized"}), 500
    
    metrics = monitor.get_aggregated_metrics()
    return jsonify({
        "status": "healthy",
        "servers_monitored": len(monitor.server_urls),
        "servers_healthy": metrics['servers']['healthy'],
        "total_active_envs": metrics['environments']['active_count']
    })


def main():
    """Main entry point for the dashboard server."""
    global CLEANUP_IDLE_THRESHOLD
    
    parser = argparse.ArgumentParser(description="Gym-Anything Dashboard Server")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
    parser.add_argument("--port", type=int, default=5001, help="Port to bind to (default: 5001)")
    parser.add_argument("--servers", type=str, required=True,
                       help="Comma-separated list of remote server URLs (e.g., http://server1:5000,http://server2:5000)")
    parser.add_argument("--cleanup-threshold", type=int, default=CLEANUP_IDLE_THRESHOLD,
                       help="Cleanup idle threshold in seconds (default: 7200 = 2 hours)")
    parser.add_argument("--debug", action="store_true", help="Enable debug mode")
    
    args = parser.parse_args()
    
    # Parse server URLs
    server_urls = [url.strip() for url in args.servers.split(',') if url.strip()]
    if not server_urls:
        logger.error("No server URLs provided")
        return
    
    # Update cleanup threshold
    CLEANUP_IDLE_THRESHOLD = args.cleanup_threshold
    
    # Initialize monitor
    global monitor
    monitor = RemoteServerMonitor(server_urls)
    monitor.start()
    
    logger.info("=" * 70)
    logger.info(f"Starting Gym-Anything Dashboard Server on {args.host}:{args.port}")
    logger.info(f"Monitoring {len(server_urls)} server(s):")
    for url in server_urls:
        logger.info(f"  - {url}")
    logger.info(f"Cleanup threshold: {args.cleanup_threshold}s ({args.cleanup_threshold/3600:.1f} hours)")
    logger.info(f"Dashboard available at: http://{args.host}:{args.port}/dashboard")
    logger.info("=" * 70)
    
    try:
        app.run(host=args.host, port=args.port, debug=args.debug, threaded=True)
    finally:
        # Cleanup on shutdown
        logger.info("Shutting down dashboard server...")
        if monitor:
            monitor.stop()
        logger.info("Dashboard server shutdown complete")


if __name__ == "__main__":
    main()
