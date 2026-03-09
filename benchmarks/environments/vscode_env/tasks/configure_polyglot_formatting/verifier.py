#!/usr/bin/env python3
"""
Verifier for Multi-Language Formatter Configuration task
"""

import sys
import os
import logging
import tempfile
import json
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import parse_vscode_settings

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Valid formatter identifiers for each language
VALID_PYTHON_FORMATTERS = [
    "ms-python.black-formatter",
    "ms-python.python"
]

VALID_JS_FORMATTERS = [
    "esbenp.prettier-vscode",
    "vscode.typescript-language-features",
    "vscode.javascript"
]

VALID_JSON_FORMATTERS = [
    "esbenp.prettier-vscode",
    "vscode.json-language-features",
    "vscode.json"
]


def verify_language_formatter(settings, language, valid_formatters):
    """
    Verify that a specific language has a valid formatter configured
    
    Args:
        settings: Parsed settings dict
        language: Language identifier (e.g., 'python', 'javascript', 'json')
        valid_formatters: List of valid formatter extension IDs
    
    Returns:
        Tuple of (configured: bool, formatter: str, message: str)
    """
    lang_key = f"[{language}]"
    
    if lang_key not in settings:
        return False, None, f"No [{language}] configuration section found"
    
    lang_config = settings[lang_key]
    
    if not isinstance(lang_config, dict):
        return False, None, f"[{language}] configuration is not a valid object"
    
    formatter = lang_config.get('editor.defaultFormatter', '')
    
    if not formatter:
        return False, None, f"No editor.defaultFormatter specified in [{language}] section"
    
    if formatter not in valid_formatters:
        return False, formatter, f"Invalid formatter '{formatter}' for [{language}] (expected one of: {', '.join(valid_formatters[:2])})"
    
    return True, formatter, f"✅ {language} → {formatter}"


def merge_settings(workspace_settings, user_settings):
    """
    Merge workspace and user settings, with workspace taking precedence
    
    Args:
        workspace_settings: Dict of workspace settings
        user_settings: Dict of user settings
    
    Returns:
        Merged settings dict
    """
    # Start with user settings
    merged = user_settings.copy() if user_settings else {}
    
    # Override with workspace settings
    if workspace_settings:
        for key, value in workspace_settings.items():
            merged[key] = value
    
    return merged


def verify_formatter_config(traj, env_info, task_info):
    """
    Verify that language-specific formatters are configured correctly.
    
    Checks:
    1. Python formatter configured in [python] section
    2. JavaScript formatter configured in [javascript] section
    3. JSON formatter configured in [json] section
    4. Valid JSON syntax in settings file
    
    Pass threshold: 70% (at least 2 out of 3 languages configured)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='vscode_formatter_verify_')

    try:
        # Copy settings files exported by export_result.sh
        workspace_settings_local = os.path.join(temp_dir, "workspace_settings.json")
        user_settings_local = os.path.join(temp_dir, "user_settings.json")

        workspace_settings = {}
        user_settings = {}
        settings_source = None

        # Try to load workspace settings
        try:
            copy_from_env("/tmp/workspace_settings.json", workspace_settings_local)
            if os.path.exists(workspace_settings_local) and os.path.getsize(workspace_settings_local) > 0:
                workspace_settings = parse_vscode_settings(workspace_settings_local)
                if workspace_settings and workspace_settings != {}:
                    settings_source = "workspace"
                    logger.info(f"Loaded workspace settings: {len(workspace_settings)} keys")
        except Exception as e:
            logger.warning(f"Failed to load workspace settings: {e}")

        # Try to load user settings
        try:
            copy_from_env("/tmp/user_settings.json", user_settings_local)
            if os.path.exists(user_settings_local) and os.path.getsize(user_settings_local) > 0:
                user_settings = parse_vscode_settings(user_settings_local)
                if user_settings and user_settings != {}:
                    if not settings_source:
                        settings_source = "user"
                    else:
                        settings_source = "workspace+user"
                    logger.info(f"Loaded user settings: {len(user_settings)} keys")
        except Exception as e:
            logger.warning(f"Failed to load user settings: {e}")

        # Merge settings (workspace overrides user)
        settings = merge_settings(workspace_settings, user_settings)

        if not settings or settings == {}:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ No settings found. Please configure language-specific formatters in VSCode settings (Ctrl+Shift+P → 'Preferences: Open Settings (JSON)')"
            }

        # Verify each language configuration
        python_ok, python_formatter, python_msg = verify_language_formatter(
            settings, 'python', VALID_PYTHON_FORMATTERS
        )
        js_ok, js_formatter, js_msg = verify_language_formatter(
            settings, 'javascript', VALID_JS_FORMATTERS
        )
        json_ok, json_formatter, json_msg = verify_language_formatter(
            settings, 'json', VALID_JSON_FORMATTERS
        )

        # Count successes
        configured_count = sum([python_ok, js_ok, json_ok])

        # Build detailed feedback
        feedback_parts = []
        feedback_parts.append(f"Settings source: {settings_source}\n")

        # Language-specific results
        feedback_parts.append(f"{'✅' if python_ok else '❌'} Python: {python_msg}")
        feedback_parts.append(f"{'✅' if js_ok else '❌'} JavaScript: {js_msg}")
        feedback_parts.append(f"{'✅' if json_ok else '❌'} JSON: {json_msg}")

        # Calculate score
        score = (configured_count / 3.0) * 100

        # Bonus points for having all three
        if configured_count == 3:
            feedback_parts.append("\n🎉 All three languages configured correctly!")

        feedback_parts.append(f"\n📊 Configured languages: {configured_count}/3")
        feedback_parts.append(f"Score: {score:.0f}%")

        # Determine pass/fail (70% threshold = at least 2/3)
        passed = score >= 70

        if passed:
            feedback_parts.insert(0, "✅ PASS: Language-specific formatters configured successfully!\n")
        else:
            feedback_parts.insert(0, "❌ FAIL: Need at least 2 out of 3 languages configured correctly\n")
            feedback_parts.append("\n💡 Hint: Add language-specific sections like:")
            feedback_parts.append('   "[python]": { "editor.defaultFormatter": "ms-python.black-formatter" }')
            feedback_parts.append('   "[javascript]": { "editor.defaultFormatter": "esbenp.prettier-vscode" }')
            feedback_parts.append('   "[json]": { "editor.defaultFormatter": "esbenp.prettier-vscode" }')

        return {
            "passed": passed,
            "score": int(score),
            "feedback": "\n".join(feedback_parts)
        }

    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Invalid JSON syntax in settings file: {str(e)}"
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
