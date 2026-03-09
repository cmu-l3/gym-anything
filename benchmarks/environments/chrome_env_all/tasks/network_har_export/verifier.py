#!/usr/bin/env python3
"""
Verifier for Chrome Network HAR Export Task (network_har_export@1)
Task: Use DevTools Network panel to capture traffic and export as HAR file

Verification Strategy:
1. Check HAR file exists in Downloads folder
2. Validate JSON structure conforms to HAR 1.2 specification
3. Verify sufficient network entries captured (minimum 3)
4. Check entries contain complete request/response data
5. Verify target demo site traffic is present
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional
from urllib.parse import urlparse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available")
    def cleanup_verification_temp():
        pass


def find_har_file(copy_from_env, expected_name="network_export.har") -> Tuple[bool, str, str, str]:
    """
    Find and copy the generated HAR file from the container.
    
    Args:
        copy_from_env: Function to copy files from container
        expected_name: Expected filename for the HAR export
        
    Returns:
        Tuple of (success, local_path, filename, error_message)
    """
    try:
        # First, try to get the filename that was found
        temp_filename = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/har_filename.txt", temp_filename.name)
            with open(temp_filename.name, 'r') as f:
                found_name = f.read().strip()
            os.unlink(temp_filename.name)
            
            if found_name == "none":
                return False, "", "", "No HAR file was found in Downloads folder"
        except Exception as e:
            logger.warning(f"Could not read har_filename.txt: {e}")
            found_name = expected_name
        
        # Try to copy the HAR file from verification directory
        temp_har = tempfile.NamedTemporaryFile(delete=False, suffix='.har')
        temp_har.close()
        
        # Try multiple possible locations
        possible_paths = [
            f"/tmp/har_export_verification/{found_name}",
            f"/tmp/{found_name}",
            f"/home/ga/Downloads/{found_name}",
            f"/home/ga/Downloads/{expected_name}",
        ]
        
        # Also try common Chrome HAR export naming patterns
        possible_paths.extend([
            "/home/ga/Downloads/localhost.har",
            "/home/ga/Downloads/www.har",
        ])
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_har.name)
                
                # Check if file has content
                if Path(temp_har.name).stat().st_size > 0:
                    logger.info(f"✓ Successfully copied HAR from: {container_path}")
                    return True, temp_har.name, found_name, ""
            except Exception as e:
                logger.debug(f"Could not copy from {container_path}: {e}")
                continue
        
        # If we get here, none of the paths worked
        os.unlink(temp_har.name)
        return False, "", "", "HAR file could not be copied from container"
        
    except Exception as e:
        logger.error(f"Error finding HAR file: {e}", exc_info=True)
        return False, "", "", f"Error finding HAR file: {str(e)}"


def validate_har_structure(har_path: str) -> Tuple[bool, int, str]:
    """
    Validate HAR file structure and return entry count.
    
    Args:
        har_path: Path to HAR file
        
    Returns:
        Tuple of (is_valid, entry_count, feedback)
    """
    try:
        with open(har_path, 'r', encoding='utf-8') as f:
            har_data = json.load(f)
        
        # Check root structure
        if 'log' not in har_data:
            return False, 0, "Missing 'log' root object in HAR structure"
        
        log = har_data['log']
        
        # Check required HAR 1.2 fields
        required_fields = ['version', 'creator', 'entries']
        missing_fields = [field for field in required_fields if field not in log]
        
        if missing_fields:
            return False, 0, f"Missing required HAR fields: {', '.join(missing_fields)}"
        
        # Check entries is a list
        entries = log.get('entries', [])
        if not isinstance(entries, list):
            return False, 0, "'entries' field is not a list"
        
        entry_count = len(entries)
        
        if entry_count == 0:
            return False, 0, "No network entries captured in HAR file"
        
        logger.info(f"HAR structure valid with {entry_count} entries")
        return True, entry_count, f"Valid HAR structure with {entry_count} entries"
        
    except json.JSONDecodeError as e:
        return False, 0, f"Invalid JSON format: {str(e)}"
    except Exception as e:
        return False, 0, f"Error validating HAR structure: {str(e)}"


def validate_entry_completeness(har_path: str) -> Tuple[bool, int, str]:
    """
    Validate that HAR entries contain complete request/response data.
    
    Args:
        har_path: Path to HAR file
        
    Returns:
        Tuple of (is_valid, valid_entry_count, feedback)
    """
    try:
        with open(har_path, 'r', encoding='utf-8') as f:
            har_data = json.load(f)
        
        entries = har_data.get('log', {}).get('entries', [])
        valid_entries = 0
        
        for entry in entries:
            # Check required entry fields
            has_request = 'request' in entry
            has_response = 'response' in entry
            has_time = 'time' in entry
            
            if not (has_request and has_response and has_time):
                continue
            
            request = entry['request']
            response = entry['response']
            
            # Validate request has method and URL
            has_method = 'method' in request
            has_url = 'url' in request
            
            # Validate response has status
            has_status = 'status' in response
            has_content = 'content' in response
            
            if has_method and has_url and has_status and has_content:
                valid_entries += 1
        
        if valid_entries < 3:
            return False, valid_entries, f"Insufficient valid entries: only {valid_entries}/3 minimum"
        
        logger.info(f"Entry completeness: {valid_entries} valid entries")
        return True, valid_entries, f"{valid_entries} entries with complete data"
        
    except Exception as e:
        return False, 0, f"Error validating entry completeness: {str(e)}"


def check_target_domain_presence(har_path: str, target_domain="localhost:8080") -> Tuple[bool, List[str], str]:
    """
    Check if HAR contains requests to the target demo site.
    
    Args:
        har_path: Path to HAR file
        target_domain: Expected domain in captured traffic
        
    Returns:
        Tuple of (is_present, matched_urls, feedback)
    """
    try:
        with open(har_path, 'r', encoding='utf-8') as f:
            har_data = json.load(f)
        
        entries = har_data.get('log', {}).get('entries', [])
        target_urls = []
        
        for entry in entries:
            url = entry.get('request', {}).get('url', '')
            if target_domain in url:
                target_urls.append(url)
        
        if not target_urls:
            return False, [], f"No requests to target domain '{target_domain}' found"
        
        logger.info(f"Target domain presence: found {len(target_urls)} requests to {target_domain}")
        return True, target_urls, f"Found {len(target_urls)} requests to demo site"
        
    except Exception as e:
        return False, [], f"Error checking target domain: {str(e)}"


def analyze_resource_diversity(har_path: str) -> Tuple[bool, Dict[str, int], str]:
    """
    Analyze diversity of resource types captured in HAR.
    
    Args:
        har_path: Path to HAR file
        
    Returns:
        Tuple of (has_diversity, resource_counts, feedback)
    """
    try:
        with open(har_path, 'r', encoding='utf-8') as f:
            har_data = json.load(f)
        
        entries = har_data.get('log', {}).get('entries', [])
        resource_types = {
            'html': 0,
            'css': 0,
            'javascript': 0,
            'image': 0,
            'json': 0,
            'other': 0
        }
        
        for entry in entries:
            mime_type = entry.get('response', {}).get('content', {}).get('mimeType', '').lower()
            url = entry.get('request', {}).get('url', '').lower()
            
            if 'html' in mime_type or url.endswith('.html'):
                resource_types['html'] += 1
            elif 'css' in mime_type or url.endswith('.css'):
                resource_types['css'] += 1
            elif 'javascript' in mime_type or 'script' in mime_type or url.endswith('.js'):
                resource_types['javascript'] += 1
            elif 'image' in mime_type or any(url.endswith(ext) for ext in ['.png', '.jpg', '.jpeg', '.gif']):
                resource_types['image'] += 1
            elif 'json' in mime_type or url.endswith('.json'):
                resource_types['json'] += 1
            else:
                resource_types['other'] += 1
        
        # Check if we have diversity (at least 3 different resource types)
        types_present = sum(1 for count in resource_types.values() if count > 0)
        has_diversity = types_present >= 3
        
        feedback = f"Resource diversity: {types_present} different types captured"
        logger.info(f"Resource diversity: {resource_types}")
        
        return has_diversity, resource_types, feedback
        
    except Exception as e:
        return False, {}, f"Error analyzing resource diversity: {str(e)}"


def check_response_content_preservation(har_path: str) -> Tuple[bool, float, str]:
    """
    Check if HAR was saved with content (response bodies included).
    
    Args:
        har_path: Path to HAR file
        
    Returns:
        Tuple of (has_content, preservation_rate, feedback)
    """
    try:
        with open(har_path, 'r', encoding='utf-8') as f:
            har_data = json.load(f)
        
        entries = har_data.get('log', {}).get('entries', [])
        entries_with_content = 0
        
        for entry in entries:
            content = entry.get('response', {}).get('content', {})
            has_text = bool(content.get('text', ''))
            has_size = content.get('size', 0) > 0
            
            if has_text or has_size:
                entries_with_content += 1
        
        if len(entries) == 0:
            return False, 0.0, "No entries to check for content"
        
        preservation_rate = entries_with_content / len(entries)
        has_content = preservation_rate >= 0.5  # At least 50% should have content
        
        feedback = f"Content preservation: {preservation_rate*100:.1f}% of entries"
        logger.info(f"Content preservation rate: {preservation_rate:.2%}")
        
        return has_content, preservation_rate, feedback
        
    except Exception as e:
        return False, 0.0, f"Error checking content preservation: {str(e)}"


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for network_har_export@1 task.
    
    Verifies:
    1. HAR file exists in Downloads folder
    2. Valid JSON structure conforming to HAR 1.2 spec
    3. Sufficient network entries (minimum 3)
    4. Complete request/response data in entries
    5. Target domain traffic captured
    
    Scoring:
    - 100%: All 5 criteria met
    - 80%: 4/5 criteria met (passing)
    - 60%: 3/5 criteria met (partial)
    - 40%: 2/5 criteria met
    - 0-20%: 0-1 criteria met
    
    Pass threshold: 75% (requires at least 4 out of 5 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    details = {}
    
    # Criterion 1: HAR file exists
    logger.info("Checking if HAR file exists...")
    success, har_path, har_name, error = find_har_file(copy_from_env)
    
    if not success:
        feedback = f"✗ HAR file not found\n{error}"
        feedback += "\n\nPlease ensure you:"
        feedback += "\n  1. Opened DevTools (F12 or Ctrl+Shift+I)"
        feedback += "\n  2. Clicked on 'Network' tab"
        feedback += "\n  3. Navigated to http://localhost:8080"
        feedback += "\n  4. Right-clicked in Network panel"
        feedback += "\n  5. Selected 'Save all as HAR with content'"
        feedback += "\n  6. Saved the file in Downloads folder"
        
        return {
            "passed": False,
            "score": 0,
            "feedback": feedback
        }
    
    feedback_parts.append(f"✓ HAR file found: {har_name}")
    criteria_met += 1
    details['har_filename'] = har_name
    
    # Criterion 2: Valid HAR structure
    logger.info("Validating HAR structure...")
    structure_valid, entry_count, structure_feedback = validate_har_structure(har_path)
    
    if structure_valid:
        feedback_parts.append(f"✓ {structure_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ {structure_feedback}")
    
    details['entry_count'] = entry_count
    
    # Criterion 3: Sufficient entries (only check if structure is valid)
    if structure_valid:
        logger.info("Checking entry count...")
        if entry_count >= 3:
            feedback_parts.append(f"✓ Sufficient entries captured ({entry_count} entries)")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ Insufficient entries ({entry_count}/3 minimum)")
    
    # Criterion 4: Complete entry data (only if we have entries)
    if structure_valid and entry_count > 0:
        logger.info("Validating entry completeness...")
        entries_valid, valid_count, entry_feedback = validate_entry_completeness(har_path)
        
        if entries_valid:
            feedback_parts.append(f"✓ {entry_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ {entry_feedback}")
        
        details['valid_entries'] = valid_count
    
    # Criterion 5: Target domain present
    if structure_valid and entry_count > 0:
        logger.info("Checking for target domain traffic...")
        domain_present, target_urls, domain_feedback = check_target_domain_presence(har_path)
        
        if domain_present:
            feedback_parts.append(f"✓ {domain_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ {domain_feedback}")
        
        details['target_urls_found'] = len(target_urls)
    
    # Additional analysis (informational, not scored)
    if structure_valid and entry_count > 0:
        has_diversity, resource_counts, diversity_feedback = analyze_resource_diversity(har_path)
        feedback_parts.append(f"ℹ {diversity_feedback}")
        details['resource_types'] = resource_counts
        
        has_content, preservation_rate, content_feedback = check_response_content_preservation(har_path)
        feedback_parts.append(f"ℹ {content_feedback}")
        details['content_preservation_rate'] = f"{preservation_rate*100:.1f}%"
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not passed:
        feedback += "\n\nTo pass this task, ensure DevTools Network panel captured traffic"
        feedback += "\nfrom the demo site and HAR was exported with 'Save all as HAR with content'."
    
    # Clean up temporary file
    try:
        if har_path and os.path.exists(har_path):
            os.unlink(har_path)
    except:
        pass
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }
