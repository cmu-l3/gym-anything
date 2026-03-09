#!/usr/bin/env python3
"""
Verifier for Instrument API Logging task

This verifier checks if comprehensive logging was added to a Flask API application.
It verifies logging configuration, request ID middleware, endpoint instrumentation,
timing decorators, and security (no sensitive data logging).
"""

import sys
import os
import logging
import tempfile
import shutil
import ast
import re
from typing import Dict, List, Tuple, Any

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_logging_instrumentation(traj, env_info, task_info):
    """
    Verify that logging was properly instrumented in the Flask API.
    
    Scoring:
    1. Logging Configuration (25 points): Proper logging setup
    2. Request ID Middleware (20 points): UUID generation in before_request
    3. Endpoint Instrumentation (25 points): Logging in at least 2 endpoints
    4. Timing Mechanism (15 points): Decorator or timing code
    5. Security (10 points): No sensitive data logged
    6. Code Validity (5 points): Syntactically correct
    
    Pass threshold: 60%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='logging_verify_')
    
    try:
        # Copy exported files
        app_py_local = os.path.join(temp_dir, "app.py")
        logging_config_local = os.path.join(temp_dir, "logging_config.py")
        middleware_local = os.path.join(temp_dir, "middleware.py")
        
        try:
            copy_from_env("/tmp/app.py", app_py_local)
            copy_from_env("/tmp/logging_config.py", logging_config_local)
            copy_from_env("/tmp/middleware.py", middleware_local)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy files: {str(e)}"}
        
        if not os.path.exists(app_py_local) or os.path.getsize(app_py_local) == 0:
            return {"passed": False, "score": 0, "feedback": "app.py not found or empty"}
        
        # Read all file contents
        with open(app_py_local, 'r', encoding='utf-8', errors='ignore') as f:
            app_content = f.read()
        
        logging_config_content = ""
        if os.path.exists(logging_config_local) and os.path.getsize(logging_config_local) > 0:
            with open(logging_config_local, 'r', encoding='utf-8', errors='ignore') as f:
                logging_config_content = f.read()
        
        middleware_content = ""
        if os.path.exists(middleware_local) and os.path.getsize(middleware_local) > 0:
            with open(middleware_local, 'r', encoding='utf-8', errors='ignore') as f:
                middleware_content = f.read()
        
        # Combine all content for analysis
        all_content = app_content + "\n" + logging_config_content + "\n" + middleware_content
        
        # Initialize scoring
        score = 0
        max_score = 100
        feedback_parts = []
        
        # Criterion 1: Logging Configuration (25 points)
        logging_config_score = check_logging_configuration(all_content, feedback_parts)
        score += logging_config_score
        
        # Criterion 2: Request ID Middleware (20 points)
        middleware_score = check_request_id_middleware(all_content, feedback_parts)
        score += middleware_score
        
        # Criterion 3: Endpoint Instrumentation (25 points)
        instrumentation_score = check_endpoint_instrumentation(app_content, feedback_parts)
        score += instrumentation_score
        
        # Criterion 4: Timing Mechanism (15 points)
        timing_score = check_timing_mechanism(all_content, feedback_parts)
        score += timing_score
        
        # Criterion 5: Security (10 points)
        security_score = check_security(all_content, feedback_parts)
        score += security_score
        
        # Criterion 6: Code Validity (5 points)
        validity_score = check_code_validity(app_py_local, logging_config_local, middleware_local, feedback_parts)
        score += validity_score
        
        passed = score >= 60
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)


def check_logging_configuration(content: str, feedback: List[str]) -> int:
    """Check for proper logging configuration (25 points max)"""
    score = 0
    
    # Check for logging import
    has_logging_import = 'import logging' in content
    
    # Check for logging configuration patterns
    has_basicConfig = 'logging.basicConfig' in content
    has_getLogger = 'logging.getLogger' in content or 'getLogger(' in content
    has_formatter = 'Formatter' in content or 'formatter' in content.lower()
    has_handler = 'Handler' in content or 'handler' in content.lower()
    
    if has_logging_import:
        score += 5
        
    if has_basicConfig or (has_getLogger and has_handler):
        score += 10
        feedback.append("✅ Logging configuration detected")
    else:
        feedback.append("❌ No logging configuration found (basicConfig or logger setup)")
        return score
    
    if has_formatter:
        score += 5
        feedback.append("✅ Logging formatter configured")
    
    # Check for appropriate log levels
    has_log_level = any(level in content for level in ['INFO', 'DEBUG', 'WARNING', 'ERROR', 'logging.INFO', 'logging.DEBUG'])
    if has_log_level:
        score += 5
        feedback.append("✅ Log level configuration found")
    
    return min(score, 25)


def check_request_id_middleware(content: str, feedback: List[str]) -> int:
    """Check for request ID middleware implementation (20 points max)"""
    score = 0
    
    # Check for before_request decorator
    has_before_request = '@app.before_request' in content or '@before_request' in content
    
    # Check for UUID generation
    has_uuid_import = 'import uuid' in content or 'from uuid import' in content
    has_uuid_generation = 'uuid.uuid4()' in content or 'uuid4()' in content or 'str(uuid.uuid4())' in content
    
    # Check for Flask g object usage
    has_g_import = 'from flask import' in content and 'g' in content
    has_g_usage = 'g.request_id' in content or 'g.req_id' in content or re.search(r'g\.\w+.*=.*uuid', content)
    
    # Check for after_request decorator
    has_after_request = '@app.after_request' in content or '@after_request' in content
    
    # Check for X-Request-ID header
    has_request_id_header = 'X-Request-ID' in content or 'X-Request-Id' in content
    
    if has_before_request:
        score += 5
        feedback.append("✅ before_request hook found")
    else:
        feedback.append("❌ No before_request hook found")
        return score
    
    if has_uuid_import and has_uuid_generation:
        score += 5
        feedback.append("✅ UUID generation detected")
    else:
        feedback.append("⚠️ UUID generation not clearly detected")
    
    if has_g_usage:
        score += 5
        feedback.append("✅ Request ID stored in Flask g object")
    
    if has_after_request and has_request_id_header:
        score += 5
        feedback.append("✅ X-Request-ID header added in after_request")
    elif has_after_request:
        score += 2
        feedback.append("⚠️ after_request found but X-Request-ID header unclear")
    
    return min(score, 20)


def check_endpoint_instrumentation(content: str, feedback: List[str]) -> int:
    """Check if endpoints have logging (25 points max)"""
    score = 0
    
    endpoints = {
        '/api/payment': False,
        '/api/balance': False,
        '/api/transaction': False
    }
    
    # Find route definitions and check for logging in each
    for endpoint_path in endpoints.keys():
        # Find the function for this route
        route_pattern = rf"@app\.route\(['\"]" + re.escape(endpoint_path) + r"['\"]"
        if re.search(route_pattern, content):
            # Get the function body (rough approximation)
            match = re.search(route_pattern + r".*?\ndef\s+(\w+)", content, re.DOTALL)
            if match:
                func_name = match.group(1)
                # Look for logging calls in the next 500 characters after function definition
                func_start = match.end()
                func_excerpt = content[func_start:func_start + 800]
                
                # Check for various logging patterns
                has_logging = (
                    'logger.info' in func_excerpt or
                    'logger.debug' in func_excerpt or
                    'logger.warning' in func_excerpt or
                    'logger.error' in func_excerpt or
                    'logging.info' in func_excerpt or
                    'logging.debug' in func_excerpt or
                    'logging.warning' in func_excerpt or
                    'logging.error' in func_excerpt or
                    'app.logger' in func_excerpt
                )
                
                if has_logging:
                    endpoints[endpoint_path] = True
    
    instrumented_count = sum(endpoints.values())
    
    if instrumented_count >= 2:
        score = 25
        feedback.append(f"✅ {instrumented_count}/3 endpoints instrumented with logging")
    elif instrumented_count == 1:
        score = 12
        feedback.append(f"⚠️ Only {instrumented_count}/3 endpoints instrumented (need at least 2)")
    else:
        score = 0
        feedback.append("❌ No endpoints properly instrumented with logging")
    
    return score


def check_timing_mechanism(content: str, feedback: List[str]) -> int:
    """Check for timing decorator or timing code (15 points max)"""
    score = 0
    
    # Check for timing decorator patterns
    has_decorator_def = (
        'def timed(' in content or
        'def timing(' in content or
        'def time_it(' in content or
        'def measure_time(' in content
    )
    
    # Check for time imports
    has_time_import = 'import time' in content or 'from time import' in content
    has_timeit_import = 'import timeit' in content
    
    # Check for time measurement
    has_time_measurement = (
        'time.time()' in content or
        'time.perf_counter()' in content or
        'timeit.' in content
    )
    
    # Check for decorator application
    has_decorator_application = (
        '@timed' in content or
        '@timing' in content or
        '@time_it' in content or
        '@measure_time' in content
    )
    
    if has_decorator_def:
        score += 5
        feedback.append("✅ Timing decorator defined")
        
        if has_decorator_application:
            score += 5
            feedback.append("✅ Timing decorator applied to endpoint")
        else:
            feedback.append("⚠️ Timing decorator defined but not applied")
    
    if has_time_import and has_time_measurement:
        score += 5
        if not has_decorator_def:
            feedback.append("✅ Time measurement code detected")
    
    if score == 0:
        feedback.append("❌ No timing mechanism detected")
    
    return min(score, 15)


def check_security(content: str, feedback: List[str]) -> int:
    """Check that sensitive data is not logged (10 points max)"""
    score = 0
    
    # Sensitive field patterns
    sensitive_patterns = [
        r'password["\']?\s*[,:\)]',
        r'token["\']?\s*[,:\)]',
        r'credit_card["\']?\s*[,:\)]',
        r'api_key["\']?\s*[,:\)]',
        r'secret["\']?\s*[,:\)]'
    ]
    
    # Check if sensitive fields appear in logging calls
    logging_call_pattern = r'(logger\.\w+|logging\.\w+|app\.logger\.\w+)\s*\([^)]*'
    logging_calls = re.findall(logging_call_pattern, content, re.IGNORECASE)
    
    has_sensitive_logging = False
    for match in re.finditer(logging_call_pattern, content, re.IGNORECASE):
        log_statement = content[match.start():match.end() + 100]
        for pattern in sensitive_patterns:
            if re.search(pattern, log_statement, re.IGNORECASE):
                # Check if it's redacted
                if '[REDACTED]' not in log_statement and '***' not in log_statement and 'sanitize' not in log_statement.lower():
                    has_sensitive_logging = True
                    break
    
    # Check for sanitization function
    has_sanitize_function = (
        'def sanitize' in content or
        'def redact' in content or
        'def filter_sensitive' in content or
        '[REDACTED]' in content or
        'SENSITIVE_FIELDS' in content
    )
    
    if has_sanitize_function:
        score = 10
        feedback.append("✅ Sensitive data sanitization detected")
    elif not has_sensitive_logging:
        score = 10
        feedback.append("✅ No sensitive data in logging calls")
    else:
        score = 0
        feedback.append("❌ Sensitive data may be logged without redaction")
    
    return score


def check_code_validity(app_py: str, logging_config: str, middleware: str, feedback: List[str]) -> int:
    """Check if Python files are syntactically valid (5 points max)"""
    score = 5
    
    files_to_check = [
        (app_py, "app.py"),
        (logging_config, "logging_config.py"),
        (middleware, "middleware.py")
    ]
    
    for filepath, name in files_to_check:
        if os.path.exists(filepath) and os.path.getsize(filepath) > 0:
            try:
                with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                    code = f.read()
                    if code.strip():  # Only check non-empty files
                        ast.parse(code)
            except SyntaxError as e:
                score = 0
                feedback.append(f"❌ Syntax error in {name}: {str(e)}")
                return score
    
    feedback.append("✅ All Python files syntactically valid")
    return score
