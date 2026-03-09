#!/usr/bin/env python3
"""
Verifier for Organize Service Terminals task

Verifies that agent created 3 organized terminal tabs with meaningful names.
"""

import sys
import os
import logging
import tempfile
import shutil
import re
from typing import Dict, Any, List, Tuple

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_terminal_names_from_ocr(ocr_text: str) -> List[str]:
    """
    Extract terminal names from OCR text.
    
    Terminal tabs typically appear as text separated by spaces or special chars.
    We look for patterns that indicate terminal names.
    """
    if not ocr_text:
        return []
    
    # Clean OCR text
    text = ocr_text.strip()
    lines = [line.strip() for line in text.split('\n') if line.strip()]
    
    terminal_names = []
    
    # Common service-related keywords that indicate meaningful names
    service_keywords = [
        'backend', 'frontend', 'worker', 'api', 'server', 
        'celery', 'dev', 'service', 'app', 'web'
    ]
    
    # Scan each line for potential terminal names
    for line in lines:
        # Look for words that match service patterns
        words = re.findall(r'\b[A-Za-z][A-Za-z0-9\s_-]{2,30}\b', line)
        
        for word in words:
            word_lower = word.lower()
            # Check if word contains service keywords
            if any(keyword in word_lower for keyword in service_keywords):
                # Filter out common non-terminal text
                if word_lower not in ['visual', 'studio', 'code', 'terminal', 'output', 
                                       'problems', 'debug', 'console', 'extensions']:
                    terminal_names.append(word.strip())
    
    # Also try to find common patterns like "Backend API", "Frontend Dev"
    # Look for capitalized multi-word phrases
    multi_word_patterns = re.findall(r'\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)+\b', text)
    for pattern in multi_word_patterns:
        if any(keyword in pattern.lower() for keyword in service_keywords):
            terminal_names.append(pattern.strip())
    
    # Remove duplicates while preserving order
    seen = set()
    unique_names = []
    for name in terminal_names:
        name_lower = name.lower()
        if name_lower not in seen:
            seen.add(name_lower)
            unique_names.append(name)
    
    return unique_names


def count_terminal_tabs_in_image(ocr_text: str, image_path: str = None) -> int:
    """
    Estimate number of terminal tabs based on OCR text and patterns.
    
    This is imperfect but we look for:
    - Multiple distinct service-related names
    - Repeated patterns that indicate tabs
    """
    terminal_names = extract_terminal_names_from_ocr(ocr_text)
    
    # If we found distinct terminal names, that's our count
    if len(terminal_names) >= 2:
        return len(terminal_names)
    
    # Fallback: look for bash/zsh mentions (each terminal runs a shell)
    bash_count = ocr_text.lower().count('bash')
    zsh_count = ocr_text.lower().count('zsh')
    shell_count = max(bash_count, zsh_count)
    
    if shell_count >= 2:
        return shell_count
    
    # If OCR failed to find clear evidence, assume 0
    return 0


def is_default_terminal_name(name: str) -> bool:
    """Check if name is a default terminal name (bash, zsh, etc)."""
    default_names = ['bash', 'zsh', 'sh', 'shell', 'terminal', 'terminal 1', 
                     'terminal 2', 'terminal 3', '1', '2', '3']
    return name.lower().strip() in default_names


def is_meaningful_terminal_name(name: str) -> bool:
    """Check if terminal name is semantically meaningful (relates to services)."""
    service_keywords = [
        'backend', 'frontend', 'worker', 'api', 'server', 
        'celery', 'dev', 'service', 'app', 'web', 'react',
        'fastapi', 'uvicorn', 'npm', 'node'
    ]
    name_lower = name.lower()
    return any(keyword in name_lower for keyword in service_keywords)


def verify_terminal_organization(traj, env_info, task_info):
    """
    Verify that 3 organized terminal tabs were created with meaningful names.
    
    Verification criteria:
    1. Exactly 3 terminals exist (or 2-4 acceptable range)
    2. Terminals have custom names (not default "bash"/"zsh")
    3. Names are semantically meaningful (relate to services)
    4. Terminal panel is visible
    5. Organization quality (terminals are separate tabs)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_terminal_verify_')
    
    try:
        # Copy screenshot and OCR results
        screenshot_path = os.path.join(temp_dir, "screenshot.png")
        terminal_region_path = os.path.join(temp_dir, "terminal_region.png")
        ocr_result_path = os.path.join(temp_dir, "ocr_result.txt")
        
        # Try to copy files
        screenshot_exists = False
        try:
            copy_from_env("/tmp/vscode_terminal_screenshot.png", screenshot_path)
            screenshot_exists = os.path.exists(screenshot_path) and os.path.getsize(screenshot_path) > 1000
        except Exception as e:
            logger.warning(f"Failed to copy main screenshot: {e}")
        
        terminal_region_exists = False
        try:
            copy_from_env("/tmp/vscode_terminal_region.png", terminal_region_path)
            terminal_region_exists = os.path.exists(terminal_region_path) and os.path.getsize(terminal_region_path) > 1000
        except Exception as e:
            logger.warning(f"Failed to copy terminal region: {e}")
        
        # Try to copy pre-computed OCR result
        ocr_text = ""
        try:
            copy_from_env("/tmp/terminal_ocr_result.txt", ocr_result_path)
            if os.path.exists(ocr_result_path):
                with open(ocr_result_path, 'r', encoding='utf-8', errors='ignore') as f:
                    ocr_text = f.read()
        except Exception as e:
            logger.warning(f"No pre-computed OCR result: {e}")
        
        # If no pre-computed OCR, run it now
        if not ocr_text and (screenshot_exists or terminal_region_exists):
            import subprocess
            
            # Prefer terminal region for OCR (more focused)
            ocr_image = terminal_region_path if terminal_region_exists else screenshot_path
            
            try:
                # Run tesseract OCR
                result = subprocess.run(
                    ['tesseract', ocr_image, 'stdout'],
                    capture_output=True,
                    text=True,
                    timeout=10
                )
                ocr_text = result.stdout
                logger.info(f"OCR extracted {len(ocr_text)} characters")
            except Exception as e:
                logger.error(f"OCR failed: {e}")
                ocr_text = ""
        
        # Initialize criteria tracking
        criteria_passed = 0
        feedback_parts = []
        
        # If we have no screenshot or OCR, fail immediately
        if not screenshot_exists and not terminal_region_exists:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ No screenshot captured - unable to verify terminal organization"
            }
        
        if not ocr_text or len(ocr_text) < 10:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ OCR failed to extract text from screenshot - unable to verify terminals"
            }
        
        # Log OCR text for debugging
        logger.info(f"OCR text preview: {ocr_text[:500]}")
        
        # Criterion 1: Count terminals (should be around 3)
        terminal_count = count_terminal_tabs_in_image(ocr_text)
        logger.info(f"Detected {terminal_count} terminals")
        
        if terminal_count == 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Exactly 3 terminals detected")
        elif 2 <= terminal_count <= 4:
            criteria_passed += 0.5  # Partial credit
            feedback_parts.append(f"⚠️ Found {terminal_count} terminals (expected 3)")
        else:
            feedback_parts.append(f"❌ Expected 3 terminals, found {terminal_count}")
        
        # Criterion 2 & 3: Extract terminal names and check quality
        terminal_names = extract_terminal_names_from_ocr(ocr_text)
        logger.info(f"Extracted terminal names: {terminal_names}")
        
        if len(terminal_names) == 0:
            # Try alternative detection: look for any service keywords
            service_keywords = ['backend', 'frontend', 'worker', 'api', 'dev', 'celery']
            found_keywords = [kw for kw in service_keywords if kw in ocr_text.lower()]
            
            if len(found_keywords) >= 2:
                criteria_passed += 0.5
                feedback_parts.append(f"⚠️ Found service keywords ({', '.join(found_keywords)}) but couldn't extract exact terminal names")
            else:
                feedback_parts.append("❌ No custom terminal names detected (may still be default 'bash'/'zsh')")
        else:
            # Check if names are not defaults
            non_default_names = [n for n in terminal_names if not is_default_terminal_name(n)]
            
            if len(non_default_names) >= 2:
                criteria_passed += 1
                feedback_parts.append(f"✅ Terminals have custom names: {', '.join(non_default_names[:3])}")
            else:
                feedback_parts.append(f"❌ Terminal names appear to be defaults: {', '.join(terminal_names[:3])}")
            
            # Check if names are meaningful
            meaningful_names = [n for n in terminal_names if is_meaningful_terminal_name(n)]
            
            if len(meaningful_names) >= 2:
                criteria_passed += 1
                feedback_parts.append(f"✅ Terminal names are meaningful: {', '.join(meaningful_names[:3])}")
            else:
                feedback_parts.append(f"❌ Terminal names don't relate to services")
        
        # Criterion 4: Terminal panel visible
        # Check if OCR text contains evidence of terminal panel
        terminal_indicators = ['bash', 'zsh', 'terminal', '$', '~', '/home/ga']
        has_terminal_indicators = any(indicator in ocr_text.lower() for indicator in terminal_indicators)
        
        if has_terminal_indicators:
            criteria_passed += 1
            feedback_parts.append("✅ Terminal panel appears to be visible")
        else:
            feedback_parts.append("❌ Terminal panel may not be visible")
        
        # Criterion 5: Organization quality (harder to verify, give partial credit if other criteria pass)
        if criteria_passed >= 3:
            criteria_passed += 0.5
            feedback_parts.append("✅ Terminals appear to be organized")
        
        # Calculate final score
        # Max possible: 5 criteria
        max_criteria = 5
        score = int((criteria_passed / max_criteria) * 100)
        passed = score >= 75
        
        # Adjust feedback for edge cases
        if not passed and terminal_count >= 2 and len(terminal_names) >= 2:
            feedback_parts.append("💡 Hint: Terminals detected but verification strict. Ensure exactly 3 terminals with clear service-related names.")
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification result: score={score}, passed={passed}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "terminal_count": terminal_count,
                "terminal_names": terminal_names,
                "criteria_passed": criteria_passed,
                "max_criteria": max_criteria
            }
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        # Cleanup temp directory
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
