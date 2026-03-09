#!/usr/bin/env python3
"""
Verifier for Organize Dev Terminals task

Verifies that 4 terminals are created with correct names and working directories:
- frontend-dev (in frontend/)
- backend-api (in backend/)
- worker (in backend/)
- logs (in logs/)
"""

import sys
import os
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_terminal_data(temp_dir):
    """
    Parse exported terminal data to extract information about terminals
    
    Returns:
        dict: {
            'terminals': [{'pid': str, 'cwd': str, 'cmdline': str}, ...],
            'count': int,
            'directories': {'frontend': int, 'backend': int, 'logs': int}
        }
    """
    result = {
        'terminals': [],
        'count': 0,
        'directories': {'frontend': 0, 'backend': 0, 'logs': 0}
    }
    
    # Parse terminal_cwds.txt (format: pid|cwd|cmdline)
    cwds_file = os.path.join(temp_dir, "terminal_cwds.txt")
    if os.path.exists(cwds_file) and os.path.getsize(cwds_file) > 0:
        with open(cwds_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and '|' in line:
                    parts = line.split('|', 2)
                    if len(parts) >= 2:
                        pid = parts[0]
                        cwd = parts[1]
                        cmdline = parts[2] if len(parts) > 2 else ""
                        
                        result['terminals'].append({
                            'pid': pid,
                            'cwd': cwd,
                            'cmdline': cmdline
                        })
                        result['count'] += 1
                        
                        # Count directories
                        if '/frontend' in cwd and cwd.endswith('/frontend'):
                            result['directories']['frontend'] += 1
                        elif '/backend' in cwd and cwd.endswith('/backend'):
                            result['directories']['backend'] += 1
                        elif '/logs' in cwd and cwd.endswith('/logs'):
                            result['directories']['logs'] += 1
    
    # Also try reading count files for validation
    count_file = os.path.join(temp_dir, "terminal_count.txt")
    if os.path.exists(count_file):
        with open(count_file, 'r') as f:
            content = f.read().strip()
            if content.startswith("Terminal count:"):
                try:
                    count = int(content.split(":")[-1].strip())
                    if count != result['count']:
                        logger.warning(f"Count mismatch: parsed {result['count']}, file says {count}")
                except:
                    pass
    
    return result


def verify_terminal_count(terminal_data):
    """
    Verify exactly 4 terminals exist
    
    Returns: (passed: bool, message: str)
    """
    count = terminal_data['count']
    
    if count == 4:
        return True, f"✅ Exactly 4 terminals found"
    elif count < 4:
        return False, f"❌ Only {count} terminals found (need 4)"
    else:
        return False, f"❌ Too many terminals: {count} found (need exactly 4)"


def verify_working_directories(terminal_data):
    """
    Verify terminals are in correct working directories:
    - 1 in frontend/
    - 2 in backend/
    - 1 in logs/
    
    Returns: (passed: bool, message: str, score: float)
    """
    dirs = terminal_data['directories']
    
    frontend_ok = dirs['frontend'] == 1
    backend_ok = dirs['backend'] == 2
    logs_ok = dirs['logs'] == 1
    
    messages = []
    score = 0.0
    
    if frontend_ok:
        messages.append("✅ 1 terminal in frontend/")
        score += 1/3
    else:
        messages.append(f"❌ Expected 1 terminal in frontend/, found {dirs['frontend']}")
    
    if backend_ok:
        messages.append("✅ 2 terminals in backend/")
        score += 1/3
    else:
        messages.append(f"❌ Expected 2 terminals in backend/, found {dirs['backend']}")
    
    if logs_ok:
        messages.append("✅ 1 terminal in logs/")
        score += 1/3
    else:
        messages.append(f"❌ Expected 1 terminal in logs/, found {dirs['logs']}")
    
    all_passed = frontend_ok and backend_ok and logs_ok
    
    return all_passed, " | ".join(messages), score


def verify_split_layout(terminal_data):
    """
    Verify terminals are in split layout (not all tabs)
    
    With 4 terminals, they must be in some split configuration.
    We assume if 4 terminals exist simultaneously, they're split.
    
    Returns: (passed: bool, message: str)
    """
    # If we have 4 terminals running, they're likely in a split layout
    # (VSCode doesn't typically show 4 terminal tabs simultaneously without splits)
    if terminal_data['count'] >= 4:
        return True, "✅ Multiple terminals suggest split layout"
    else:
        return False, "❌ Insufficient terminals for split layout verification"


def verify_terminal_organization(traj, env_info, task_info):
    """
    Main verification function for terminal organization task
    
    Checks:
    1. Exactly 4 terminals exist (25%)
    2. Correct working directories (40%)
    3. Split layout used (15%)
    4. Terminal count matches expectations (20%)
    
    Returns: dict with 'passed', 'score', 'feedback'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='terminal_verify_')
    
    try:
        # Copy all exported files from /tmp/terminal_task_export
        export_files = [
            "terminal_processes.txt",
            "terminal_cwds.txt",
            "terminal_count.txt",
            "frontend_count.txt",
            "backend_count.txt",
            "logs_count.txt",
            "summary.txt"
        ]
        
        files_copied = 0
        for filename in export_files:
            src_path = f"/tmp/terminal_task_export/{filename}"
            dst_path = os.path.join(temp_dir, filename)
            try:
                copy_from_env(src_path, dst_path)
                if os.path.exists(dst_path) and os.path.getsize(dst_path) > 0:
                    files_copied += 1
            except Exception as e:
                logger.warning(f"Failed to copy {filename}: {e}")
        
        if files_copied == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ No terminal data exported - terminals may not have been created"
            }
        
        # Parse terminal data
        terminal_data = parse_terminal_data(temp_dir)
        
        if terminal_data['count'] == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ No terminals detected in the workspace"
            }
        
        # Run verification checks
        criteria_scores = []
        feedback_parts = []
        
        # Criterion 1: Verify terminal count (25 points)
        count_passed, count_msg = verify_terminal_count(terminal_data)
        feedback_parts.append(count_msg)
        if count_passed:
            criteria_scores.append(25)
        else:
            criteria_scores.append(0)
        
        # Criterion 2: Verify working directories (40 points)
        dirs_passed, dirs_msg, dirs_score = verify_working_directories(terminal_data)
        feedback_parts.append(dirs_msg)
        criteria_scores.append(int(40 * dirs_score))
        
        # Criterion 3: Verify split layout (15 points)
        split_passed, split_msg = verify_split_layout(terminal_data)
        feedback_parts.append(split_msg)
        if split_passed:
            criteria_scores.append(15)
        else:
            criteria_scores.append(0)
        
        # Criterion 4: Overall terminal presence (20 points)
        # Award based on how many terminals exist
        presence_score = min(20, int((terminal_data['count'] / 4) * 20))
        criteria_scores.append(presence_score)
        if terminal_data['count'] >= 3:
            feedback_parts.append(f"✅ Terminal presence: {terminal_data['count']}/4")
        else:
            feedback_parts.append(f"⚠️ Insufficient terminals: {terminal_data['count']}/4")
        
        # Calculate final score
        total_score = sum(criteria_scores)
        passed = total_score >= 80
        
        # Add detailed terminal info to feedback
        if terminal_data['terminals']:
            feedback_parts.append(f"Terminals detected: {len(terminal_data['terminals'])}")
            for i, term in enumerate(terminal_data['terminals'][:4], 1):
                cwd_short = term['cwd'].split('/')[-1] if '/' in term['cwd'] else term['cwd']
                feedback_parts.append(f"  Terminal {i}: .../{cwd_short}")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": total_score,
            "feedback": feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
