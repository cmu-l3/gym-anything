#!/usr/bin/env python3
"""
Verifier for JSON Validation Documentation task
"""

import sys
import os
import json
import re
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def detect_json_errors(filepath):
    """
    Detect JSON syntax errors by attempting to parse.
    Returns list of errors with line numbers and messages.
    """
    errors = []
    try:
        with open(filepath, 'r') as f:
            content = f.read()
            try:
                json.loads(content)
            except json.JSONDecodeError as e:
                errors.append({
                    'line': e.lineno,
                    'column': e.colno,
                    'message': e.msg,
                    'file': os.path.basename(filepath)
                })
    except Exception as e:
        logger.warning(f"Could not read file {filepath}: {e}")
    
    return errors


def check_for_logical_errors(filepath):
    """
    Check for logical errors like duplicate keys, negative values in wrong places.
    Returns list of issues.
    """
    issues = []
    try:
        with open(filepath, 'r') as f:
            content = f.read()
            lines = content.split('\n')
            
            # Check for duplicate keys
            seen_keys = {}
            for i, line in enumerate(lines, 1):
                # Simple key detection (not perfect but good enough)
                key_match = re.search(r'"(\w+)"\s*:', line)
                if key_match:
                    key = key_match.group(1)
                    if key in seen_keys:
                        issues.append({
                            'line': i,
                            'message': f'Duplicate key "{key}"',
                            'file': os.path.basename(filepath),
                            'type': 'logical'
                        })
                    seen_keys[key] = i
            
            # Check for negative values in suspicious contexts
            if 'maxConnections' in content:
                for i, line in enumerate(lines, 1):
                    if 'maxConnections' in line and '-' in line:
                        issues.append({
                            'line': i,
                            'message': 'Negative value for maxConnections',
                            'file': os.path.basename(filepath),
                            'type': 'logical'
                        })
    
    except Exception as e:
        logger.warning(f"Could not analyze file {filepath}: {e}")
    
    return issues


def verify_json_validation_task(traj, env_info, task_info):
    """
    Verify that JSON validation documentation task was completed.
    
    Checks:
    1. Report file exists (validation_report.md)
    2. Report has proper markdown structure (headers, etc.)
    3. Report documents at least 80% of actual JSON errors
    4. Report mentions all problematic files
    5. Report includes line numbers
    6. Report has clear descriptions (not just raw errors)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='json_validation_verify_')
    
    try:
        workspace = "/home/ga/workspace/json_validation_task"
        report_path = f"{workspace}/validation_report.md"
        
        # JSON files to check
        json_files = [
            f"{workspace}/config.json",
            f"{workspace}/database.json",
            f"{workspace}/api_settings.json"
        ]
        
        # Copy report file
        local_report = os.path.join(temp_dir, "validation_report.md")
        try:
            copy_from_env(report_path, local_report)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Report file not found or could not be copied: {e}"
            }
        
        # Check report exists and has content
        if not os.path.exists(local_report) or os.path.getsize(local_report) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Report file is empty or missing"
            }
        
        with open(local_report, 'r') as f:
            report_content = f.read()
        
        score = 0
        max_score = 100
        feedback_parts = []
        
        # Criterion 1: Check markdown structure (15 points)
        has_headers = bool(re.search(r'^#+\s+.+', report_content, re.MULTILINE))
        has_summary = any(keyword in report_content.lower() 
                         for keyword in ['summary', 'found', 'errors'])
        has_list_or_sections = bool(re.search(r'^\s*[-*\d]+\.?\s+', report_content, re.MULTILINE))
        
        structure_score = 0
        if has_headers:
            structure_score += 5
        if has_summary:
            structure_score += 5
        if has_list_or_sections:
            structure_score += 5
        
        score += structure_score
        if structure_score >= 10:
            feedback_parts.append("✅ Report has proper markdown structure")
        else:
            feedback_parts.append(f"△ Report structure incomplete ({structure_score}/15 points)")
        
        # Copy JSON files and detect actual errors
        actual_errors = []
        for json_file in json_files:
            local_json = os.path.join(temp_dir, os.path.basename(json_file))
            try:
                copy_from_env(json_file, local_json)
                
                # Detect syntax errors
                syntax_errors = detect_json_errors(local_json)
                actual_errors.extend(syntax_errors)
                
                # Detect logical errors
                logical_errors = check_for_logical_errors(local_json)
                actual_errors.extend(logical_errors)
                
            except Exception as e:
                logger.warning(f"Could not process {json_file}: {e}")
        
        if not actual_errors:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Task setup issue: No JSON errors found in workspace files"
            }
        
        logger.info(f"Detected {len(actual_errors)} actual errors in JSON files")
        
        # Criterion 2: Check file coverage (20 points)
        mentioned_files = set()
        for json_file in json_files:
            filename = os.path.basename(json_file)
            if filename in report_content or filename.replace('.json', '') in report_content:
                mentioned_files.add(filename)
        
        file_coverage_ratio = len(mentioned_files) / len(json_files)
        file_coverage_score = int(20 * file_coverage_ratio)
        score += file_coverage_score
        
        if file_coverage_ratio >= 0.8:
            feedback_parts.append(f"✅ Report covers {len(mentioned_files)}/{len(json_files)} problematic files")
        elif file_coverage_ratio >= 0.5:
            feedback_parts.append(f"△ Report covers only {len(mentioned_files)}/{len(json_files)} files")
        else:
            feedback_parts.append(f"✗ Report missing multiple files ({len(mentioned_files)}/{len(json_files)})")
        
        # Criterion 3: Check error coverage (30 points)
        documented_errors = 0
        for error in actual_errors:
            file_mentioned = error['file'] in report_content
            
            # Check if line number is mentioned (with tolerance of ±3 lines)
            line_num = error['line']
            line_mentioned = False
            for offset in range(-3, 4):
                check_line = line_num + offset
                if check_line > 0:
                    # Look for line number references
                    if re.search(rf'\b{check_line}\b', report_content):
                        line_mentioned = True
                        break
            
            # Check if error type/message keywords are present
            error_msg = error['message'].lower()
            # Extract key words from error message
            keywords = [word for word in re.findall(r'\w+', error_msg) 
                       if len(word) > 3 and word not in ['expected', 'line', 'column']]
            
            msg_mentioned = any(keyword in report_content.lower() for keyword in keywords) if keywords else False
            
            # Count as documented if file is mentioned AND (line or message keywords present)
            if file_mentioned and (line_mentioned or msg_mentioned):
                documented_errors += 1
        
        error_coverage_ratio = documented_errors / len(actual_errors) if actual_errors else 0
        error_coverage_score = int(30 * error_coverage_ratio)
        score += error_coverage_score
        
        if error_coverage_ratio >= 0.8:
            feedback_parts.append(f"✅ Report documents {documented_errors}/{len(actual_errors)} errors ({int(error_coverage_ratio*100)}%)")
        elif error_coverage_ratio >= 0.5:
            feedback_parts.append(f"△ Report documents {documented_errors}/{len(actual_errors)} errors ({int(error_coverage_ratio*100)}% - incomplete)")
        else:
            feedback_parts.append(f"✗ Report misses many errors ({documented_errors}/{len(actual_errors)}, {int(error_coverage_ratio*100)}%)")
        
        # Criterion 4: Check for clear descriptions (20 points)
        # Look for explanatory language indicating understanding
        explanation_keywords = [
            'missing', 'expected', 'invalid', 'should', 'must',
            'fix', 'add', 'remove', 'change', 'replace', 'correct',
            'comma', 'bracket', 'quote', 'brace', 'colon',
            'syntax', 'error', 'wrong', 'incorrect'
        ]
        
        explanation_count = sum(1 for keyword in explanation_keywords 
                               if keyword in report_content.lower())
        word_count = len(report_content.split())
        
        description_score = 0
        if explanation_count >= 5 and word_count >= 100:
            description_score = 20
            feedback_parts.append("✅ Report contains clear explanations")
        elif explanation_count >= 3 and word_count >= 50:
            description_score = 12
            feedback_parts.append("△ Report has some explanations but could be more detailed")
        elif explanation_count >= 1:
            description_score = 6
            feedback_parts.append("△ Report has minimal explanations")
        else:
            feedback_parts.append("✗ Report lacks clear explanations")
        
        score += description_score
        
        # Criterion 5: Check for line numbers (15 points)
        # Look for line number references
        line_number_pattern = r'(?:line|Line|LINE)\s*:?\s*\d+|(?:^|\s)(?:line\s+)?\d+(?:\s*:|\s*-)'
        line_refs = re.findall(line_number_pattern, report_content)
        
        line_number_score = 0
        if len(line_refs) >= len(actual_errors) * 0.7:
            line_number_score = 15
            feedback_parts.append(f"✅ Report includes line numbers ({len(line_refs)} references)")
        elif len(line_refs) >= 2:
            line_number_score = 8
            feedback_parts.append(f"△ Report has some line numbers ({len(line_refs)} references)")
        else:
            feedback_parts.append("✗ Report missing line number references")
        
        score += line_number_score
        
        # Ensure score doesn't exceed 100
        score = min(score, max_score)
        
        # Determine pass/fail
        passed = score >= 75
        
        # Build final feedback
        feedback_str = " | ".join(feedback_parts)
        final_message = f"Score: {score}/{max_score}\n{feedback_str}\n\nActual JSON errors in workspace: {len(actual_errors)}"
        
        return {
            "passed": passed,
            "score": score,
            "feedback": final_message
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
