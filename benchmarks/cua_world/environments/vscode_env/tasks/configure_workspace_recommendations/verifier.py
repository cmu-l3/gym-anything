#!/usr/bin/env python3
"""
Verifier for Configure Workspace Recommendations task
"""

import sys
import os
import json
import re
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Common legitimate extensions for validation
KNOWN_GOOD_EXTENSIONS = {
    # Python
    'ms-python.python',
    'ms-python.vscode-pylance',
    'ms-python.black-formatter',
    'ms-python.pylint',
    'ms-python.isort',
    'ms-python.flake8',
    'ms-python.autopep8',
    
    # JavaScript/TypeScript
    'dbaeumer.vscode-eslint',
    'esbenp.prettier-vscode',
    'ms-vscode.vscode-typescript-next',
    'xabikos.javascriptsnippets',
    'standard.vscode-standard',
    
    # General development
    'eamodio.gitlens',
    'mhutchie.git-graph',
    'donjayamanne.githistory',
    'christian-kohler.path-intellisense',
    'visualstudioexptteam.vscodeintellicode',
    'streetsidesoftware.code-spell-checker',
    'redhat.vscode-yaml',
    'tamasfe.even-better-toml',
    
    # Docker/DevOps
    'ms-azuretools.vscode-docker',
    'ms-kubernetes-tools.vscode-kubernetes-tools',
    
    # Other languages
    'golang.go',
    'rust-lang.rust-analyzer',
    'ms-vscode.cpptools',
}

# Extensions that are personal preference (themes/icons - not team recommendations)
PERSONAL_PREFERENCE_EXTENSIONS = [
    'pkief.material-icon-theme',
    'equinusocio.vsc-material-theme',
    'zhuangtongfa.material-theme',
    'dracula-theme.theme-dracula',
    'github.github-vscode-theme',
    'vscode-icons-team.vscode-icons',
]


def verify_workspace_recommendations(traj, env_info, task_info):
    """
    Verify that workspace extension recommendations are properly configured.
    
    Checks:
    1. .vscode/extensions.json file exists (20 points)
    2. Valid JSON structure (20 points)
    3. Has 'recommendations' array (10 points)
    4. At least 3 extensions recommended (15 points)
    5. Valid extension ID format (15 points)
    6. Extensions are relevant/known (10 points)
    7. No personal preference extensions (5 points)
    8. No duplicate extensions (5 points)
    
    Pass threshold: 75% (75/100 points)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='workspace_recommendations_verify_')
    
    try:
        # Copy extensions.json from container (exported by export_result.sh)
        extensions_json_container = "/tmp/extensions.json"
        extensions_json_local = os.path.join(temp_dir, "extensions.json")
        
        try:
            copy_from_env(extensions_json_container, extensions_json_local)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Failed to copy extensions.json: {str(e)}"
            }
        
        feedback_parts = []
        score = 0
        max_score = 100
        
        # Check 1: File exists and is not error placeholder (20 points)
        if not os.path.exists(extensions_json_local) or os.path.getsize(extensions_json_local) == 0:
            feedback_parts.append("❌ File .vscode/extensions.json does not exist or is empty")
            return {
                'passed': False,
                'score': 0.0,
                'feedback': '\n'.join(feedback_parts)
            }
        
        # Read content to check for error markers
        with open(extensions_json_local, 'r', encoding='utf-8') as f:
            raw_content = f.read()
        
        if 'file_not_found' in raw_content or 'error' in raw_content:
            feedback_parts.append("❌ File .vscode/extensions.json was not created")
            return {
                'passed': False,
                'score': 0.0,
                'feedback': '\n'.join(feedback_parts)
            }
        
        feedback_parts.append("✅ File .vscode/extensions.json exists")
        score += 20
        
        # Check 2: Valid JSON (20 points)
        try:
            with open(extensions_json_local, 'r', encoding='utf-8') as f:
                config = json.load(f)
        except json.JSONDecodeError as e:
            feedback_parts.append(f"❌ Invalid JSON syntax: {str(e)[:100]}")
            return {
                'passed': False,
                'score': score / max_score,
                'feedback': '\n'.join(feedback_parts)
            }
        except Exception as e:
            feedback_parts.append(f"❌ Error reading JSON: {str(e)[:100]}")
            return {
                'passed': False,
                'score': score / max_score,
                'feedback': '\n'.join(feedback_parts)
            }
        
        feedback_parts.append("✅ Valid JSON structure")
        score += 20
        
        # Check 3: Has recommendations array (10 points)
        if 'recommendations' not in config:
            feedback_parts.append("❌ Missing 'recommendations' field in JSON")
            return {
                'passed': False,
                'score': score / max_score,
                'feedback': '\n'.join(feedback_parts)
            }
        
        if not isinstance(config['recommendations'], list):
            feedback_parts.append("❌ 'recommendations' must be an array/list")
            return {
                'passed': False,
                'score': score / max_score,
                'feedback': '\n'.join(feedback_parts)
            }
        
        feedback_parts.append("✅ Has 'recommendations' array")
        score += 10
        
        recommendations = config['recommendations']
        
        # Check 4: Sufficient number of extensions (15 points)
        num_recommendations = len(recommendations)
        
        if num_recommendations == 0:
            feedback_parts.append("❌ Recommendations array is empty (need at least 3)")
            return {
                'passed': False,
                'score': score / max_score,
                'feedback': '\n'.join(feedback_parts)
            }
        elif num_recommendations < 3:
            feedback_parts.append(f"❌ Only {num_recommendations} extension(s) recommended (need at least 3)")
            return {
                'passed': False,
                'score': score / max_score,
                'feedback': '\n'.join(feedback_parts)
            }
        elif num_recommendations >= 5:
            feedback_parts.append(f"✅ Excellent: {num_recommendations} extensions recommended")
            score += 15
        elif num_recommendations >= 3:
            feedback_parts.append(f"✅ Good: {num_recommendations} extensions recommended")
            score += 12
        
        # Check 5: Valid extension ID format (15 points)
        # Format should be: publisher.extension-name (lowercase, alphanumeric with hyphens)
        extension_id_pattern = re.compile(r'^[a-z0-9\-]+\.[a-z0-9\-]+$', re.IGNORECASE)
        invalid_ids = []
        
        for ext in recommendations:
            if not isinstance(ext, str):
                invalid_ids.append(f"{ext} (not a string)")
            elif not extension_id_pattern.match(ext):
                invalid_ids.append(ext)
        
        if invalid_ids:
            feedback_parts.append(f"❌ Invalid extension ID format: {invalid_ids[:3]}")
            score += 5  # Partial credit
        else:
            feedback_parts.append("✅ All extension IDs have valid format (publisher.name)")
            score += 15
        
        # Check 6: Extensions are relevant/known (10 points)
        known_extensions = [
            ext for ext in recommendations 
            if ext.lower() in {e.lower() for e in KNOWN_GOOD_EXTENSIONS}
        ]
        unknown_extensions = [
            ext for ext in recommendations
            if ext.lower() not in {e.lower() for e in KNOWN_GOOD_EXTENSIONS}
        ]
        
        known_count = len(known_extensions)
        
        if known_count >= 3:
            feedback_parts.append(f"✅ {known_count} recognized professional extensions")
            score += 10
        elif known_count >= 1:
            feedback_parts.append(f"⚠️  Only {known_count} recognized extension(s)")
            if unknown_extensions:
                feedback_parts.append(f"   Unknown: {unknown_extensions[:2]}")
            score += 5
        else:
            feedback_parts.append("⚠️  No commonly recognized extensions found")
            if unknown_extensions:
                feedback_parts.append(f"   Provided: {unknown_extensions[:3]}")
        
        # Check 7: No personal preference extensions (5 points)
        personal_found = [
            ext for ext in recommendations 
            if ext.lower() in {e.lower() for e in PERSONAL_PREFERENCE_EXTENSIONS}
        ]
        
        if personal_found:
            feedback_parts.append(f"⚠️  Found personal preference extensions (themes/icons): {personal_found}")
            score += 2
        else:
            feedback_parts.append("✅ No personal preference extensions (good team focus)")
            score += 5
        
        # Check 8: No duplicate extensions (5 points)
        unique_recommendations = list(set([ext.lower() for ext in recommendations]))
        
        if len(unique_recommendations) < len(recommendations):
            feedback_parts.append("⚠️  Duplicate extension IDs detected")
            score += 2
        else:
            feedback_parts.append("✅ No duplicate extensions")
            score += 5
        
        # Final assessment
        normalized_score = score / max_score
        passed = normalized_score >= 0.75
        
        feedback_parts.append(f"\n📊 Final Score: {score}/{max_score} ({normalized_score*100:.1f}%)")
        
        if passed:
            feedback_parts.append("✅ PASSED: Workspace recommendations properly configured")
        else:
            feedback_parts.append("❌ FAILED: Configuration needs improvement")
        
        return {
            'passed': passed,
            'score': int(normalized_score * 100),  # Return as integer percentage
            'feedback': '\n'.join(feedback_parts),
            'details': {
                'num_recommendations': num_recommendations,
                'known_extensions': known_count,
                'has_personal_prefs': len(personal_found) > 0,
                'has_duplicates': len(unique_recommendations) < len(recommendations)
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
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
