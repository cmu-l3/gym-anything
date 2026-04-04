#!/usr/bin/env python3
"""
Verifier for Configure Custom File Associations task
"""

import sys
import os
import json
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import parse_vscode_settings

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_file_associations(traj, env_info, task_info):
    """
    Verify that file associations have been correctly configured in VSCode settings.
    
    Checks:
    1. settings.json exists and is valid JSON
    2. "files.associations" key exists
    3. All three required associations are present with correct language modes:
       - *.svcconfig → yaml
       - *.route → jsonc (or json)
       - *.tpl.html → html
    
    Returns:
        dict with keys: passed (bool), score (int 0-100), feedback (str)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available in environment"
        }
    
    SETTINGS_PATH = "/home/ga/.config/Code/User/settings.json"
    
    # Required file associations
    REQUIRED_ASSOCIATIONS = {
        "*.svcconfig": ["yaml"],
        "*.route": ["jsonc", "json"],  # Either jsonc or json is acceptable
        "*.tpl.html": ["html"]
    }
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
    temp_path = temp_file.name
    temp_file.close()
    
    try:
        # Copy settings.json from container
        try:
            copy_from_env(SETTINGS_PATH, temp_path)
        except Exception as e:
            logger.error(f"Failed to copy settings.json: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Could not access settings.json. Make sure you've configured file associations in VSCode settings. Error: {str(e)}"
            }
        
        # Check file exists and is not empty
        if not os.path.exists(temp_path):
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ settings.json not found. Please open VSCode Settings and add file associations."
            }
        
        if os.path.getsize(temp_path) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ settings.json is empty. Please configure file associations."
            }
        
        # Parse JSON
        try:
            with open(temp_path, 'r', encoding='utf-8') as f:
                settings = json.load(f)
        except json.JSONDecodeError as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ settings.json is not valid JSON: {str(e)}"
            }
        
        # Check if files.associations exists
        if "files.associations" not in settings:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ No 'files.associations' key found in settings.json. Open Settings (Ctrl+,), search for 'file associations', and add the required mappings."
            }
        
        file_associations = settings["files.associations"]
        
        if not isinstance(file_associations, dict):
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ 'files.associations' should be an object/dictionary, but got {type(file_associations).__name__}"
            }
        
        # Verify each required association
        missing = []
        incorrect = []
        correct_count = 0
        correct_details = []
        
        for pattern, acceptable_langs in REQUIRED_ASSOCIATIONS.items():
            if pattern not in file_associations:
                missing.append(pattern)
                logger.info(f"Missing pattern: {pattern}")
            else:
                actual_lang = file_associations[pattern].lower() if isinstance(file_associations[pattern], str) else str(file_associations[pattern])
                
                # Check if actual language is in acceptable list
                if actual_lang in [lang.lower() for lang in acceptable_langs]:
                    correct_count += 1
                    correct_details.append(f"  ✓ {pattern} → {file_associations[pattern]}")
                    logger.info(f"Correct: {pattern} → {actual_lang}")
                else:
                    incorrect.append({
                        "pattern": pattern,
                        "expected": acceptable_langs,
                        "actual": file_associations[pattern]
                    })
                    logger.info(f"Incorrect: {pattern} → {actual_lang} (expected one of {acceptable_langs})")
        
        # Calculate score
        total_required = len(REQUIRED_ASSOCIATIONS)
        score = int((correct_count / total_required) * 100)
        passed = (correct_count == total_required)
        
        # Build feedback message
        feedback_parts = []
        
        if passed:
            feedback_parts.append(f"✅ Perfect! All {total_required} file associations correctly configured:")
            feedback_parts.extend(correct_details)
            feedback_parts.append("\nThese custom file types will now have proper syntax highlighting automatically!")
        else:
            if correct_count > 0:
                feedback_parts.append(f"⚠️ Partial success: {correct_count}/{total_required} associations correct")
                feedback_parts.extend(correct_details)
            else:
                feedback_parts.append(f"❌ No correct associations found (0/{total_required})")
            
            if missing:
                feedback_parts.append(f"\n❌ Missing associations:")
                for pattern in missing:
                    expected = REQUIRED_ASSOCIATIONS[pattern]
                    expected_str = expected[0] if len(expected) == 1 else f"one of {expected}"
                    feedback_parts.append(f"  • {pattern} should map to {expected_str}")
            
            if incorrect:
                feedback_parts.append(f"\n❌ Incorrect associations:")
                for item in incorrect:
                    expected_str = item['expected'][0] if len(item['expected']) == 1 else f"one of {item['expected']}"
                    feedback_parts.append(f"  • {item['pattern']}: has '{item['actual']}' but should be {expected_str}")
            
            feedback_parts.append("\n💡 Hint: Open Settings (Ctrl+,), search for 'file associations', and add/correct the patterns above.")
        
        feedback = "\n".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "metadata": {
                "correct_count": correct_count,
                "total_required": total_required,
                "missing": missing,
                "incorrect": incorrect,
                "current_associations": file_associations
            }
        }
        
    except Exception as e:
        logger.exception("Unexpected error during verification")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification failed with unexpected error: {str(e)}"
        }
    
    finally:
        # Clean up temp file
        if os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass
