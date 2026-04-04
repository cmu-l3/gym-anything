#!/usr/bin/env python3
"""
Verifier for Log Correlation Task
"""

import sys
import os
import re
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_section(content: str, section_name: str) -> str:
    """
    Extract content between markdown section headers
    
    Args:
        content: Full markdown content
        section_name: Section header name to extract
        
    Returns:
        Section content as string
    """
    # Match ## Section or # Section, capture content until next header or end
    pattern = rf'##?\s*{re.escape(section_name)}[^\n]*\n(.*?)(?=##?\s+\w+|\Z)'
    match = re.search(pattern, content, re.IGNORECASE | re.DOTALL)
    return match.group(1).strip() if match else ""


def verify_log_correlation_task(traj, env_info, task_info):
    """
    Verify that the log correlation incident report was created correctly.
    
    Checks:
    1. File exists at expected location
    2. Contains required sections (Root Cause, Timeline, Evidence)
    3. Root cause mentions connection pool issue
    4. Timeline has at least 3 timestamps
    5. Evidence references multiple log files
    6. Content is substantive (not just template)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_report_path = "/home/ga/workspace/log_analysis/docs/incident_report_2024-01-23.md"
    temp_dir = tempfile.mkdtemp(prefix='log_verify_')
    
    try:
        # Copy the incident report
        local_report = os.path.join(temp_dir, "incident_report.md")
        
        try:
            copy_from_env(container_report_path, local_report)
        except Exception as e:
            logger.warning(f"Failed to copy report from expected path: {e}")
            # Try copying from /tmp as backup
            try:
                copy_from_env("/tmp/incident_report_2024-01-23.md", local_report)
            except Exception as e2:
                return {
                    "passed": False, 
                    "score": 0, 
                    "feedback": f"❌ Incident report not found at expected location: {container_report_path}"
                }
        
        if not os.path.exists(local_report) or os.path.getsize(local_report) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Incident report file is empty or not found"
            }
        
        # Read report content
        content = read_file_content(local_report)
        
        scores = {}
        feedback_parts = []
        
        # Criterion 1: File exists (already verified above)
        scores['file_exists'] = 1.0
        feedback_parts.append("✅ File exists at correct location")
        
        # Criterion 2: Required sections present
        required_sections = {
            'Root Cause': r'##?\s*Root\s*Cause',
            'Timeline': r'##?\s*Timeline',
            'Evidence': r'##?\s*Evidence'
        }
        
        sections_found = {}
        for section_display, pattern in required_sections.items():
            if re.search(pattern, content, re.IGNORECASE):
                sections_found[section_display] = True
                scores[f'has_{section_display.lower().replace(" ", "_")}_section'] = 1.0
            else:
                sections_found[section_display] = False
                scores[f'has_{section_display.lower().replace(" ", "_")}_section'] = 0.0
                feedback_parts.append(f"❌ Missing required section: {section_display}")
        
        if all(sections_found.values()):
            feedback_parts.append("✅ All required sections present")
        
        # Criterion 3: Root Cause mentions connection pool
        root_cause_section = extract_section(content, "Root Cause")
        connection_pool_keywords = [
            'connection pool',
            'connection.*pool',
            'pool.*exhaust',
            'pool.*deplet'
        ]
        
        connection_pool_mentioned = False
        for keyword in connection_pool_keywords:
            if re.search(keyword, root_cause_section, re.IGNORECASE):
                connection_pool_mentioned = True
                break
        
        if connection_pool_mentioned:
            scores['correct_root_cause'] = 1.0
            feedback_parts.append("✅ Root cause correctly identifies connection pool issue")
        else:
            scores['correct_root_cause'] = 0.0
            # Check if they at least mentioned database or performance
            if re.search(r'database|query|export|job', root_cause_section, re.IGNORECASE):
                scores['correct_root_cause'] = 0.5
                feedback_parts.append("⚠️ Root cause mentions database/export but not connection pool specifically")
            else:
                feedback_parts.append("❌ Root cause doesn't mention connection pool (key element)")
        
        # Criterion 4: Timeline has at least 3 timestamps
        timeline_section = extract_section(content, "Timeline")
        
        # Match various timestamp formats
        timestamp_patterns = [
            r'\d{1,2}:\d{2}:\d{2}',  # 14:23:15
            r'\d{1,2}:\d{2}\s*[AP]M',  # 2:23 PM or 14:23 PM
            r'\d{4}-\d{2}-\d{2}\s+\d{1,2}:\d{2}',  # 2024-01-23 14:23
        ]
        
        timestamps_found = []
        for pattern in timestamp_patterns:
            timestamps_found.extend(re.findall(pattern, timeline_section, re.IGNORECASE))
        
        # Remove duplicates while preserving order
        unique_timestamps = []
        seen = set()
        for ts in timestamps_found:
            if ts not in seen:
                unique_timestamps.append(ts)
                seen.add(ts)
        
        timestamp_count = len(unique_timestamps)
        
        if timestamp_count >= 3:
            scores['timeline_detailed'] = 1.0
            feedback_parts.append(f"✅ Timeline has {timestamp_count} timestamps")
        elif timestamp_count > 0:
            scores['timeline_detailed'] = timestamp_count / 3.0
            feedback_parts.append(f"⚠️ Timeline has only {timestamp_count} timestamp(s), expected ≥3")
        else:
            scores['timeline_detailed'] = 0.0
            feedback_parts.append("❌ Timeline missing timestamps")
        
        # Criterion 5: Evidence references multiple log files
        evidence_section = extract_section(content, "Evidence")
        
        log_files = ['application.log', 'database.log', 'requests.log']
        log_files_mentioned = []
        
        for log_file in log_files:
            if log_file in evidence_section:
                log_files_mentioned.append(log_file)
        
        log_file_count = len(log_files_mentioned)
        
        if log_file_count >= 2:
            scores['evidence_multi_source'] = 1.0
            feedback_parts.append(f"✅ Evidence references {log_file_count} log files: {', '.join(log_files_mentioned)}")
        elif log_file_count == 1:
            scores['evidence_multi_source'] = 0.5
            feedback_parts.append(f"⚠️ Evidence references only {log_files_mentioned[0]}, expected ≥2 sources")
        else:
            scores['evidence_multi_source'] = 0.0
            feedback_parts.append("❌ Evidence doesn't reference specific log files")
        
        # Criterion 6: Content is substantive (not just template)
        # Remove template placeholders and excessive whitespace
        substantial_content = re.sub(r'\[.*?\]', '', content)  # Remove [TODO], [Date], etc.
        substantial_content = re.sub(r'Example format:.*', '', substantial_content, flags=re.MULTILINE)
        substantial_content = re.sub(r'\s+', ' ', substantial_content).strip()
        
        content_length = len(substantial_content)
        
        if content_length >= 400:
            scores['content_substantive'] = 1.0
            feedback_parts.append(f"✅ Report is substantive ({content_length} characters)")
        elif content_length >= 200:
            scores['content_substantive'] = content_length / 400.0
            feedback_parts.append(f"⚠️ Report seems brief ({content_length} characters, expected ≥400)")
        else:
            scores['content_substantive'] = 0.0
            feedback_parts.append(f"❌ Report is too thin ({content_length} characters)")
        
        # Calculate weighted final score
        score_weights = {
            'file_exists': 0.10,
            'has_root_cause_section': 0.10,
            'has_timeline_section': 0.10,
            'has_evidence_section': 0.10,
            'correct_root_cause': 0.30,
            'timeline_detailed': 0.15,
            'evidence_multi_source': 0.10,
            'content_substantive': 0.05
        }
        
        weighted_score = sum(
            scores.get(key, 0.0) * weight 
            for key, weight in score_weights.items()
        )
        
        # Success requires weighted score ≥ 0.80 and connection pool must be mentioned
        final_score = int(weighted_score * 100)
        passed = weighted_score >= 0.80 and connection_pool_mentioned
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": final_score,
            "feedback": feedback,
            "details": {
                "weighted_score": round(weighted_score, 2),
                "individual_scores": scores,
                "timestamp_count": timestamp_count,
                "log_files_referenced": log_file_count,
                "content_length": content_length
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
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
