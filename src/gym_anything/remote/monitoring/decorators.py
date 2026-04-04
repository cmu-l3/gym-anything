"""
Fail-safe decorators for tracking endpoint and operation metrics.

All decorators are designed to never break the wrapped function, even if
metrics collection fails. Errors are silently caught and logged.
"""

from __future__ import annotations

import time
import logging
from functools import wraps
from typing import Callable, Any

from .metrics import get_metrics_collector

logger = logging.getLogger(__name__)


def track_endpoint(func: Callable) -> Callable:
    """
    Decorator for Flask endpoints to track requests, latency, and errors.
    
    This decorator:
    - Logs request start
    - Tracks request latency
    - Records successes and errors
    - Never breaks the wrapped function (fail-safe)
    
    Usage:
        @app.route('/envs/create', methods=['POST'])
        @track_endpoint
        def create_environment():
            ...
    """
    @wraps(func)
    def wrapper(*args, **kwargs):
        metrics = get_metrics_collector()
        endpoint_name = func.__name__
        start_time = time.time()
        
        # Log request start (fail-safe)
        try:
            metrics.log_request_start(endpoint_name)
        except Exception as e:
            logger.debug(f"Failed to log request start for {endpoint_name}: {e}")
        
        # Execute the original function
        try:
            result = func(*args, **kwargs)
            
            # Log success (fail-safe)
            try:
                latency = time.time() - start_time
                metrics.log_request_success(endpoint_name, latency)
            except Exception as e:
                logger.debug(f"Failed to log request success for {endpoint_name}: {e}")
            
            return result
            
        except Exception as e:
            # Log error (fail-safe)
            try:
                latency = time.time() - start_time
                error_msg = f"{type(e).__name__}: {str(e)}"
                metrics.log_request_error(endpoint_name, error_msg, latency)
            except Exception as log_error:
                logger.debug(f"Failed to log request error for {endpoint_name}: {log_error}")
            
            # Re-raise the original exception
            raise
    
    return wrapper


def track_env_activity(func: Callable) -> Callable:
    """
    Decorator to automatically update environment last activity timestamp.
    
    Extracts env_id from function arguments and updates activity.
    
    Usage:
        @track_env_activity
        def get_environment(self, env_id: str):
            ...
    """
    @wraps(func)
    def wrapper(*args, **kwargs):
        metrics = get_metrics_collector()
        
        # Try to extract env_id from args or kwargs
        env_id = None
        try:
            # Check kwargs first
            if 'env_id' in kwargs:
                env_id = kwargs['env_id']
            # Check positional args (usually second arg after self)
            elif len(args) >= 2:
                env_id = args[1]
            
            if env_id:
                metrics.log_env_activity(env_id)
        except Exception as e:
            logger.debug(f"Failed to track env activity: {e}")
        
        # Execute original function
        return func(*args, **kwargs)
    
    return wrapper


def log_env_event(event_type: str):
    """
    Decorator factory for logging specific environment events.
    
    Args:
        event_type: Type of event ('created', 'closed', 'reset', 'step')
    
    Usage:
        @log_env_event('created')
        def create_environment(self, ...):
            ...
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs):
            # Execute original function first
            result = func(*args, **kwargs)
            
            # Try to log the event (fail-safe)
            try:
                metrics = get_metrics_collector()
                
                # Different event types need different data
                if event_type == 'created' and isinstance(result, str):
                    # result is env_id for create operations
                    # Try to extract additional info from kwargs
                    env_dir = kwargs.get('env_dir')
                    task_id = kwargs.get('task_id')
                    metadata = kwargs.get('metadata')
                    metrics.log_env_created(result, env_dir, task_id, metadata)
                    
                elif event_type == 'closed':
                    # Extract env_id from args/kwargs
                    env_id = kwargs.get('env_id') or (args[1] if len(args) >= 2 else None)
                    reason = kwargs.get('reason', 'manual')
                    if env_id:
                        metrics.log_env_closed(env_id, reason)
                        
                elif event_type == 'reset':
                    # Extract env_id from args/kwargs
                    env_id = kwargs.get('env_id') or (args[1] if len(args) >= 2 else None)
                    if env_id:
                        metrics.log_env_reset(env_id)
                        
                elif event_type == 'step':
                    # Extract env_id from args/kwargs
                    env_id = kwargs.get('env_id') or (args[1] if len(args) >= 2 else None)
                    actions = kwargs.get('actions', [])
                    action_count = len(actions) if isinstance(actions, list) else 1
                    if env_id:
                        metrics.log_env_step(env_id, action_count)
                        
            except Exception as e:
                logger.debug(f"Failed to log {event_type} event: {e}")
            
            return result
        
        return wrapper
    return decorator


class MetricsContext:
    """
    Context manager for manual metrics tracking in complex operations.
    
    Usage:
        with MetricsContext('complex_operation') as ctx:
            # Do work
            ctx.add_detail('items_processed', 100)
    """
    
    def __init__(self, operation_name: str):
        self.operation_name = operation_name
        self.start_time = None
        self.metrics = get_metrics_collector()
        self.details = {}
    
    def __enter__(self):
        self.start_time = time.time()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        try:
            latency = time.time() - self.start_time
            
            if exc_type is None:
                # Success
                self.metrics.log_request_success(self.operation_name, latency)
            else:
                # Error
                error_msg = f"{exc_type.__name__}: {str(exc_val)}"
                self.metrics.log_request_error(self.operation_name, error_msg, latency)
        except Exception:
            pass  # Fail-safe
        
        return False  # Don't suppress exceptions
    
    def add_detail(self, key: str, value: Any):
        """Add detail to the operation (for potential future logging)."""
        self.details[key] = value


def fail_safe(default_return=None):
    """
    Decorator to make any function fail-safe by catching all exceptions.
    
    Args:
        default_return: Value to return if function fails
    
    Usage:
        @fail_safe(default_return={})
        def risky_operation():
            ...
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs):
            try:
                return func(*args, **kwargs)
            except Exception as e:
                logger.warning(f"Fail-safe caught exception in {func.__name__}: {e}")
                return default_return
        return wrapper
    return decorator

