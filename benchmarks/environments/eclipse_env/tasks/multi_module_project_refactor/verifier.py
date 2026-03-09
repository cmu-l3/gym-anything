import json
import os
import logging
import tempfile

logger = logging.getLogger(__name__)


def verify_multi_module_project_refactor(traj, env_info, task_info):
    """
    Verify the multi-module Maven project refactoring task.

    Scoring breakdown (100 pts total, pass >= 70):
    - Parent POM has <modules> section listing 3+ modules (20 pts)
    - All three child module pom.xml files exist (15 pts)
    - Model classes in ecommerce-api (15 pts)
    - Repository classes in ecommerce-persistence (15 pts)
    - Service classes in ecommerce-service (15 pts)
    - Inter-module dependencies declared correctly (10 pts)
    - Build passes with mvn clean install (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')

    score = 0
    feedback_parts = []
    subscores = {}

    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env('/tmp/multimodule_result.json', tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        logger.warning(f"Could not read result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result: {e}",
            "subscores": {}
        }

    # --- Criterion 1: Parent POM with modules (20 pts) ---
    parent_pom = result.get('parent_pom_exists', False)
    has_modules = result.get('parent_has_modules', False)
    module_count = int(result.get('module_count', 0))

    if parent_pom and has_modules and module_count >= 3:
        score += 20
        subscores['parent_pom_modules'] = True
        feedback_parts.append(f"Parent POM has {module_count} modules declared (20/20)")
    elif parent_pom and module_count >= 1:
        score += 8
        subscores['parent_pom_modules'] = 'partial'
        feedback_parts.append(f"Parent POM exists but only {module_count}/3 modules (8/20)")
    else:
        subscores['parent_pom_modules'] = False
        feedback_parts.append("No parent POM found at /home/ga/ecommerce-refactored/pom.xml (0/20)")

    # --- Criterion 2: Child module pom.xml files (15 pts) ---
    api_pom = result.get('api_pom', False)
    pers_pom = result.get('persistence_pom', False)
    svc_pom = result.get('service_pom', False)
    child_poms = sum([api_pom, pers_pom, svc_pom])

    if child_poms == 3:
        score += 15
        subscores['child_poms'] = True
        feedback_parts.append("All 3 child module pom.xml files exist (15/15)")
    elif child_poms >= 1:
        partial = 5 * child_poms
        score += partial
        subscores['child_poms'] = 'partial'
        feedback_parts.append(f"{child_poms}/3 child module pom.xml files exist ({partial}/15)")
    else:
        subscores['child_poms'] = False
        feedback_parts.append("No child module pom.xml files found (0/15)")

    # --- Criterion 3: Model classes in ecommerce-api (15 pts) ---
    api_product = int(result.get('api_product_class', 0))
    api_customer = int(result.get('api_customer_class', 0))
    api_order = int(result.get('api_order_class', 0))
    api_classes = sum([api_product > 0, api_customer > 0, api_order > 0])

    if api_classes >= 3:
        score += 15
        subscores['api_classes'] = True
        feedback_parts.append("Model classes in ecommerce-api (15/15)")
    elif api_classes >= 1:
        partial = 5 * api_classes
        score += partial
        subscores['api_classes'] = 'partial'
        feedback_parts.append(f"{api_classes}/3 model classes in ecommerce-api ({partial}/15)")
    else:
        subscores['api_classes'] = False
        feedback_parts.append("No model classes found in ecommerce-api (0/15)")

    # --- Criterion 4: Repository classes in ecommerce-persistence (15 pts) ---
    pers_prod = int(result.get('persistence_product_repo', 0))
    pers_cust = int(result.get('persistence_customer_repo', 0))
    pers_ord = int(result.get('persistence_order_repo', 0))
    pers_classes = sum([pers_prod > 0, pers_cust > 0, pers_ord > 0])

    if pers_classes >= 3:
        score += 15
        subscores['persistence_classes'] = True
        feedback_parts.append("Repository classes in ecommerce-persistence (15/15)")
    elif pers_classes >= 1:
        partial = 5 * pers_classes
        score += partial
        subscores['persistence_classes'] = 'partial'
        feedback_parts.append(f"{pers_classes}/3 repo classes in ecommerce-persistence ({partial}/15)")
    else:
        subscores['persistence_classes'] = False
        feedback_parts.append("No repository classes in ecommerce-persistence (0/15)")

    # --- Criterion 5: Service classes in ecommerce-service (15 pts) ---
    svc_prod = int(result.get('service_product_svc', 0))
    svc_cust = int(result.get('service_customer_svc', 0))
    svc_ord = int(result.get('service_order_svc', 0))
    svc_classes = sum([svc_prod > 0, svc_cust > 0, svc_ord > 0])

    if svc_classes >= 3:
        score += 15
        subscores['service_classes'] = True
        feedback_parts.append("Service classes in ecommerce-service (15/15)")
    elif svc_classes >= 1:
        partial = 5 * svc_classes
        score += partial
        subscores['service_classes'] = 'partial'
        feedback_parts.append(f"{svc_classes}/3 service classes in ecommerce-service ({partial}/15)")
    else:
        subscores['service_classes'] = False
        feedback_parts.append("No service classes in ecommerce-service (0/15)")

    # --- Criterion 6: Inter-module dependencies (10 pts) ---
    pers_dep = result.get('persistence_depends_api', False)
    svc_dep_api = result.get('service_depends_api', False)
    svc_dep_pers = result.get('service_depends_persistence', False)
    dep_count = sum([pers_dep, svc_dep_api, svc_dep_pers])

    if dep_count >= 3:
        score += 10
        subscores['inter_module_deps'] = True
        feedback_parts.append("Inter-module dependencies declared correctly (10/10)")
    elif dep_count >= 1:
        partial = 3 * dep_count
        score += partial
        subscores['inter_module_deps'] = 'partial'
        feedback_parts.append(f"{dep_count}/3 inter-module dependencies correct ({partial}/10)")
    else:
        subscores['inter_module_deps'] = False
        feedback_parts.append("No inter-module dependencies found (0/10)")

    # --- Criterion 7: Build passes (10 pts) ---
    build_success = result.get('build_success', False)
    if build_success:
        score += 10
        subscores['build_passes'] = True
        feedback_parts.append("Build passes: mvn clean install succeeded (10/10)")
    else:
        subscores['build_passes'] = False
        feedback_parts.append("Build FAILED: mvn clean install returned non-zero (0/10)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
