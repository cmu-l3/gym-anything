#!/usr/bin/env python3
"""
Verifier for Fix Encoding Issue task
Checks that the file was properly converted to UTF-8 and French characters are preserved
"""

import sys
import os
import logging
import tempfile
import shutil

# Try to import chardet, install if not available
try:
    import chardet
except ImportError:
    print("Installing chardet library...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "chardet", "--quiet"])
    import chardet

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_encoding_fixed(traj, env_info, task_info):
    """
    Verify that the encoding issue was fixed:
    1. File is now in UTF-8 encoding
    2. French accented characters are correctly preserved
    3. No garbled character patterns remain
    4. File content is readable and contains expected strings
    
    Args:
        traj: Trajectory (unused)
        env_info: Environment info with copy_from_env function
        task_info: Task info (unused)
        
    Returns:
        dict with 'passed', 'score', and 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='encoding_verify_')
    
    try:
        # Copy the final file from /tmp
        final_file_path = os.path.join(temp_dir, "analyze_data_final.py")
        
        try:
            copy_from_env("/tmp/analyze_data_final.py", final_file_path)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Failed to copy file from container: {str(e)}"
            }
        
        # Check if file exists and has content
        if not os.path.exists(final_file_path) or os.path.getsize(final_file_path) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ File analyze_data.py not found or empty in workspace"
            }
        
        feedback_parts = []
        criteria_passed = 0
        total_criteria = 4
        
        # Criterion 1: Detect actual encoding
        with open(final_file_path, 'rb') as f:
            raw_data = f.read()
            detected = chardet.detect(raw_data)
            detected_encoding = detected['encoding'].lower() if detected['encoding'] else 'unknown'
            confidence = detected.get('confidence', 0)
        
        logger.info(f"Detected encoding: {detected_encoding} (confidence: {confidence:.2f})")
        
        # Check if it's UTF-8 (or ASCII which is UTF-8 compatible)
        is_utf8 = detected_encoding in ['utf-8', 'ascii', 'utf-8-sig']
        
        if is_utf8 and confidence > 0.7:
            feedback_parts.append("✅ File is now in UTF-8 encoding")
            criteria_passed += 1
        else:
            feedback_parts.append(f"❌ File encoding is {detected_encoding} (confidence: {confidence:.2f}), expected UTF-8")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # Criterion 2: Read content and verify it's valid UTF-8
        try:
            with open(final_file_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except UnicodeDecodeError as e:
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts) + f" | ❌ Cannot read file as UTF-8: {str(e)}"
            }
        
        # Criterion 3: Verify French characters are present and correct
        required_french_terms = [
            "données",      # data
            "été",          # summer
            "météo",        # weather
            "Créé",         # created
            "français",     # French
            "températures", # temperatures
            "résumé",       # summary
            "succès",       # success
            "Montréal",     # city with accent
            "Genève"        # city with accent
        ]
        
        found_terms = [term for term in required_french_terms if term in content]
        missing_terms = [term for term in required_french_terms if term not in content]
        
        found_ratio = len(found_terms) / len(required_french_terms)
        
        if found_ratio >= 0.8:  # At least 80% of terms found
            feedback_parts.append(f"✅ French accented characters preserved ({len(found_terms)}/{len(required_french_terms)} key terms)")
            criteria_passed += 1
        else:
            missing_str = ', '.join(missing_terms[:3])
            feedback_parts.append(f"❌ French characters missing or incorrect ({len(found_terms)}/{len(required_french_terms)} found). Missing: {missing_str}")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # Criterion 4: Verify no garbled characters remain
        garbled_patterns = [
            'Ã©', 'Ã¨', 'Ã ', 'Ã´', 'Ã§', 'Ã«', 'â€™', 'Ã‰',
            'Ã®', 'Ã¢', 'Ãª', 'Ã¹', 'Ã»', 'Ã§'
        ]
        
        garbled_found = [pattern for pattern in garbled_patterns if pattern in content]
        
        if garbled_found:
            feedback_parts.append(f"❌ File still contains garbled characters: {', '.join(garbled_found[:3])}")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        else:
            feedback_parts.append("✅ No garbled character patterns found")
            criteria_passed += 1
        
        # Criterion 5: Verify file structure is intact
        expected_functions = ["def analyser_données", "def afficher_résumé"]
        structure_intact = all(func in content for func in expected_functions)
        
        if structure_intact:
            feedback_parts.append("✅ File structure and code integrity maintained")
            criteria_passed += 1
        else:
            feedback_parts.append("❌ File structure may be corrupted (functions missing)")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # All criteria passed
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
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
