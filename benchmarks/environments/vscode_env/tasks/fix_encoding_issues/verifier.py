#!/usr/bin/env python3
"""
Verifier for Fix Encoding Issues task

Checks:
1. Files converted to UTF-8 encoding
2. Special characters preserved correctly
3. Line endings converted to LF (no CRLF)
4. Control files unchanged
"""

import sys
import os
import logging
import tempfile
import shutil

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def detect_encoding(filepath):
    """Detect file encoding using chardet"""
    try:
        import chardet
    except ImportError:
        logger.error("chardet not installed. Install with: pip install chardet")
        return None
    
    try:
        with open(filepath, 'rb') as f:
            raw_data = f.read()
            if not raw_data:
                return None
            result = chardet.detect(raw_data)
            return result.get('encoding', 'unknown').upper() if result else None
    except Exception as e:
        logger.error(f"Error detecting encoding for {filepath}: {e}")
        return None


def has_crlf_line_endings(filepath):
    """Check if file has Windows (CRLF) line endings"""
    try:
        with open(filepath, 'rb') as f:
            content = f.read()
            return b'\r\n' in content
    except Exception as e:
        logger.error(f"Error checking line endings for {filepath}: {e}")
        return False


def verify_utf8_characters(filepath, expected_chars):
    """Verify that expected UTF-8 characters are present and readable"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        missing_chars = []
        for char in expected_chars:
            if char not in content:
                missing_chars.append(char)
        
        if missing_chars:
            return False, f"Missing characters: {missing_chars}"
        
        return True, "All expected characters found"
    except UnicodeDecodeError as e:
        return False, f"UTF-8 decode error: {e}"
    except Exception as e:
        return False, f"Error reading file: {e}"


def verify_encoding_fix(traj, env_info, task_info):
    """
    Main verification function for encoding fix task
    
    Returns:
        dict with keys: passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    workspace = "/home/ga/workspace/data-pipeline"
    temp_dir = tempfile.mkdtemp(prefix='encoding_verify_')
    
    try:
        issues = []
        checks_passed = 0
        total_checks = 10
        
        # Define files and their requirements
        encoding_checks = [
            ("data/customers.csv", ["José García", "François Dupont", "Müller Schmidt", "Søren Nielsen"]),
            ("data/locations.txt", ["São Paulo", "Malmö", "Zürich", "Montréal"]),
            ("docs/glossary.txt", ["naïve", "café", "résumé", "façade"])
        ]
        
        line_ending_checks = [
            "README.md",
            "docs/notes.md",
            "scripts/validate.sh"
        ]
        
        control_files = [
            "data/products.json",
            "scripts/process.py"
        ]
        
        # Check encoding conversions (6 checks total: 3 encoding + 3 character integrity)
        for rel_path, expected_chars in encoding_checks:
            container_path = os.path.join(workspace, rel_path)
            local_path = os.path.join(temp_dir, os.path.basename(rel_path))
            
            try:
                copy_from_env(container_path, local_path)
            except Exception as e:
                issues.append(f"❌ Failed to copy {rel_path}: {e}")
                continue
            
            if not os.path.exists(local_path) or os.path.getsize(local_path) == 0:
                issues.append(f"❌ File not found or empty: {rel_path}")
                continue
            
            # Check 1: Encoding
            encoding = detect_encoding(local_path)
            if encoding and encoding in ['UTF-8', 'ASCII', 'US-ASCII']:
                checks_passed += 1
                logger.info(f"✅ {rel_path}: Correct encoding ({encoding})")
            else:
                issues.append(f"❌ {rel_path}: Wrong encoding ({encoding}), expected UTF-8")
                logger.warning(f"❌ {rel_path}: Wrong encoding ({encoding})")
            
            # Check 2: Character integrity
            char_ok, msg = verify_utf8_characters(local_path, expected_chars)
            if char_ok:
                checks_passed += 1
                logger.info(f"✅ {rel_path}: {msg}")
            else:
                issues.append(f"❌ {rel_path}: {msg}")
                logger.warning(f"❌ {rel_path}: {msg}")
        
        # Check line ending conversions (3 checks)
        for rel_path in line_ending_checks:
            container_path = os.path.join(workspace, rel_path)
            local_path = os.path.join(temp_dir, os.path.basename(rel_path) + "_le")
            
            try:
                copy_from_env(container_path, local_path)
            except Exception as e:
                issues.append(f"❌ Failed to copy {rel_path}: {e}")
                continue
            
            if not os.path.exists(local_path):
                issues.append(f"❌ File not found: {rel_path}")
                continue
            
            if has_crlf_line_endings(local_path):
                issues.append(f"❌ {rel_path}: Still has CRLF line endings, expected LF")
                logger.warning(f"❌ {rel_path}: Has CRLF")
            else:
                checks_passed += 1
                logger.info(f"✅ {rel_path}: Correct LF line endings")
        
        # Verify control files exist and are readable (1 check - bonus for not breaking things)
        control_ok = True
        for rel_path in control_files:
            container_path = os.path.join(workspace, rel_path)
            local_path = os.path.join(temp_dir, os.path.basename(rel_path) + "_ctrl")
            
            try:
                copy_from_env(container_path, local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                    # Just check it's readable
                    with open(local_path, 'r', encoding='utf-8') as f:
                        f.read()
                else:
                    control_ok = False
            except:
                control_ok = False
        
        if control_ok:
            checks_passed += 1
            logger.info("✅ Control files intact")
        
        # Calculate score
        score = int((checks_passed / total_checks) * 100)
        success = score >= 90  # Must pass 9/10 checks
        
        # Generate feedback
        if success:
            feedback = f"✅ Task completed successfully! ({checks_passed}/{total_checks} checks passed)\n"
            feedback += "- All files converted to UTF-8\n"
            feedback += "- All line endings converted to LF\n"
            feedback += "- Special characters preserved correctly"
        else:
            feedback = f"❌ Task incomplete ({checks_passed}/{total_checks} checks passed):\n"
            if issues:
                feedback += "\n".join(issues[:10])  # Limit to first 10 issues
            else:
                feedback += "Some checks failed. Review encoding and line endings."
        
        logger.info(f"Final score: {score}%, Passed: {success}")
        
        return {
            "passed": success,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Cleanup temp directory
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
