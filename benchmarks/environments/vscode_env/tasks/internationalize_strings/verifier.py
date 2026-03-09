#!/usr/bin/env python3
"""
Verifier for Internationalize Strings task
"""

import sys
import os
import logging
import tempfile
import json
import re
import ast
from pathlib import Path
from typing import Dict, Set, Tuple, List

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_string_literals(js_code: str) -> List[str]:
    """Extract string literals from JavaScript code (simple regex-based)"""
    # Match strings in single or double quotes
    pattern = r'''(?:["'])([^"'\\]*(?:\\.[^"'\\]*)*)(?:["'])'''
    matches = re.findall(pattern, js_code)
    return matches


def extract_i18n_keys_from_code(js_code: str) -> Set[str]:
    """Extract i18n keys from t() function calls"""
    # Match patterns like t('key.name') or t("key.name")
    patterns = [
        r'''t\(['"]([\w.]+)['"]\)''',  # t('key')
        r'''__\(['"]([\w.]+)['"]\)''',  # __('key')
        r'''i18n\.t\(['"]([\w.]+)['"]\)''',  # i18n.t('key')
    ]
    
    keys = set()
    for pattern in patterns:
        matches = re.findall(pattern, js_code)
        keys.update(matches)
    
    return keys


def has_i18n_import(js_code: str) -> bool:
    """Check if code has i18n import statement"""
    import_patterns = [
        r'''require\s*\(\s*['"]\.?\.?/i18n['"]\s*\)''',
        r'''from\s+['"]\.?\.?/i18n['"]''',
        r'''import.*from.*['"]\.?\.?/i18n['"]''',
        r'''const\s*{\s*t\s*}.*require.*i18n''',
    ]
    
    for pattern in import_patterns:
        if re.search(pattern, js_code):
            return True
    return False


def count_console_logs(js_code: str) -> int:
    """Count console.log statements"""
    return len(re.findall(r'console\.log', js_code))


def is_semantic_key(key: str) -> bool:
    """Check if key follows semantic naming conventions"""
    # Semantic keys typically have dots or underscores and aren't just numbers
    if key.isdigit():
        return False
    if len(key) < 3:
        return False
    # Good keys have structure like "error.message" or "button_submit"
    return '.' in key or '_' in key or any(c.isupper() for c in key)


def verify_internationalization(traj, env_info, task_info):
    """
    Verify that user-facing strings have been properly internationalized.
    
    Scoring breakdown (100 points total):
    - Translation file exists and valid: 20 points
    - Translation quality (entries, semantic keys): 15 points
    - Code modified (import, function calls): 25 points
    - Key consistency: 25 points
    - Selective extraction (debug preserved): 15 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    workspace_path = "/home/ga/workspace/i18n_task"
    temp_dir = tempfile.mkdtemp(prefix='i18n_verify_')

    try:
        score_breakdown = {
            'translation_file': 0,      # max 20
            'translation_quality': 0,   # max 15
            'code_modified': 0,         # max 25
            'key_consistency': 0,       # max 25
            'selective_extraction': 0,  # max 15
        }
        
        feedback_parts = []

        # === 1. Check for translation file ===
        translation_files = [
            f'{workspace_path}/i18n/en.json',
            f'{workspace_path}/locales/en.json',
            f'{workspace_path}/translations.json',
            f'{workspace_path}/i18n/translations.json'
        ]
        
        translation_data = None
        translation_path = None
        
        for tf_path in translation_files:
            local_tf = os.path.join(temp_dir, os.path.basename(tf_path))
            try:
                copy_from_env(tf_path, local_tf)
                if os.path.exists(local_tf) and os.path.getsize(local_tf) > 0:
                    with open(local_tf, 'r', encoding='utf-8') as f:
                        translation_data = json.load(f)
                    translation_path = tf_path
                    score_breakdown['translation_file'] = 20
                    feedback_parts.append(f"✅ Translation file found: {tf_path.replace(workspace_path + '/', '')}")
                    break
            except json.JSONDecodeError as e:
                feedback_parts.append(f"❌ Translation file found but invalid JSON: {e}")
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": " | ".join(feedback_parts)
                }
            except Exception:
                continue
        
        if not translation_data:
            feedback_parts.append("❌ No translation file found (expected: i18n/en.json)")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }

        # === 2. Validate translation quality ===
        num_translations = len(translation_data)
        
        if num_translations >= 6:
            score_breakdown['translation_quality'] += 10
            feedback_parts.append(f"✅ Translation file has {num_translations} entries")
        elif num_translations >= 4:
            score_breakdown['translation_quality'] += 7
            feedback_parts.append(f"△ Translation file has {num_translations} entries (expected 6+)")
        elif num_translations >= 2:
            score_breakdown['translation_quality'] += 4
            feedback_parts.append(f"△ Translation file has only {num_translations} entries")
        else:
            feedback_parts.append(f"❌ Translation file has insufficient entries: {num_translations}")
        
        # Check key quality (semantic naming)
        semantic_keys = [k for k in translation_data.keys() if is_semantic_key(k)]
        semantic_ratio = len(semantic_keys) / max(1, len(translation_data))
        
        if semantic_ratio >= 0.8:
            score_breakdown['translation_quality'] += 5
            feedback_parts.append("✅ Translation keys use semantic naming (e.g., 'error.message')")
        elif semantic_ratio >= 0.5:
            score_breakdown['translation_quality'] += 3
            feedback_parts.append("△ Some translation keys could be more semantic")
        else:
            feedback_parts.append("❌ Translation keys lack semantic structure (use 'error.message', not 'string1')")

        # === 3. Check source code modifications ===
        app_js_path = f'{workspace_path}/app.js'
        local_app_js = os.path.join(temp_dir, 'app.js')
        
        try:
            copy_from_env(app_js_path, local_app_js)
        except Exception as e:
            feedback_parts.append(f"❌ Failed to copy app.js: {e}")
            return {
                "passed": False,
                "score": sum(score_breakdown.values()),
                "feedback": " | ".join(feedback_parts)
            }
        
        if not os.path.exists(local_app_js):
            feedback_parts.append("❌ app.js not found")
            return {
                "passed": False,
                "score": sum(score_breakdown.values()),
                "feedback": " | ".join(feedback_parts)
            }
        
        with open(local_app_js, 'r', encoding='utf-8') as f:
            app_js_content = f.read()
        
        # Check for i18n import
        has_import = has_i18n_import(app_js_content)
        if has_import:
            score_breakdown['code_modified'] += 10
            feedback_parts.append("✅ i18n import added to app.js")
        else:
            feedback_parts.append("❌ No i18n import found in app.js (need: const { t } = require('./i18n');)")
        
        # Count i18n function calls
        i18n_keys_in_code = extract_i18n_keys_from_code(app_js_content)
        i18n_call_count = len(i18n_keys_in_code)
        
        if i18n_call_count >= 6:
            score_breakdown['code_modified'] += 15
            feedback_parts.append(f"✅ i18n function calls found: {i18n_call_count} (t('key') calls)")
        elif i18n_call_count >= 4:
            score_breakdown['code_modified'] += 12
            feedback_parts.append(f"△ Some i18n calls found: {i18n_call_count} (expected 6+)")
        elif i18n_call_count >= 2:
            score_breakdown['code_modified'] += 7
            feedback_parts.append(f"△ Few i18n calls found: {i18n_call_count}")
        else:
            feedback_parts.append(f"❌ Insufficient i18n function calls: {i18n_call_count}")

        # === 4. Check key consistency ===
        json_keys = set(translation_data.keys())
        
        if i18n_keys_in_code:
            missing_keys = i18n_keys_in_code - json_keys
            extra_keys = json_keys - i18n_keys_in_code
            
            if not missing_keys:
                score_breakdown['key_consistency'] = 25
                feedback_parts.append("✅ Perfect key consistency - all code keys exist in translation file")
            elif len(missing_keys) <= 1:
                score_breakdown['key_consistency'] = 20
                feedback_parts.append(f"△ Minor inconsistency: missing keys {missing_keys}")
            elif len(missing_keys) <= 2:
                score_breakdown['key_consistency'] = 15
                feedback_parts.append(f"△ Some missing keys: {missing_keys}")
            else:
                score_breakdown['key_consistency'] = 5
                feedback_parts.append(f"❌ Many missing keys in translation file: {missing_keys}")
            
            # Extra keys are okay (for future use) but note if excessive
            if len(extra_keys) > len(i18n_keys_in_code):
                feedback_parts.append(f"⚠️ Many unused keys in translation file: {len(extra_keys)}")
        else:
            if json_keys:
                score_breakdown['key_consistency'] = 10
                feedback_parts.append("△ Translation file has keys, but no t() calls found in code")
            else:
                feedback_parts.append("❌ No translation keys found in code or translation file")

        # === 5. Check selective extraction (console.log preserved) ===
        console_log_count = count_console_logs(app_js_content)
        
        # Original file had 6 console.log statements
        if console_log_count >= 5:
            score_breakdown['selective_extraction'] = 15
            feedback_parts.append(f"✅ Debug statements preserved ({console_log_count} console.log found)")
        elif console_log_count >= 3:
            score_breakdown['selective_extraction'] = 10
            feedback_parts.append(f"△ Some debug statements preserved ({console_log_count} console.log)")
        elif console_log_count >= 1:
            score_breakdown['selective_extraction'] = 5
            feedback_parts.append(f"△ Few debug statements ({console_log_count} console.log)")
        else:
            score_breakdown['selective_extraction'] = 8
            feedback_parts.append("⚠️ No console.log found (may have been incorrectly internationalized or removed)")
        
        # Check that user-facing strings were actually removed
        remaining_hardcoded_user_strings = 0
        user_strings_to_check = [
            "Please enter both username and password",
            "Welcome back",
            "Invalid credentials",
            "Submit",
            "Cancel",
            "User Profile",
            "Email is required"
        ]
        
        for user_str in user_strings_to_check:
            # Check if these strings still appear as hardcoded (not in t() calls)
            # Simple heuristic: if string appears outside of console.log
            if user_str in app_js_content:
                # Check if it's in a t() call or console.log
                context_pattern = f'''(t\(['"]{re.escape(user_str)}['"]\)|console\.log.*{re.escape(user_str)})'''
                if not re.search(context_pattern, app_js_content):
                    remaining_hardcoded_user_strings += 1
        
        if remaining_hardcoded_user_strings > 3:
            feedback_parts.append(f"⚠️ Many user-facing strings still hardcoded: ~{remaining_hardcoded_user_strings}")
            # Reduce selective extraction score slightly
            score_breakdown['selective_extraction'] = max(0, score_breakdown['selective_extraction'] - 5)

        # === Calculate final score ===
        final_score = sum(score_breakdown.values())
        passed = final_score >= 70
        
        feedback_parts.append(f"\n📊 Score breakdown: Translation={score_breakdown['translation_file']}/20, Quality={score_breakdown['translation_quality']}/15, Code={score_breakdown['code_modified']}/25, Consistency={score_breakdown['key_consistency']}/25, Selective={score_breakdown['selective_extraction']}/15")
        feedback_parts.append(f"🎯 Final Score: {final_score}/100")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": final_score,
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
        if os.path.exists(temp_dir):
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)
