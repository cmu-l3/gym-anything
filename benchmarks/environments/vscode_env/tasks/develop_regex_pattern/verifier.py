#!/usr/bin/env python3
"""
Verifier for develop_regex_pattern@1 task
Validates that agent developed and tested a working regex pattern for log parsing
"""

import sys
import os
import re
import logging
import tempfile
import shutil
from pathlib import Path
from typing import Tuple, Dict, List, Any

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_regex_pattern(traj, env_info, task_info):
    """
    Verify the regex pattern development task
    
    Returns:
        dict with keys: passed, score, feedback, metadata
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available",
            "metadata": {}
        }
    
    workspace_path = "/home/ga/workspace/log_parser"
    
    # Expected sample logs for validation
    sample_logs = [
        "[2024-01-15 14:23:45.123] INFO auth.login - User john.doe@example.com logged in from 192.168.1.100",
        "[2024-01-15 14:23:46.234] INFO auth.login - User alice+shopping@example.com logged in from 10.0.0.5",
        "[2024-01-15 14:24:12.456] ERROR auth.password - Failed login attempt for admin@example.com (reason: invalid_password)",
        "[2024-01-15 14:25:01.789] WARN auth.session - Session timeout for user@test.com after 3600s",
        "[2024-01-15 14:25:15.901] ERROR auth.mfa - MFA challenge failed for bob.smith@company.org (attempts: 3)",
        "[2024-01-15 14:26:30.112] INFO auth.logout - User jane_doe@example.com logged out (session_duration: 125s)",
        "[2024-01-15 14:27:45.223] DEBUG auth.token - Token refresh for service-account@internal.local",
        "[2024-01-15 14:28:01.334] ERROR auth.rate_limit - Rate limit exceeded for attacker@malicious.net from 203.0.113.42"
    ]
    
    expected_extractions = [
        ("2024-01-15 14:23:45.123", "INFO", "auth.login", "User john.doe@example.com logged in from 192.168.1.100"),
        ("2024-01-15 14:23:46.234", "INFO", "auth.login", "User alice+shopping@example.com logged in from 10.0.0.5"),
        ("2024-01-15 14:24:12.456", "ERROR", "auth.password", "Failed login attempt for admin@example.com (reason: invalid_password)"),
        ("2024-01-15 14:25:01.789", "WARN", "auth.session", "Session timeout for user@test.com after 3600s"),
        ("2024-01-15 14:25:15.901", "ERROR", "auth.mfa", "MFA challenge failed for bob.smith@company.org (attempts: 3)"),
        ("2024-01-15 14:26:30.112", "INFO", "auth.logout", "User jane_doe@example.com logged out (session_duration: 125s)"),
        ("2024-01-15 14:27:45.223", "DEBUG", "auth.token", "Token refresh for service-account@internal.local"),
        ("2024-01-15 14:28:01.334", "ERROR", "auth.rate_limit", "Rate limit exceeded for attacker@malicious.net from 203.0.113.42")
    ]
    
    metadata = {
        "files_created": [],
        "pattern_valid": False,
        "matches_all_logs": False,
        "correct_extractions": 0,
        "total_logs": len(sample_logs),
        "test_evidence_found": False,
        "documentation_found": False,
        "extraction_errors": []
    }
    
    temp_dir = tempfile.mkdtemp(prefix='regex_verify_')
    
    try:
        # Define file paths
        pattern_file_container = f"{workspace_path}/pattern.txt"
        test_results_file_container = f"{workspace_path}/test_results.txt"
        explanation_file_container = f"{workspace_path}/pattern_explanation.md"
        
        pattern_file_local = os.path.join(temp_dir, "pattern.txt")
        test_results_file_local = os.path.join(temp_dir, "test_results.txt")
        explanation_file_local = os.path.join(temp_dir, "pattern_explanation.md")
        
        # Check and copy required files
        files_exist = []
        
        # Copy pattern.txt
        try:
            copy_from_env(pattern_file_container, pattern_file_local)
            if os.path.exists(pattern_file_local) and os.path.getsize(pattern_file_local) > 0:
                files_exist.append("pattern.txt")
                metadata["files_created"].append("pattern.txt")
            else:
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": "FAILED: pattern.txt file not found or empty",
                    "metadata": metadata
                }
        except Exception as e:
            logger.error(f"Failed to copy pattern.txt: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"FAILED: Could not access pattern.txt - {str(e)}",
                "metadata": metadata
            }
        
        # Copy test_results.txt
        try:
            copy_from_env(test_results_file_container, test_results_file_local)
            if os.path.exists(test_results_file_local) and os.path.getsize(test_results_file_local) > 0:
                files_exist.append("test_results.txt")
                metadata["files_created"].append("test_results.txt")
            else:
                logger.warning("test_results.txt not found or empty")
        except Exception as e:
            logger.warning(f"Failed to copy test_results.txt: {e}")
        
        # Copy pattern_explanation.md
        try:
            copy_from_env(explanation_file_container, explanation_file_local)
            if os.path.exists(explanation_file_local) and os.path.getsize(explanation_file_local) > 0:
                files_exist.append("pattern_explanation.md")
                metadata["files_created"].append("pattern_explanation.md")
            else:
                logger.warning("pattern_explanation.md not found or empty")
        except Exception as e:
            logger.warning(f"Failed to copy pattern_explanation.md: {e}")
        
        if "test_results.txt" not in files_exist:
            return {
                "passed": False,
                "score": 0.1,
                "feedback": "FAILED: test_results.txt file not found or empty",
                "metadata": metadata
            }
        
        if "pattern_explanation.md" not in files_exist:
            return {
                "passed": False,
                "score": 0.1,
                "feedback": "FAILED: pattern_explanation.md file not found or empty",
                "metadata": metadata
            }
        
        # Read and validate pattern
        try:
            with open(pattern_file_local, 'r', encoding='utf-8') as f:
                pattern_text = f.read().strip()
            
            if not pattern_text:
                return {
                    "passed": False,
                    "score": 0.1,
                    "feedback": "FAILED: pattern.txt is empty",
                    "metadata": metadata
                }
            
            # Try to compile the regex
            try:
                pattern = re.compile(pattern_text)
                metadata["pattern_valid"] = True
            except re.error as e:
                return {
                    "passed": False,
                    "score": 0.1,
                    "feedback": f"FAILED: Invalid regex pattern: {str(e)}",
                    "metadata": metadata
                }
        except Exception as e:
            return {
                "passed": False,
                "score": 0.1,
                "feedback": f"FAILED: Error reading pattern.txt: {str(e)}",
                "metadata": metadata
            }
        
        # Test pattern against all sample logs
        correct_count = 0
        incorrect_details = []
        
        for i, log_line in enumerate(sample_logs):
            match = pattern.search(log_line)
            if not match:
                error = f"Line {i+1}: Pattern did not match"
                incorrect_details.append(error)
                metadata["extraction_errors"].append(error)
                continue
            
            groups = match.groups()
            if len(groups) < 4:
                error = f"Line {i+1}: Pattern has fewer than 4 capturing groups (found {len(groups)})"
                incorrect_details.append(error)
                metadata["extraction_errors"].append(error)
                continue
            
            expected = expected_extractions[i]
            actual = groups[:4]  # Take first 4 groups
            
            # Check each component with some tolerance
            timestamp_match = expected[0] in str(actual[0]) if actual[0] else False
            level_match = expected[1].strip() == str(actual[1]).strip() if actual[1] else False
            component_match = expected[2].strip() == str(actual[2]).strip() if actual[2] else False
            
            # Message matching - allow for some whitespace differences
            message_expected = expected[3].strip()
            message_actual = str(actual[3]).strip() if actual[3] else ""
            message_match = message_expected == message_actual
            
            if timestamp_match and level_match and component_match and message_match:
                correct_count += 1
            else:
                details = []
                if not timestamp_match:
                    details.append(f"timestamp: expected '{expected[0]}', got '{actual[0]}'")
                if not level_match:
                    details.append(f"level: expected '{expected[1]}', got '{actual[1]}'")
                if not component_match:
                    details.append(f"component: expected '{expected[2]}', got '{actual[2]}'")
                if not message_match:
                    details.append(f"message mismatch (length: expected {len(message_expected)}, got {len(message_actual)})")
                error = f"Line {i+1}: {'; '.join(details)}"
                incorrect_details.append(error)
                metadata["extraction_errors"].append(error)
        
        metadata["correct_extractions"] = correct_count
        metadata["matches_all_logs"] = (correct_count == len(sample_logs))
        
        # Check test results file for evidence
        with open(test_results_file_local, 'r', encoding='utf-8') as f:
            test_content = f.read()
        
        if len(test_content) > 50:  # Non-trivial content
            # Check if it contains evidence of testing
            evidence_keywords = [
                "group", "match", "timestamp", "INFO", "ERROR", "WARN", "DEBUG",
                "auth.", "2024-01-15", "capturing"
            ]
            evidence_count = sum(1 for kw in evidence_keywords if kw.lower() in test_content.lower())
            if evidence_count >= 3:
                metadata["test_evidence_found"] = True
        
        # Check explanation file
        with open(explanation_file_local, 'r', encoding='utf-8') as f:
            explanation_content = f.read()
        
        if len(explanation_content) > 50:  # At least 50 characters
            # Check if it contains the pattern and some explanation
            if pattern_text in explanation_content or "regex" in explanation_content.lower():
                metadata["documentation_found"] = True
        
        # Calculate score
        score = 0.0
        feedback_parts = []
        
        # Pattern validity: 20%
        if metadata["pattern_valid"]:
            score += 0.2
            feedback_parts.append("✅ Valid regex pattern")
        else:
            feedback_parts.append("❌ Invalid regex pattern")
        
        # Correctness: 50% (proportional to correct extractions)
        extraction_score = (correct_count / len(sample_logs)) * 0.5
        score += extraction_score
        
        if correct_count == len(sample_logs):
            feedback_parts.append(f"✅ Correctly parsed all {len(sample_logs)} log lines")
        elif correct_count > 0:
            feedback_parts.append(f"⚠️ Correctly parsed {correct_count}/{len(sample_logs)} log lines")
        else:
            feedback_parts.append(f"❌ Failed to parse any log lines correctly")
        
        # Add details about errors (limit to first 2 for brevity)
        if incorrect_details and len(incorrect_details) <= 2:
            for detail in incorrect_details[:2]:
                feedback_parts.append(f"Issue: {detail}")
        elif len(incorrect_details) > 2:
            feedback_parts.append(f"Issues found in {len(incorrect_details)} log lines")
        
        # Testing evidence: 20%
        if metadata["test_evidence_found"]:
            score += 0.2
            feedback_parts.append("✅ Test results show validation evidence")
        else:
            feedback_parts.append("❌ Test results lack clear testing evidence")
        
        # Documentation: 10%
        if metadata["documentation_found"]:
            score += 0.1
            feedback_parts.append("✅ Pattern explanation provided")
        else:
            feedback_parts.append("❌ Pattern explanation insufficient")
        
        # Success threshold: 0.8 (need 80% to pass)
        passed = score >= 0.8
        
        if passed:
            feedback = f"SUCCESS (score: {score:.2f}): {' | '.join(feedback_parts)}"
        else:
            feedback = f"PARTIAL (score: {score:.2f}): {' | '.join(feedback_parts)}"
        
        return {
            "passed": passed,
            "score": int(score * 100),
            "feedback": feedback,
            "metadata": metadata
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "metadata": metadata
        }
    finally:
        # Cleanup temp directory
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
