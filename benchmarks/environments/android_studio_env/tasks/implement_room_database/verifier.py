#!/usr/bin/env python3
"""
Verifier for implement_room_database task.

The agent must add Room persistence to SunflowerApp by:
1. Adding Room dependencies to build.gradle.kts
2. Annotating Plant.kt as a Room @Entity with @PrimaryKey
3. Creating a PlantDao.kt with @Dao, @Query, @Insert annotations
4. Creating a PlantDatabase.kt extending RoomDatabase with @Database annotation
5. Updating PlantRepository.kt to reference the DAO
6. Getting the project to compile

Scoring (100 points total):
- Room dependencies in build.gradle.kts: 15 pts
- Plant.kt has @Entity and @PrimaryKey: 15 pts
- PlantDao.kt exists with @Dao, @Query, @Insert: 20 pts
- PlantDatabase.kt exists with @Database, RoomDatabase: 15 pts
- PlantRepository.kt uses DAO: 10 pts
- Project compiles (Gradle build): 25 pts

Pass threshold: 70/100
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _read_text(copy_from_env, path):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
    try:
        copy_from_env(path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except Exception as e:
        logger.debug("Could not read %s: %s", path, e)
        return ""
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def _read_json(copy_from_env, path):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def verify_implement_room_database(traj, env_info, task_info):
    """Verify Room database implementation in SunflowerApp."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/AndroidStudioProjects/SunflowerApp')
    pkg_path = metadata.get('package_path', 'com/google/samples/apps/sunflower')

    src_dir = f"{project_dir}/app/src/main/java/{pkg_path}"

    # Read files directly from VM
    plant_kt = _read_text(copy_from_env, f"{src_dir}/data/Plant.kt")
    repo_kt = _read_text(copy_from_env, f"{src_dir}/data/PlantRepository.kt")
    build_gradle = _read_text(copy_from_env, f"{project_dir}/app/build.gradle.kts")

    # DAO and Database might be in data/ subpackage or top package
    dao_kt = _read_text(copy_from_env, f"{src_dir}/data/PlantDao.kt")
    if not dao_kt:
        dao_kt = _read_text(copy_from_env, f"{src_dir}/PlantDao.kt")
    db_kt = _read_text(copy_from_env, f"{src_dir}/data/PlantDatabase.kt")
    if not db_kt:
        db_kt = _read_text(copy_from_env, f"{src_dir}/PlantDatabase.kt")
        if not db_kt:
            db_kt = _read_text(copy_from_env, f"{src_dir}/data/AppDatabase.kt")
            if not db_kt:
                db_kt = _read_text(copy_from_env, f"{src_dir}/AppDatabase.kt")

    # Fall back to export JSON
    result = _read_json(copy_from_env, "/tmp/task_result.json")
    if not plant_kt:
        plant_kt = result.get('plant_kt_content', '')
    if not repo_kt:
        repo_kt = result.get('repo_content', '')
    if not build_gradle:
        build_gradle = result.get('build_gradle_content', '')
    if not dao_kt:
        dao_kt = result.get('dao_content', '')
    if not db_kt:
        db_kt = result.get('db_content', '')

    score = 0
    feedback = []

    # GATE: If no files were changed at all, score 0
    any_change = (
        result.get('plant_kt_changed', False) or
        result.get('build_gradle_changed', False) or
        result.get('repo_changed', False) or
        result.get('dao_exists', False) or
        result.get('db_exists', False)
    )
    # Also check by content inspection
    has_entity = '@Entity' in plant_kt
    has_dao = '@Dao' in dao_kt
    has_room_dep = 'room' in build_gradle.lower()

    if not any_change and not has_entity and not has_dao and not has_room_dep:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No changes detected — no Room implementation found"
        }

    # ================================================================
    # Criterion 1: Room dependencies in build.gradle.kts (15 pts)
    # ================================================================
    try:
        has_room_runtime = bool(re.search(
            r'implementation\s*\(\s*"androidx\.room:room-(runtime|ktx):[^"]+"\s*\)',
            build_gradle
        ))
        has_room_compiler = bool(re.search(
            r'(kapt|ksp|annotationProcessor)\s*\(\s*"androidx\.room:room-compiler:[^"]+"\s*\)',
            build_gradle
        ))
        has_kapt_or_ksp = bool(re.search(
            r'id\s*\(\s*"(com\.google\.devtools\.ksp|org\.jetbrains\.kotlin\.kapt)"\s*\)',
            build_gradle
        ))

        if has_room_runtime and has_room_compiler:
            score += 15
            feedback.append("Room dependencies: complete (15/15)")
        elif has_room_runtime:
            score += 8
            feedback.append("Room dependencies: runtime found but compiler missing (8/15)")
        elif has_room_dep:
            score += 5
            feedback.append("Room dependencies: partial (5/15)")
        else:
            feedback.append("Room dependencies: not found (0/15)")
    except Exception as e:
        feedback.append(f"Room dependencies: error checking ({e}) (0/15)")

    # ================================================================
    # Criterion 2: Plant.kt has @Entity and @PrimaryKey (15 pts)
    # ================================================================
    try:
        has_entity_annotation = bool(re.search(r'@Entity', plant_kt))
        has_primary_key = bool(re.search(r'@PrimaryKey', plant_kt))
        has_room_import = bool(re.search(r'import\s+androidx\.room\.', plant_kt))

        if has_entity_annotation and has_primary_key:
            score += 15
            feedback.append("Plant.kt Entity: @Entity + @PrimaryKey (15/15)")
        elif has_entity_annotation:
            score += 8
            feedback.append("Plant.kt Entity: @Entity but no @PrimaryKey (8/15)")
        elif has_room_import:
            score += 3
            feedback.append("Plant.kt Entity: Room imports but no annotations (3/15)")
        else:
            feedback.append("Plant.kt Entity: no Room annotations (0/15)")
    except Exception as e:
        feedback.append(f"Plant.kt Entity: error ({e}) (0/15)")

    # ================================================================
    # Criterion 3: PlantDao.kt with @Dao, @Query, @Insert (20 pts)
    # ================================================================
    try:
        if dao_kt:
            has_dao_annotation = bool(re.search(r'@Dao', dao_kt))
            has_query = bool(re.search(r'@Query', dao_kt))
            has_insert = bool(re.search(r'@Insert', dao_kt))
            has_delete = bool(re.search(r'@Delete', dao_kt))
            is_interface = bool(re.search(r'interface\s+\w+Dao', dao_kt, re.IGNORECASE))

            dao_score = 0
            if has_dao_annotation:
                dao_score += 5
            if is_interface:
                dao_score += 3
            if has_query:
                dao_score += 5
            if has_insert:
                dao_score += 4
            if has_delete:
                dao_score += 3

            score += min(dao_score, 20)
            parts = []
            if has_dao_annotation: parts.append("@Dao")
            if has_query: parts.append("@Query")
            if has_insert: parts.append("@Insert")
            if has_delete: parts.append("@Delete")
            feedback.append(f"PlantDao: {', '.join(parts)} ({min(dao_score, 20)}/20)")
        else:
            feedback.append("PlantDao: file not found (0/20)")
    except Exception as e:
        feedback.append(f"PlantDao: error ({e}) (0/20)")

    # ================================================================
    # Criterion 4: PlantDatabase.kt with @Database, RoomDatabase (15 pts)
    # ================================================================
    try:
        if db_kt:
            has_db_annotation = bool(re.search(r'@Database', db_kt))
            extends_room = bool(re.search(r'RoomDatabase', db_kt))
            has_entities_param = bool(re.search(r'entities\s*=', db_kt))
            has_abstract_dao = bool(re.search(r'abstract\s+fun\s+\w+[Dd]ao\s*\(', db_kt))

            db_score = 0
            if has_db_annotation: db_score += 5
            if extends_room: db_score += 4
            if has_entities_param: db_score += 3
            if has_abstract_dao: db_score += 3

            score += min(db_score, 15)
            feedback.append(f"PlantDatabase: score {min(db_score, 15)}/15")
        else:
            feedback.append("PlantDatabase: file not found (0/15)")
    except Exception as e:
        feedback.append(f"PlantDatabase: error ({e}) (0/15)")

    # ================================================================
    # Criterion 5: PlantRepository.kt uses DAO (10 pts)
    # ================================================================
    try:
        has_dao_ref = bool(re.search(r'[Dd]ao', repo_kt))
        has_database_ref = bool(re.search(r'[Dd]atabase', repo_kt))
        still_mutable_list = bool(re.search(r'mutableListOf\s*<\s*Plant\s*>\s*\(\s*\)', repo_kt))

        if has_dao_ref and not still_mutable_list:
            score += 10
            feedback.append("PlantRepository: uses DAO (10/10)")
        elif has_dao_ref or has_database_ref:
            score += 5
            feedback.append("PlantRepository: partially updated (5/10)")
        else:
            feedback.append("PlantRepository: still uses in-memory list (0/10)")
    except Exception as e:
        feedback.append(f"PlantRepository: error ({e}) (0/10)")

    # ================================================================
    # Criterion 6: Project compiles (25 pts)
    # ================================================================
    try:
        build_success = result.get('build_success', False)
        if not build_success:
            gradle_log = _read_text(copy_from_env, "/tmp/gradle_output.log")
            if gradle_log and "BUILD SUCCESSFUL" in gradle_log:
                build_success = True

        if build_success:
            score += 25
            feedback.append("Build: succeeded (25/25)")
        else:
            feedback.append("Build: failed (0/25)")
    except Exception as e:
        feedback.append(f"Build: error ({e}) (0/25)")

    passed = score >= 70

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": " | ".join(feedback)
    }
