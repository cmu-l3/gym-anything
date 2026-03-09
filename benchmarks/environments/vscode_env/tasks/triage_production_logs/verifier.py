#!/usr/bin/env python3
"""
Verifier for Triage Production Logs task
"""

import sys
import os
import logging
import tempfile
import re
from pathlib import Path
from typing import Dict, Set, Tuple, Any

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_transaction_ids(content: str) -> Set[str]:
    """Extract all transaction IDs from content"""
    pattern = r'txn_\d{12}'
    return set(re.findall(pattern, content))


def extract_error_counts(content: str) -> Dict[str, int]:
    """
    Extract error type counts from summary
    Matches patterns like:
    - "ERR_PAYMENT_TIMEOUT: 23 occurrences"
    - "ERR_INVALID_CARD: 8"
    - "**ERR_PAYMENT_TIMEOUT**: 23 occurrences"
    """
    counts = {}
    
    # Pattern 1: "ERR_XXX: number"
    pattern1 = r'(ERR_[A-Z_]+)\s*:\s*(\d+)'
    for match in re.finditer(pattern1, content, re.IGNORECASE):
        error_type = match.group(1).upper()
        count = int(match.group(2))
        counts[error_type] = count
    
    # Pattern 2: "number ERR_XXX" (reverse order)
    pattern2 = r'(\d+)\s+(ERR_[A-Z_]+)'
    for match in re.finditer(pattern2, content, re.IGNORECASE):
        count = int(match.group(1))
        error_type = match.group(2).upper()
        if error_type not in counts:  # Don't override if already found
            counts[error_type] = count
    
    return counts


def check_structure(content: str) -> Tuple[bool, int]:
    """Check if summary has proper structure with sections"""
    content_lower = content.lower()
    
    # Check for section indicators (headers, keywords)
    structure_indicators = [
        'error' in content_lower,
        'transaction' in content_lower,
        'summary' in content_lower or 'incident' in content_lower,
        'timeline' in content_lower or 'timestamp' in content_lower or 'time' in content_lower,
        '#' in content or '##' in content or '###' in content,  # Markdown headers
        'recommend' in content_lower or 'action' in content_lower or 'next step' in content_lower
    ]
    
    score = sum(structure_indicators)
    has_structure = score >= 3  # Need at least 3 indicators
    
    return has_structure, score


def parse_log_ground_truth(log_content: str) -> Tuple[Dict[str, int], Set[str]]:
    """Parse the source log to extract ground truth"""
    actual_errors = {}
    actual_txn_ids = set()
    
    for line in log_content.split('\n'):
        # Extract transaction IDs
        txn_matches = re.findall(r'txn_\d{12}', line)
        actual_txn_ids.update(txn_matches)
        
        # Count errors (only ERROR and CRITICAL lines)
        if '[ERROR]' in line or '[CRITICAL]' in line:
            error_match = re.search(r'(ERR_[A-Z_]+)', line)
            if error_match:
                error_type = error_match.group(1).upper()
                actual_errors[error_type] = actual_errors.get(error_type, 0) + 1
    
    return actual_errors, actual_txn_ids


def verify_triage_summary(traj, env_info, task_info):
    """
    Verify that triage summary was created correctly.
    
    Checks:
    1. File exists and has sufficient content
    2. Contains at least 10 transaction IDs
    3. All transaction IDs are real (not fabricated)
    4. At least 3 error types identified
    5. Error counts are accurate (within 10% tolerance)
    6. Most common error is identified
    7. Has proper structure
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='triage_verify_')
    
    try:
        workspace_path = "/home/ga/workspace/incident_logs"
        summary_path = f"{workspace_path}/triage_summary.md"
        log_path = f"{workspace_path}/production_payment_service.log"
        
        local_summary = os.path.join(temp_dir, "triage_summary.md")
        local_log = os.path.join(temp_dir, "production_payment_service.log")
        
        # Copy files
        try:
            copy_from_env(summary_path, local_summary)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ triage_summary.md not found or could not be copied: {str(e)}"
            }
        
        try:
            copy_from_env(log_path, local_log)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Source log file not found: {str(e)}"
            }
        
        # Read files
        if not os.path.exists(local_summary) or os.path.getsize(local_summary) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ triage_summary.md is empty or not found"
            }
        
        summary_content = read_file_content(local_summary)
        log_content = read_file_content(local_log)
        
        feedback_parts = []
        criteria_met = 0
        total_criteria = 7
        
        # Criterion 1: File has sufficient content (>500 chars)
        if len(summary_content) < 500:
            feedback_parts.append(f"❌ Summary too short: {len(summary_content)} chars (need >500)")
            return {
                "passed": False,
                "score": int((criteria_met / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        else:
            criteria_met += 1
            feedback_parts.append(f"✅ Summary has sufficient content ({len(summary_content)} chars)")
        
        # Parse ground truth from log
        actual_errors, actual_txn_ids = parse_log_ground_truth(log_content)
        
        # Extract data from summary
        summary_txn_ids = extract_transaction_ids(summary_content)
        claimed_errors = extract_error_counts(summary_content)
        
        # Criterion 2: Contains at least 10 transaction IDs
        if len(summary_txn_ids) < 10:
            feedback_parts.append(f"❌ Insufficient transaction IDs: {len(summary_txn_ids)}/10")
            return {
                "passed": False,
                "score": int((criteria_met / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        else:
            criteria_met += 1
            feedback_parts.append(f"✅ Found {len(summary_txn_ids)} transaction IDs")
        
        # Criterion 3: All transaction IDs are real (not fabricated)
        fabricated = summary_txn_ids - actual_txn_ids
        if fabricated:
            fabricated_list = list(fabricated)[:3]
            feedback_parts.append(f"❌ Fabricated transaction IDs detected: {fabricated_list}")
            return {
                "passed": False,
                "score": 0,  # Zero score for fabricated data
                "feedback": " | ".join(feedback_parts)
            }
        else:
            criteria_met += 1
            feedback_parts.append("✅ All transaction IDs are valid")
        
        # Criterion 4: At least 3 error types identified
        if len(claimed_errors) < 3:
            feedback_parts.append(f"❌ Too few error types: {len(claimed_errors)}/3")
            return {
                "passed": False,
                "score": int((criteria_met / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        else:
            criteria_met += 1
            feedback_parts.append(f"✅ Identified {len(claimed_errors)} error types")
        
        # Criterion 5: Error counts are accurate (within 10% tolerance)
        inaccurate = []
        for error_type, claimed_count in claimed_errors.items():
            if error_type not in actual_errors:
                inaccurate.append(f"{error_type} not in log")
                continue
            
            actual_count = actual_errors[error_type]
            tolerance = max(1, int(actual_count * 0.1))  # 10% or at least 1
            
            if abs(claimed_count - actual_count) > tolerance:
                inaccurate.append(f"{error_type}: claimed {claimed_count}, actual {actual_count}")
        
        if inaccurate:
            feedback_parts.append(f"❌ Inaccurate error counts: {'; '.join(inaccurate[:2])}")
            return {
                "passed": False,
                "score": int((criteria_met / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        else:
            criteria_met += 1
            feedback_parts.append("✅ Error counts accurate (within tolerance)")
        
        # Criterion 6: Most common error is identified
        if actual_errors:
            most_common_error = max(actual_errors, key=actual_errors.get)
            if most_common_error not in claimed_errors:
                feedback_parts.append(f"❌ Missed most common error: {most_common_error} ({actual_errors[most_common_error]} occurrences)")
                return {
                    "passed": False,
                    "score": int((criteria_met / total_criteria) * 100),
                    "feedback": " | ".join(feedback_parts)
                }
            else:
                criteria_met += 1
                feedback_parts.append(f"✅ Most common error identified: {most_common_error}")
        else:
            criteria_met += 1  # No errors to identify
        
        # Criterion 7: Has proper structure
        has_structure, structure_score = check_structure(summary_content)
        if not has_structure:
            feedback_parts.append(f"❌ Lacks proper structure (score: {structure_score}/6)")
            return {
                "passed": False,
                "score": int((criteria_met / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        else:
            criteria_met += 1
            feedback_parts.append(f"✅ Well-structured summary (score: {structure_score}/6)")
        
        # All criteria met!
        score = int((criteria_met / total_criteria) * 100)
        
        return {
            "passed": True,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": {
                "transactions_found": len(summary_txn_ids),
                "error_types_analyzed": len(claimed_errors),
                "accuracy": "within tolerance",
                "structure_score": structure_score,
                "criteria_met": f"{criteria_met}/{total_criteria}"
            }
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Cleanup
        if os.path.exists(temp_dir):
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)
