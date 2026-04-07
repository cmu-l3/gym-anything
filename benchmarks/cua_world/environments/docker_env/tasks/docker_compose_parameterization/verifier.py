#!/usr/bin/env python3
import json
import base64
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_compose_parameterization(traj, env_info, task_info):
    """
    Verifies that the docker-compose.yml was refactored with variables/defaults
    and that the stack is running with the requested production configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring weights
    SCORE_TOTAL = 0
    MAX_SCORE = 100
    
    # Metadata targets
    META = task_info.get('metadata', {})
    PROD_VALS = META.get('prod_values', {})
    DEFAULT_VALS = META.get('default_values', {})

    feedback = []

    # =========================================================
    # 1. Static Analysis of docker-compose.yml (40 points total)
    # =========================================================
    compose_b64 = result.get('compose_content_b64', '')
    if not compose_b64:
        feedback.append("docker-compose.yml not found.")
    else:
        try:
            compose_content = base64.b64decode(compose_b64).decode('utf-8')
            
            # Check for variable usage: ${VAR} or $VAR
            # We look for specific patterns replacing the hardcoded values
            
            # A. Postgres Image Tag (5 pts)
            if re.search(r'image:\s*postgres:\$\{.*\}', compose_content) or \
               re.search(r'image:\s*postgres:\$', compose_content):
                SCORE_TOTAL += 5
                feedback.append("Refactored Postgres image tag.")
            else:
                feedback.append("Postgres image tag not refactored (still hardcoded?).")

            # B. Postgres Password (5 pts)
            if re.search(r'POSTGRES_PASSWORD:\s*\$\{.*\}', compose_content) or \
               re.search(r'POSTGRES_PASSWORD:\s*\$', compose_content):
                SCORE_TOTAL += 5
                feedback.append("Refactored Postgres password.")
            else:
                feedback.append("Postgres password not refactored.")

            # C. Node/App Image Tag/Args (5 pts)
            # The dockerfile might use an ARG, but the compose file passing it or the image tag 
            # might be parameterized. The task asks to refactor compose. 
            # Could be 'image: inventory-app:${TAG}' or build args. 
            # Or the Dockerfile build context might be passing args.
            # Let's check generally if variables are used in the inventory-web service.
            if re.search(r'image:\s*.*:\$\{.*\}', compose_content) or \
               re.search(r'args:\s*.*NODE_VERSION', compose_content, re.IGNORECASE):
                SCORE_TOTAL += 5
                feedback.append("Refactored App/Node image configuration.")
            else:
                feedback.append("App image/build config not clearly refactored.")

            # D. Host Port (5 pts)
            # Look for "3000:3000" becoming "${PORT}:3000"
            if re.search(r'["\']?\$\{.*\}["\']?:3000', compose_content):
                SCORE_TOTAL += 5
                feedback.append("Refactored Host Port mapping.")
            else:
                feedback.append("Host Port mapping not refactored.")

            # E. App Mode (5 pts)
            if re.search(r'APP_MODE:\s*\$\{.*\}', compose_content) or \
               re.search(r'APP_MODE:\s*\$', compose_content):
                SCORE_TOTAL += 5
                feedback.append("Refactored APP_MODE.")
            else:
                feedback.append("APP_MODE not refactored.")

            # F. Check for Default Values Usage (:- syntax) (15 pts)
            # We check if at least 3 distinct variables use the :- syntax
            defaults_count = len(re.findall(r'\$\{.*:-.*\}', compose_content))
            if defaults_count >= 3:
                SCORE_TOTAL += 15
                feedback.append(f"Correctly used default value syntax ({defaults_count} found).")
            elif defaults_count > 0:
                SCORE_TOTAL += 5
                feedback.append(f"Partially used default value syntax (only {defaults_count} found).")
            else:
                feedback.append("Did not use ':-default' syntax for default values.")

        except Exception as e:
            feedback.append(f"Error parsing compose file: {str(e)}")

    # =========================================================
    # 2. Production Config File (.env.prod) (20 points)
    # =========================================================
    env_b64 = result.get('env_content_b64', '')
    if env_b64:
        try:
            env_content = base64.b64decode(env_b64).decode('utf-8')
            # Check for required prod values
            if PROD_VALS['password'] in env_content:
                SCORE_TOTAL += 5
            if PROD_VALS['port'] in env_content:
                SCORE_TOTAL += 5
            if PROD_VALS['mode'] in env_content:
                SCORE_TOTAL += 5
            if PROD_VALS['node_tag'] in env_content or PROD_VALS['postgres_tag'] in env_content:
                SCORE_TOTAL += 5
            feedback.append("Production .env file created and verified.")
        except:
            feedback.append("Error parsing .env file.")
    else:
        feedback.append(".env.prod file not found.")

    # =========================================================
    # 3. Runtime Verification (40 points)
    # =========================================================
    
    # A. Web Port 80 Accessibility (15 pts)
    if result.get('http_status_80') == '200':
        SCORE_TOTAL += 15
        feedback.append("Web app accessible on production port 80.")
    elif result.get('http_status_3000') == '200':
        feedback.append("Web app running on default port 3000 (failed to switch to 80).")
    else:
        feedback.append("Web app not accessible.")

    # B. Database Version Check (15 pts)
    db_inspect = result.get('db_inspect', {})
    if db_inspect:
        config = db_inspect.get('Config', {})
        image_tag = config.get('Image', '')
        # Docker inspect Image field usually has "postgres:15"
        if f"postgres:{PROD_VALS['postgres_tag']}" in image_tag:
            SCORE_TOTAL += 15
            feedback.append(f"Database running correct version: {image_tag}")
        elif f"postgres:{DEFAULT_VALS['postgres_tag']}" in image_tag:
            feedback.append(f"Database still running dev version: {image_tag}")
        else:
            feedback.append(f"Database running unexpected version: {image_tag}")
    else:
        feedback.append("Database container not found.")

    # C. Secrets Check (Runtime Env) (10 pts)
    if db_inspect:
        env_vars = db_inspect.get('Config', {}).get('Env', [])
        found_pass = False
        for var in env_vars:
            if f"POSTGRES_PASSWORD={PROD_VALS['password']}" in var:
                found_pass = True
                break
        
        if found_pass:
            SCORE_TOTAL += 10
            feedback.append("Database running with production password.")
        else:
            feedback.append("Database not running with production password.")

    # Cap score
    SCORE_TOTAL = min(SCORE_TOTAL, MAX_SCORE)
    
    return {
        "passed": SCORE_TOTAL >= 70,
        "score": SCORE_TOTAL,
        "feedback": " ".join(feedback)
    }