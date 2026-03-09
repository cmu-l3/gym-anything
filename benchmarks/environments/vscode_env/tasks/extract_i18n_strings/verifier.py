#!/usr/bin/env python3
"""
Verifier for extract_i18n_strings@1 task
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


def count_translation_keys(obj):
    """Recursively count leaf keys in nested dict"""
    if isinstance(obj, dict):
        return sum(count_translation_keys(v) for v in obj.values())
    return 1


def verify_i18n_extraction(traj, env_info, task_info):
    """
    Verify that i18n strings were properly extracted and components updated.
    
    Checks:
    1. Translation file exists with valid JSON structure (20 points)
    2. Translation file contains expected keys and good coverage (25 points)
    3. i18nConfig.js file was created with proper setup (15 points)
    4. At least 3 components were updated to use i18n (40 points)
    
    Returns:
        dict with passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    workspace = "/home/ga/workspace/dashboard-app"
    temp_dir = tempfile.mkdtemp(prefix='i18n_verify_')
    
    try:
        score = 0
        max_score = 100
        details = {}
        feedback_parts = []
        
        # === Check 1: Translation file exists and is valid JSON (20 points) ===
        translation_container_path = os.path.join(workspace, "src/locales/en.json")
        translation_local_path = os.path.join(temp_dir, "en.json")
        
        translation_exists = False
        translations = {}
        
        try:
            copy_from_env(translation_container_path, translation_local_path)
            
            if os.path.exists(translation_local_path) and os.path.getsize(translation_local_path) > 0:
                translation_exists = True
                details["translation_file_exists"] = True
                score += 10
                feedback_parts.append("✅ Translation file exists")
                
                # Try to parse JSON
                try:
                    with open(translation_local_path, 'r', encoding='utf-8') as f:
                        translations = json.load(f)
                    
                    details["translation_valid_json"] = True
                    score += 10
                    feedback_parts.append("✅ Translation file is valid JSON")
                    
                except json.JSONDecodeError as e:
                    details["translation_valid_json"] = False
                    feedback_parts.append(f"❌ Translation file is not valid JSON: {e}")
                except Exception as e:
                    details["translation_valid_json"] = False
                    feedback_parts.append(f"❌ Error reading translation file: {e}")
            else:
                details["translation_file_exists"] = False
                feedback_parts.append("❌ Translation file not found or empty")
                
        except Exception as e:
            logger.warning(f"Failed to copy translation file: {e}")
            details["translation_file_exists"] = False
            feedback_parts.append("❌ Translation file not found")
        
        # === Check 2: Translation structure and coverage (25 points) ===
        if translations:
            # Check for reasonable structure
            expected_sections = ['header', 'login', 'dashboard']
            found_sections = [s for s in expected_sections if s in translations]
            
            details["translation_sections"] = found_sections
            
            if len(found_sections) >= 3:
                score += 8
                feedback_parts.append(f"✅ Translation file has all 3 sections")
            elif len(found_sections) >= 2:
                score += 5
                feedback_parts.append(f"⚠️ Translation file has {len(found_sections)} sections (expected 3)")
            else:
                score += 2
                feedback_parts.append(f"❌ Translation file has only {len(found_sections)} section(s)")
            
            # Count total translation keys
            total_keys = count_translation_keys(translations)
            details["translation_key_count"] = total_keys
            
            if total_keys >= 15:
                score += 12
                feedback_parts.append(f"✅ Excellent coverage: {total_keys} translation keys")
            elif total_keys >= 10:
                score += 8
                feedback_parts.append(f"✅ Good coverage: {total_keys} translation keys")
            elif total_keys >= 6:
                score += 4
                feedback_parts.append(f"⚠️ Moderate coverage: {total_keys} translation keys")
            else:
                feedback_parts.append(f"❌ Poor coverage: only {total_keys} translation keys")
            
            # Check for nested structure (good practice)
            has_nested = any(isinstance(v, dict) for v in translations.values())
            if has_nested:
                score += 5
                feedback_parts.append("✅ Good structure: nested organization")
            else:
                score += 2
                feedback_parts.append("⚠️ Flat structure (nested would be better)")
        
        # === Check 3: i18nConfig.js exists and is properly configured (15 points) ===
        config_container_path = os.path.join(workspace, "src/i18nConfig.js")
        config_local_path = os.path.join(temp_dir, "i18nConfig.js")
        
        try:
            copy_from_env(config_container_path, config_local_path)
            
            if os.path.exists(config_local_path) and os.path.getsize(config_local_path) > 0:
                with open(config_local_path, 'r', encoding='utf-8') as f:
                    config_content = f.read()
                
                details["i18n_config_exists"] = True
                
                # Check for essential imports and setup
                has_i18n_import = 'i18next' in config_content or "import i18n" in config_content
                has_react_i18next = 'react-i18next' in config_content or 'initReactI18next' in config_content
                has_init = '.init(' in config_content or 'init(' in config_content
                has_translation_import = "locales/en" in config_content or "locales/en.json" in config_content
                
                config_score = 0
                if has_i18n_import:
                    config_score += 4
                if has_react_i18next:
                    config_score += 4
                if has_init:
                    config_score += 4
                if has_translation_import:
                    config_score += 3
                
                score += config_score
                
                if config_score >= 12:
                    details["i18n_config"] = "complete"
                    feedback_parts.append("✅ i18nConfig.js properly configured")
                elif config_score >= 6:
                    details["i18n_config"] = "partial"
                    feedback_parts.append("⚠️ i18nConfig.js exists but may be incomplete")
                else:
                    details["i18n_config"] = "minimal"
                    feedback_parts.append("⚠️ i18nConfig.js has minimal setup")
                    
            else:
                details["i18n_config_exists"] = False
                feedback_parts.append("❌ i18nConfig.js not found")
                
        except Exception as e:
            logger.warning(f"Failed to copy i18nConfig.js: {e}")
            details["i18n_config_exists"] = False
            feedback_parts.append("❌ i18nConfig.js not found")
        
        # === Check 4: Components updated to use i18n (40 points) ===
        components_to_check = [
            ("src/components/Header.jsx", "Header"),
            ("src/components/LoginForm.jsx", "LoginForm"),
            ("src/components/Dashboard.jsx", "Dashboard")
        ]
        
        updated_components = []
        partially_updated = []
        
        for component_path, component_name in components_to_check:
            container_path = os.path.join(workspace, component_path)
            local_path = os.path.join(temp_dir, os.path.basename(component_path))
            
            try:
                copy_from_env(container_path, local_path)
                
                if not os.path.exists(local_path):
                    continue
                
                with open(local_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                # Check if component imports i18n
                has_import = 'useTranslation' in content and 'react-i18next' in content
                has_hook_call = re.search(r'useTranslation\s*\(', content)
                has_t_variable = re.search(r'const\s*{\s*t\s*}', content) or re.search(r'const\s+t\s*=', content)
                has_t_calls = bool(re.search(r'\{?\s*t\s*\([\'"`]', content))
                
                component_score = 0
                if has_import:
                    component_score += 1
                if has_hook_call:
                    component_score += 1
                if has_t_variable:
                    component_score += 1
                if has_t_calls:
                    component_score += 2
                
                if component_score >= 4:
                    updated_components.append(component_name)
                elif component_score >= 2:
                    partially_updated.append(component_name)
                    
            except Exception as e:
                logger.warning(f"Failed to check {component_path}: {e}")
        
        details["updated_components_count"] = len(updated_components)
        details["updated_components"] = updated_components
        details["partially_updated_components"] = partially_updated
        
        # Award points based on components updated
        if len(updated_components) >= 3:
            score += 40
            feedback_parts.append("✅ All 3 components fully updated with i18n")
        elif len(updated_components) == 2:
            score += 28
            if partially_updated:
                feedback_parts.append(f"✅ 2 components fully updated, 1 partially: {', '.join(partially_updated)}")
            else:
                feedback_parts.append("⚠️ 2 components updated (1 missing)")
        elif len(updated_components) == 1:
            score += 15
            feedback_parts.append(f"⚠️ Only 1 component fully updated: {', '.join(updated_components)}")
        elif partially_updated:
            score += 8
            feedback_parts.append(f"⚠️ Partial updates in: {', '.join(partially_updated)}")
        else:
            feedback_parts.append("❌ No components updated to use i18n")
        
        # === Final scoring ===
        final_score = score / max_score
        details["raw_score"] = score
        details["max_score"] = max_score
        
        # Generate summary feedback
        if final_score >= 0.90:
            summary = "🎉 Excellent! The app is fully ready for internationalization."
        elif final_score >= 0.70:
            summary = "✅ Good work! i18n setup is mostly complete."
        elif final_score >= 0.50:
            summary = "⚠️ Partial completion. More work needed on components."
        else:
            summary = "❌ Incomplete. Significant i18n work still required."
        
        passed = final_score >= 0.70
        
        feedback = f"{summary}\n" + " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": int(final_score * 100),
            "feedback": feedback,
            "details": details
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
