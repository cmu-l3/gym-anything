#!/usr/bin/env python3
"""
Verifier for Setup Team Devcontainer task
Checks devcontainer configuration for team environment consistency
"""

import sys
import os
import json
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_devcontainer_setup(traj, env_info, task_info):
    """
    Verify devcontainer setup task completion.
    
    Checks:
    1. .devcontainer/devcontainer.json exists and is valid JSON (15 points)
    2. Correct Node.js 18 base image configured (20 points)
    3. All required extensions specified (30 points)
    4. Post-create command configured (15 points)
    5. Editor settings embedded (10 points)
    6. Team documentation created (10 points)
    
    Pass threshold: 70%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='devcontainer_verify_')
    
    try:
        # Copy exported files
        devcontainer_local = os.path.join(temp_dir, "devcontainer.json")
        readme_local = os.path.join(temp_dir, "README_DEVCONTAINER.md")
        
        try:
            copy_from_env("/tmp/devcontainer.json", devcontainer_local)
        except Exception as e:
            logger.warning(f"Failed to copy devcontainer.json: {e}")
        
        try:
            copy_from_env("/tmp/README_DEVCONTAINER.md", readme_local)
        except Exception as e:
            logger.warning(f"Failed to copy README_DEVCONTAINER.md: {e}")
        
        results = {
            "criteria": {},
            "total_score": 0,
            "max_score": 100,
            "feedback": []
        }
        
        # Criterion 1: Devcontainer file exists and is valid JSON (15 points)
        config = {}
        if os.path.exists(devcontainer_local) and os.path.getsize(devcontainer_local) > 0:
            try:
                with open(devcontainer_local, 'r', encoding='utf-8') as f:
                    config = json.load(f)
                results["criteria"]["devcontainer_exists"] = 15
                results["feedback"].append("✅ Devcontainer configuration file exists and is valid JSON")
            except json.JSONDecodeError as e:
                results["criteria"]["devcontainer_exists"] = 5
                results["feedback"].append(f"⚠️ Devcontainer file exists but is invalid JSON: {str(e)[:50]}")
        else:
            results["criteria"]["devcontainer_exists"] = 0
            results["feedback"].append("❌ Devcontainer configuration file missing or empty")
        
        # Criterion 2: Correct base image configured (20 points)
        image_score = 0
        image_field = config.get("image", "")
        dockerfile_field = config.get("dockerFile", "")
        build_field = config.get("build", {})
        name_field = config.get("name", "")
        
        # Check for Node.js 18 image
        if "javascript-node" in image_field and "18" in image_field:
            image_score += 15
            results["feedback"].append("✅ Correct Node.js 18 devcontainer base image specified")
        elif "node:18" in image_field.lower() or "node" in image_field.lower() and "18" in image_field:
            image_score += 12
            results["feedback"].append("⚠️ Node 18 image found but not official devcontainer image")
        elif dockerfile_field or build_field:
            # If using Dockerfile or build config, check if it references Node 18
            if isinstance(build_field, dict):
                build_dockerfile = build_field.get("dockerfile", "")
                if "node" in build_dockerfile.lower():
                    image_score += 10
                    results["feedback"].append("⚠️ Custom Dockerfile/build configuration detected")
            elif "node" in dockerfile_field.lower():
                image_score += 10
                results["feedback"].append("⚠️ Custom Dockerfile detected")
        
        # Check container name
        if "team-project" in name_field.lower():
            image_score += 5
            results["feedback"].append("✅ Container properly named")
        elif name_field:
            image_score += 3
            results["feedback"].append("⚠️ Container has a name but doesn't match 'team-project-dev'")
        
        if image_score == 0:
            results["feedback"].append("❌ Base image not properly configured (expected Node.js 18)")
        
        results["criteria"]["base_image"] = image_score
        
        # Criterion 3: Required extensions specified (30 points)
        required_extensions = {
            "dbaeumer.vscode-eslint": "ESLint",
            "esbenp.prettier-vscode": "Prettier",
            "eamodio.gitlens": "GitLens"
        }
        
        extensions_list = []
        
        # Check new format (customizations.vscode.extensions)
        customizations = config.get("customizations", {})
        vscode_config = customizations.get("vscode", {})
        extensions_list = vscode_config.get("extensions", [])
        
        # Also check old format (extensions at root level)
        if not extensions_list:
            extensions_list = config.get("extensions", [])
        
        extensions_score = 0
        for ext_id, ext_name in required_extensions.items():
            if any(ext_id.lower() in ext.lower() for ext in extensions_list):
                extensions_score += 10
                results["feedback"].append(f"✅ {ext_name} extension specified")
            else:
                results["feedback"].append(f"❌ {ext_name} extension missing ({ext_id})")
        
        results["criteria"]["required_extensions"] = extensions_score
        
        # Criterion 4: Post-create command configured (15 points)
        post_create_cmd = config.get("postCreateCommand", "")
        post_start_cmd = config.get("postStartCommand", "")
        post_attach_cmd = config.get("postAttachCommand", "")
        
        # Check various command formats
        if isinstance(post_create_cmd, list):
            post_create_cmd = " ".join(post_create_cmd)
        
        post_create_str = str(post_create_cmd).lower()
        
        if "npm install" in post_create_str or "npm i" in post_create_str:
            results["criteria"]["post_create"] = 15
            results["feedback"].append("✅ Post-create command runs 'npm install'")
        elif "npm" in post_create_str:
            results["criteria"]["post_create"] = 10
            results["feedback"].append("⚠️ Post-create command references npm but not 'install'")
        elif "npm install" in str(post_start_cmd).lower() or "npm install" in str(post_attach_cmd).lower():
            results["criteria"]["post_create"] = 12
            results["feedback"].append("⚠️ npm install found in postStartCommand or postAttachCommand (should be in postCreateCommand)")
        else:
            results["criteria"]["post_create"] = 0
            results["feedback"].append("❌ Post-create command not configured to run 'npm install'")
        
        # Criterion 5: Editor settings embedded (10 points)
        settings_score = 0
        vscode_settings = vscode_config.get("settings", {})
        
        # Also check old format (settings at root level)
        if not vscode_settings:
            vscode_settings = config.get("settings", {})
        
        # Check format on save
        format_on_save = vscode_settings.get("editor.formatOnSave", False)
        if format_on_save is True or str(format_on_save).lower() == "true":
            settings_score += 5
            results["feedback"].append("✅ Format on save enabled")
        else:
            results["feedback"].append("❌ Format on save not enabled")
        
        # Check Prettier as JavaScript formatter
        js_config = vscode_settings.get("[javascript]", {})
        if not js_config:
            # Also check alternative formats
            js_config = vscode_settings.get("javascript", {})
        
        js_formatter = js_config.get("editor.defaultFormatter", "")
        if not js_formatter:
            # Check global formatter setting
            js_formatter = vscode_settings.get("editor.defaultFormatter", "")
        
        if "prettier" in js_formatter.lower() or "esbenp.prettier-vscode" in js_formatter.lower():
            settings_score += 5
            results["feedback"].append("✅ Prettier set as JavaScript formatter")
        else:
            results["feedback"].append("❌ Prettier not set as default JavaScript formatter")
        
        results["criteria"]["editor_settings"] = settings_score
        
        # Criterion 6: Team documentation created (10 points)
        doc_score = 0
        if os.path.exists(readme_local) and os.path.getsize(readme_local) > 0:
            with open(readme_local, 'r', encoding='utf-8') as f:
                readme_content = f.read()
            
            # Check for substantial content
            if len(readme_content) > 200:
                doc_score += 5
                results["feedback"].append("✅ Documentation file has substantial content")
            elif len(readme_content) > 50:
                doc_score += 3
                results["feedback"].append("⚠️ Documentation file exists but is brief")
            
            readme_lower = readme_content.lower()
            
            # Check for key terms
            has_container_mention = "container" in readme_lower or "devcontainer" in readme_lower
            has_instructions = "reopen" in readme_lower or "rebuild" in readme_lower or "open" in readme_lower
            
            if has_container_mention:
                doc_score += 3
                
            if has_instructions:
                doc_score += 2
                results["feedback"].append("✅ Documentation includes container usage instructions")
            
            # Cap at 10 points
            doc_score = min(doc_score, 10)
        else:
            results["feedback"].append("❌ Team documentation file (README_DEVCONTAINER.md) missing")
        
        results["criteria"]["documentation"] = doc_score
        
        # Calculate total score
        results["total_score"] = sum(results["criteria"].values())
        score_percentage = (results["total_score"] / results["max_score"]) * 100
        
        # Determine success (70% threshold)
        success = score_percentage >= 70
        
        feedback_str = "\n".join(results["feedback"])
        
        return {
            "passed": success,
            "score": score_percentage,
            "raw_score": results["total_score"],
            "max_score": results["max_score"],
            "criteria_breakdown": results["criteria"],
            "feedback": feedback_str,
            "message": f"Score: {score_percentage:.1f}% ({'PASS' if success else 'FAIL'}) - {results['total_score']}/{results['max_score']} points"
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "message": "Verification failed due to error"
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
