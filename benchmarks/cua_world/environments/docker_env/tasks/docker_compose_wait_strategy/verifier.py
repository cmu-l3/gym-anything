#!/usr/bin/env python3
import json
import base64
import os
import logging
from typing import Dict, Any

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_compose_wait_strategy(traj, env_info, task_info):
    """
    Verifies that the Docker Compose stack is configured with correct
    startup dependencies and healthchecks.
    """
    # 1. Load result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    max_score = 100

    # --- Static Analysis (Config Check) ---
    try:
        config_b64 = result.get('compose_config_b64', '')
        if config_b64:
            config_str = base64.b64decode(config_b64).decode('utf-8')
            config = json.loads(config_str)
            services = config.get('services', {})
            
            # 1. DB Healthcheck (20 pts)
            db_svc = services.get('db', {})
            healthcheck = db_svc.get('healthcheck', {})
            test_cmd = healthcheck.get('test', [])
            
            # Docker Compose parsed config usually makes test a list: ["CMD-SHELL", "pg_isready..."]
            # or just a list of strings if defined as array
            test_cmd_str = str(test_cmd).lower()
            
            if 'pg_isready' in test_cmd_str:
                score += 20
                feedback.append("✅ DB healthcheck found.")
            else:
                feedback.append("❌ DB healthcheck missing or incorrect (expected 'pg_isready').")

            # 2. Seeder Dependency (25 pts)
            seeder_svc = services.get('seeder', {})
            seeder_deps = seeder_svc.get('depends_on', {})
            
            # depends_on can be list or dict in yaml, but 'docker compose config' usually normalizes to dict
            if isinstance(seeder_deps, dict) and 'db' in seeder_deps:
                condition = seeder_deps['db'].get('condition', '')
                if condition == 'service_healthy':
                    score += 25
                    feedback.append("✅ Seeder waits for DB to be healthy.")
                else:
                    feedback.append(f"❌ Seeder depends on DB but condition is '{condition}' (expected 'service_healthy').")
            else:
                feedback.append("❌ Seeder does not depend on DB.")

            # 3. Backend Dependency (25 pts)
            backend_svc = services.get('backend', {})
            backend_deps = backend_svc.get('depends_on', {})
            
            if isinstance(backend_deps, dict) and 'seeder' in backend_deps:
                condition = backend_deps['seeder'].get('condition', '')
                if condition == 'service_completed_successfully':
                    score += 25
                    feedback.append("✅ Backend waits for Seeder completion.")
                else:
                    feedback.append(f"❌ Backend depends on Seeder but condition is '{condition}' (expected 'service_completed_successfully').")
            else:
                feedback.append("❌ Backend does not depend on Seeder.")
                
        else:
            feedback.append("❌ Could not parse Docker Compose configuration.")
    except Exception as e:
        feedback.append(f"❌ Error analyzing configuration: {str(e)}")

    # --- Dynamic Analysis (Runtime Check) ---
    
    # 4. Stack Starts Cleanly & Functionality (15 pts)
    # Check if API is 200 OK
    api_code = result.get('api_status_code', 0)
    seeder_exit = result.get('seeder_exit_code', -1)
    
    if api_code == 200 and seeder_exit == 0:
        score += 15
        feedback.append("✅ Stack started successfully and API is healthy.")
    else:
        feedback.append(f"❌ Runtime check failed: API status {api_code} (expected 200), Seeder exit {seeder_exit} (expected 0).")

    # 5. Temporal Verification (15 pts)
    # Backend start time should be >= Seeder finish time
    seeder_finish = result.get('seeder_finish_epoch', 0)
    backend_start = result.get('backend_start_epoch', 0)
    
    if seeder_finish > 0 and backend_start > 0:
        # Allow small buffer? Theoretically backend start should be strictly after seeder finish
        # depends_on: service_completed_successfully guarantees this.
        if backend_start >= seeder_finish:
            score += 15
            feedback.append("✅ Execution order verified (Backend started after Seeder finished).")
        else:
            feedback.append(f"❌ Execution order violation: Backend started at {backend_start}, Seeder finished at {seeder_finish}.")
    elif score >= 70: 
        # If we passed static checks but missed timestamps (e.g. fast execution or clock skew),
        # we might be lenient if config is perfect, but better to be strict.
        # If config is correct, this usually implicitly passes.
        # If timestamps are 0, it means containers didn't run properly.
        feedback.append("❌ Could not verify timestamps (containers might have failed).")

    # Final result
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }