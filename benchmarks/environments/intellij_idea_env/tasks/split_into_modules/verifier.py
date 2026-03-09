#!/usr/bin/env python3
"""
Verifier for split_into_modules task.

Criteria:
1.  Parent POM exists and defines modules (10 pts)
2.  Module 'petclinic-model' exists, valid POM, correct sources (15 pts)
3.  Module 'petclinic-service' exists, valid POM, depends on model (15 pts)
4.  Module 'petclinic-app' exists, valid POM, depends on service+model (15 pts)
5.  Original root source directory is empty/removed (10 pts)
6.  Maven build (compile+package) succeeds for the whole project (35 pts)
"""

import json
import tempfile
import os
import re
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_split_into_modules(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    pom_contents = result.get("pom_contents", {})
    modules_found = result.get("modules_found", {})
    jars_found = result.get("jars_found", {})
    
    # --- Helper to parse XML ---
    def get_xml_root(content):
        try:
            return ET.fromstring(content)
        except ET.ParseError:
            return None
            
    # Namespace map for Maven POMs
    ns = {'m': 'http://maven.apache.org/POM/4.0.0'}

    # --- Criterion 1: Parent POM (10 pts) ---
    parent_pom = pom_contents.get("parent", "")
    parent_root = get_xml_root(parent_pom)
    
    if parent_root is not None:
        packaging = parent_root.find("m:packaging", ns)
        modules = parent_root.find("m:modules", ns)
        
        # Check packaging is pom
        is_pom_pkg = packaging is not None and packaging.text.strip() == "pom"
        
        # Check modules list
        module_names = []
        if modules is not None:
            for mod in modules.findall("m:module", ns):
                module_names.append(mod.text.strip())
        
        has_all_modules = all(m in module_names for m in ["petclinic-model", "petclinic-service", "petclinic-app"])
        
        if is_pom_pkg and has_all_modules:
            score += 10
            feedback_parts.append("Parent POM is valid (packaging=pom, modules defined)")
        else:
            feedback_parts.append(f"Parent POM issues: Packaging='{packaging.text if packaging is not None else 'None'}', Modules={module_names}")
    else:
        feedback_parts.append("Parent POM invalid or missing")

    # --- Criterion 2: Model Module (15 pts) ---
    # We check existence and POM validity (no dependencies required)
    if modules_found.get("model"):
        model_pom = pom_contents.get("model", "")
        model_root = get_xml_root(model_pom)
        if model_root is not None:
            # Check artifactId
            aid = model_root.find("m:artifactId", ns)
            if aid is not None and aid.text.strip() == "petclinic-model":
                score += 15
                feedback_parts.append("Model module POM valid")
            else:
                score += 5
                feedback_parts.append("Model module exists but artifactId incorrect")
        else:
            score += 5
            feedback_parts.append("Model module exists but POM invalid")
    else:
        feedback_parts.append("Model module missing")

    # --- Criterion 3: Service Module (15 pts) ---
    # Must depend on petclinic-model
    if modules_found.get("service"):
        service_pom = pom_contents.get("service", "")
        service_root = get_xml_root(service_pom)
        if service_root is not None:
            deps = service_root.find("m:dependencies", ns)
            has_model_dep = False
            if deps is not None:
                for dep in deps.findall("m:dependency", ns):
                    daid = dep.find("m:artifactId", ns)
                    if daid is not None and daid.text.strip() == "petclinic-model":
                        has_model_dep = True
                        break
            
            if has_model_dep:
                score += 15
                feedback_parts.append("Service module configured correctly")
            else:
                score += 5
                feedback_parts.append("Service module exists but missing dependency on model")
        else:
            score += 5
            feedback_parts.append("Service module exists but POM invalid")
    else:
        feedback_parts.append("Service module missing")

    # --- Criterion 4: App Module (15 pts) ---
    # Must depend on petclinic-service (and transitively or explicitly model)
    if modules_found.get("app"):
        app_pom = pom_contents.get("app", "")
        app_root = get_xml_root(app_pom)
        if app_root is not None:
            deps = app_root.find("m:dependencies", ns)
            has_service_dep = False
            if deps is not None:
                for dep in deps.findall("m:dependency", ns):
                    daid = dep.find("m:artifactId", ns)
                    if daid is not None and daid.text.strip() == "petclinic-service":
                        has_service_dep = True
                        break
            
            if has_service_dep:
                score += 15
                feedback_parts.append("App module configured correctly")
            else:
                score += 5
                feedback_parts.append("App module exists but missing dependency on service")
        else:
            score += 5
            feedback_parts.append("App module exists but POM invalid")
    else:
        feedback_parts.append("App module missing")

    # --- Criterion 5: Root clean (10 pts) ---
    if result.get("root_src_clean", False):
        score += 10
        feedback_parts.append("Root source directory cleaned")
    else:
        feedback_parts.append("Root source directory still contains files")

    # --- Criterion 6: Build Success (35 pts) ---
    exit_code = result.get("mvn_exit_code", -1)
    if exit_code == 0:
        # Extra verification: check JARs were actually produced
        # This prevents cases where "mvn package" runs but does nothing because modules aren't linked
        jars = result.get("jars_found", {})
        if jars.get("model") and jars.get("service") and jars.get("app"):
            score += 35
            feedback_parts.append("Maven build successful and JARs generated")
        else:
            score += 20
            feedback_parts.append("Maven build reported success, but JARs not found (Check reactor configuration)")
    else:
        feedback_parts.append("Maven build failed")

    # --- Final calculation ---
    # Pass if score >= 60 AND build succeeded
    passed = (score >= 60) and (exit_code == 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }