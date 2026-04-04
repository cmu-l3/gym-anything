import json
import os
import logging
import tempfile

logger = logging.getLogger(__name__)


def verify_java8_to_java17_migration(traj, env_info, task_info):
    """
    Verify the Java 8 to Java 17 migration task.

    Scoring breakdown (100 pts total, pass >= 65):
    - Date/Calendar removed from main source (25 pts)
    - java.time API used (20 pts)
    - Raw types replaced with generics (20 pts)
    - StringBuffer replaced with StringBuilder (15 pts)
    - pom.xml targets Java 17 (10 pts)
    - Build + tests pass (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')

    score = 0
    feedback_parts = []
    subscores = {}

    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env('/tmp/java17_migration_result.json', tmp_path)
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

    # --- Criterion 1: Date/Calendar removed (25 pts) ---
    date_imports = int(result.get('date_import_count', 99))
    date_usage = int(result.get('date_usage_count', 99))
    initial_date = int(result.get('initial_date_count', 0))

    # Partial credit for reducing (but not eliminating) Date usage
    if date_imports == 0 and date_usage == 0:
        score += 25
        subscores['date_removed'] = True
        feedback_parts.append("All java.util.Date/Calendar removed (25/25)")
    elif date_usage < initial_date / 2:
        score += 12
        subscores['date_removed'] = 'partial'
        feedback_parts.append(f"Partially removed Date/Calendar: {date_usage} usages remain (12/25)")
    else:
        subscores['date_removed'] = False
        feedback_parts.append(f"Date/Calendar NOT removed: {date_usage} usages remain (0/25)")

    # --- Criterion 2: java.time API used (20 pts) ---
    localdate_count = int(result.get('localdate_count', 0))
    period_count = int(result.get('period_count', 0))
    formatter_count = int(result.get('datetimeformatter_count', 0))

    time_api_score = 0
    if localdate_count >= 3:
        time_api_score += 10
    elif localdate_count >= 1:
        time_api_score += 5
    if period_count >= 1:
        time_api_score += 5
    if formatter_count >= 1:
        time_api_score += 5

    score += time_api_score
    if time_api_score >= 15:
        subscores['java_time_api'] = True
        feedback_parts.append(f"java.time API fully used: LocalDate({localdate_count}) Period({period_count}) Formatter({formatter_count}) ({time_api_score}/20)")
    elif time_api_score >= 5:
        subscores['java_time_api'] = 'partial'
        feedback_parts.append(f"java.time partially used: LocalDate({localdate_count}) ({time_api_score}/20)")
    else:
        subscores['java_time_api'] = False
        feedback_parts.append(f"java.time NOT used ({time_api_score}/20)")

    # --- Criterion 3: Raw types replaced (20 pts) ---
    raw_list = int(result.get('raw_list_count', 99))
    generic_map = int(result.get('generic_map_count', 0))
    generic_list = int(result.get('generic_list_count', 0))

    if raw_list == 0 and generic_map >= 2 and generic_list >= 2:
        score += 20
        subscores['generics_added'] = True
        feedback_parts.append(f"Raw types replaced with generics (20/20)")
    elif generic_map >= 1 or generic_list >= 2:
        score += 10
        subscores['generics_added'] = 'partial'
        feedback_parts.append(f"Partial generics: Map<>({generic_map}) List<>({generic_list}) (10/20)")
    else:
        subscores['generics_added'] = False
        feedback_parts.append(f"Raw types NOT replaced with generics (0/20)")

    # --- Criterion 4: StringBuffer → StringBuilder (15 pts) ---
    sb_count = int(result.get('stringbuffer_count', 99))
    sbuilder_count = int(result.get('stringbuilder_count', 0))
    initial_sb = int(result.get('initial_stringbuffer_count', 0))

    if sb_count == 0 and sbuilder_count >= initial_sb:
        score += 15
        subscores['stringbuffer_replaced'] = True
        feedback_parts.append(f"All StringBuffer replaced with StringBuilder (15/15)")
    elif sb_count < initial_sb and sbuilder_count >= 1:
        score += 7
        subscores['stringbuffer_replaced'] = 'partial'
        feedback_parts.append(f"Partially replaced StringBuffer ({sb_count} remain) (7/15)")
    else:
        subscores['stringbuffer_replaced'] = False
        feedback_parts.append(f"StringBuffer NOT replaced ({sb_count} still present) (0/15)")

    # --- Criterion 5: pom.xml Java 17 (10 pts) ---
    pom_17 = int(result.get('pom_source_17', 0)) > 0 and int(result.get('pom_target_17', 0)) > 0
    if pom_17:
        score += 10
        subscores['pom_java17'] = True
        feedback_parts.append("pom.xml updated to Java 17 (10/10)")
    else:
        subscores['pom_java17'] = False
        feedback_parts.append("pom.xml still targets Java 8, not 17 (0/10)")

    # --- Criterion 6: Build passes (10 pts) ---
    # Only award build points if at least one migration was applied
    # (prevents awarding build credit for an unchanged, already-passing legacy build)
    any_migration_applied = (
        subscores.get('date_removed') not in (False, None) or
        subscores.get('generics_added') not in (False, None) or
        subscores.get('stringbuffer_replaced') not in (False, None) or
        subscores.get('pom_java17') not in (False, None)
    )
    build_success = result.get('build_success', False)
    if build_success and any_migration_applied:
        score += 10
        subscores['build_passes'] = True
        feedback_parts.append("Build passes: mvn clean test succeeded (10/10)")
    elif build_success and not any_migration_applied:
        subscores['build_passes'] = False
        feedback_parts.append("Build passes but no migration applied — build credit requires changes (0/10)")
    else:
        subscores['build_passes'] = False
        feedback_parts.append("Build FAILED: mvn clean test returned non-zero (0/10)")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
