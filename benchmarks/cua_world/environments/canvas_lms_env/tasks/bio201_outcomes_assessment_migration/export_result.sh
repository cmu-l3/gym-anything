#!/bin/bash
set -euo pipefail

TASK_NAME="bio201_outcomes_assessment_migration"

echo "=== Exporting ${TASK_NAME} ==="
source /workspace/scripts/task_utils.sh

take_screenshot "/tmp/${TASK_NAME}_end.png"

COURSE_ID=$(cat "/tmp/${TASK_NAME}_course_id" 2>/dev/null || echo "")
START_TS=$(cat "/tmp/${TASK_NAME}_start_ts" 2>/dev/null || echo "0")

# Defaults
FEATURE_OUTCOME_GB="off"
FEATURE_STUDENT_GB="off"
OUTCOME_COUNT=0
OUTCOME_INQUIRY_EXISTS=false
OUTCOME_INQUIRY_MASTERY=""
OUTCOME_DESIGN_MASTERY=""
OUTCOME_COMM_MASTERY=""
RUBRIC_COUNT=0
PAPER_RUBRIC_CRITERIA=0
PAPER_RUBRIC_POINTS=0
PAPER_RUBRIC_GRADING=false
ESSAY_RUBRIC_CRITERIA=0
ESSAY_RUBRIC_POINTS=0
ESSAY_RUBRIC_GRADING=false
WEIGHT_WRITTEN=""
WEIGHT_LAB=""
WEIGHT_QUIZ=""
WEIGHT_PART=""
ECOLOGY_GROUP=""
LATE_DEDUCTION=""
LATE_MINIMUM=""
LATE_ENABLED=""
MOD4_PREREQ_NAME=""

if [ -n "${COURSE_ID}" ]; then

  # ── Feature Flags ──
  FEATURE_OUTCOME_GB=$(canvas_query "SELECT COALESCE(state, 'off') FROM feature_flags WHERE context_id=${COURSE_ID} AND context_type='Course' AND feature='outcome_gradebook' LIMIT 1" 2>/dev/null | tr -d '[:space:]' || echo "off")
  FEATURE_STUDENT_GB=$(canvas_query "SELECT COALESCE(state, 'off') FROM feature_flags WHERE context_id=${COURSE_ID} AND context_type='Course' AND feature='student_outcome_gradebook' LIMIT 1" 2>/dev/null | tr -d '[:space:]' || echo "off")

  # ── Learning Outcomes (mastery_points is in the serialized 'data' YAML column) ──
  OUTCOME_COUNT=$(canvas_query "SELECT COUNT(*) FROM learning_outcomes WHERE context_type='Course' AND context_id=${COURSE_ID} AND workflow_state='active'" | tr -d '[:space:]')

  # Extract mastery_points from the YAML data column using substring matching
  OUTCOME_INQUIRY_MASTERY=$(canvas_query "SELECT substring(data from 'mastery_points: ([0-9.]+)') FROM learning_outcomes WHERE context_type='Course' AND context_id=${COURSE_ID} AND LOWER(TRIM(short_description))='scientific inquiry' AND workflow_state='active' LIMIT 1" 2>/dev/null | tr -d '[:space:]' || echo "")
  [ -n "${OUTCOME_INQUIRY_MASTERY}" ] && OUTCOME_INQUIRY_EXISTS=true

  OUTCOME_DESIGN_MASTERY=$(canvas_query "SELECT substring(data from 'mastery_points: ([0-9.]+)') FROM learning_outcomes WHERE context_type='Course' AND context_id=${COURSE_ID} AND LOWER(TRIM(short_description))='experimental design' AND workflow_state='active' LIMIT 1" 2>/dev/null | tr -d '[:space:]' || echo "")

  OUTCOME_COMM_MASTERY=$(canvas_query "SELECT substring(data from 'mastery_points: ([0-9.]+)') FROM learning_outcomes WHERE context_type='Course' AND context_id=${COURSE_ID} AND LOWER(TRIM(short_description))='scientific communication' AND workflow_state='active' LIMIT 1" 2>/dev/null | tr -d '[:space:]' || echo "")

  # ── Rubrics ──
  RUBRIC_COUNT=$(canvas_query "SELECT COUNT(*) FROM rubrics WHERE context_id=${COURSE_ID} AND context_type='Course'" | tr -d '[:space:]')

  # Final Research Paper rubric
  PAPER_ID=$(canvas_query "SELECT id FROM assignments WHERE context_id=${COURSE_ID} AND context_type='Course' AND LOWER(TRIM(title))='final research paper' AND workflow_state='published' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')
  if [ -n "${PAPER_ID}" ]; then
    PAPER_RA=$(canvas_query "SELECT rubric_id FROM rubric_associations WHERE association_id=${PAPER_ID} AND association_type='Assignment' AND purpose='grading' LIMIT 1" 2>/dev/null | tr -d '[:space:]' || echo "")
    if [ -n "${PAPER_RA}" ]; then
      PAPER_RUBRIC_GRADING=true
      PAPER_RUBRIC_CRITERIA=$(canvas_query "SELECT ROUND((LENGTH(data::text) - LENGTH(REPLACE(data::text,'\"criterion_use_range\"','')))/LENGTH('\"criterion_use_range\"')::numeric)::int FROM rubrics WHERE id=${PAPER_RA}" 2>/dev/null | tr -d '[:space:]' || echo "0")
      PAPER_RUBRIC_POINTS=$(canvas_query "SELECT COALESCE(points_possible, 0) FROM rubrics WHERE id=${PAPER_RA}" 2>/dev/null | tr -d '[:space:]' || echo "0")
    fi
  fi

  # Midterm Essay rubric
  ESSAY_ID=$(canvas_query "SELECT id FROM assignments WHERE context_id=${COURSE_ID} AND context_type='Course' AND LOWER(TRIM(title))='midterm essay' AND workflow_state='published' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')
  if [ -n "${ESSAY_ID}" ]; then
    ESSAY_RA=$(canvas_query "SELECT rubric_id FROM rubric_associations WHERE association_id=${ESSAY_ID} AND association_type='Assignment' AND purpose='grading' LIMIT 1" 2>/dev/null | tr -d '[:space:]' || echo "")
    if [ -n "${ESSAY_RA}" ]; then
      ESSAY_RUBRIC_GRADING=true
      ESSAY_RUBRIC_CRITERIA=$(canvas_query "SELECT ROUND((LENGTH(data::text) - LENGTH(REPLACE(data::text,'\"criterion_use_range\"','')))/LENGTH('\"criterion_use_range\"')::numeric)::int FROM rubrics WHERE id=${ESSAY_RA}" 2>/dev/null | tr -d '[:space:]' || echo "0")
      ESSAY_RUBRIC_POINTS=$(canvas_query "SELECT COALESCE(points_possible, 0) FROM rubrics WHERE id=${ESSAY_RA}" 2>/dev/null | tr -d '[:space:]' || echo "0")
    fi
  fi

  # ── Assignment Group Weights (assignment_groups uses context_id, not course_id) ──
  WEIGHT_WRITTEN=$(canvas_query "SELECT group_weight FROM assignment_groups WHERE context_id=${COURSE_ID} AND context_type='Course' AND LOWER(TRIM(name))='written assignments' AND workflow_state NOT IN ('deleted') LIMIT 1" 2>/dev/null | tr -d '[:space:]' || echo "")
  WEIGHT_LAB=$(canvas_query "SELECT group_weight FROM assignment_groups WHERE context_id=${COURSE_ID} AND context_type='Course' AND LOWER(TRIM(name))='laboratory reports' AND workflow_state NOT IN ('deleted') LIMIT 1" 2>/dev/null | tr -d '[:space:]' || echo "")
  WEIGHT_QUIZ=$(canvas_query "SELECT group_weight FROM assignment_groups WHERE context_id=${COURSE_ID} AND context_type='Course' AND LOWER(TRIM(name))='quizzes & exams' AND workflow_state NOT IN ('deleted') LIMIT 1" 2>/dev/null | tr -d '[:space:]' || echo "")
  WEIGHT_PART=$(canvas_query "SELECT group_weight FROM assignment_groups WHERE context_id=${COURSE_ID} AND context_type='Course' AND LOWER(TRIM(name))='participation' AND workflow_state NOT IN ('deleted') LIMIT 1" 2>/dev/null | tr -d '[:space:]' || echo "")

  # ── Ecology Field Report group ──
  ECOLOGY_GROUP=$(canvas_query "SELECT ag.name FROM assignments a JOIN assignment_groups ag ON a.assignment_group_id=ag.id WHERE a.context_id=${COURSE_ID} AND a.context_type='Course' AND LOWER(TRIM(a.title))='ecology field report' AND a.workflow_state='published' LIMIT 1" 2>/dev/null | tr -d '[:space:]' || echo "")

  # ── Late Policy ──
  LATE_DEDUCTION=$(canvas_query "SELECT COALESCE(late_submission_deduction::text, '') FROM late_policies WHERE course_id=${COURSE_ID} LIMIT 1" 2>/dev/null | tr -d '[:space:]' || echo "")
  LATE_MINIMUM=$(canvas_query "SELECT COALESCE(late_submission_minimum_percent::text, '') FROM late_policies WHERE course_id=${COURSE_ID} LIMIT 1" 2>/dev/null | tr -d '[:space:]' || echo "")
  LATE_ENABLED=$(canvas_query "SELECT COALESCE(late_submission_deduction_enabled::text, '') FROM late_policies WHERE course_id=${COURSE_ID} LIMIT 1" 2>/dev/null | tr -d '[:space:]' || echo "")

  # ── Module 4 prerequisite ──
  MOD4_ID=$(canvas_query "SELECT id FROM context_modules WHERE context_id=${COURSE_ID} AND context_type='Course' AND name LIKE 'Week 4%' AND workflow_state='active' LIMIT 1" 2>/dev/null | tr -d '[:space:]' || echo "")
  if [ -n "${MOD4_ID}" ]; then
    # Prerequisites are serialized in the prerequisites column; extract via Rails or parse
    MOD4_PREREQ_NAME=$(canvas_query "SELECT prerequisites FROM context_modules WHERE id=${MOD4_ID}" 2>/dev/null | grep -oP 'name: [^\n,}]+' | head -1 | sed 's/name: //' || echo "")
    # Fallback: try to get the prerequisite module name
    if [ -z "${MOD4_PREREQ_NAME}" ]; then
      MOD4_PREREQ_NAME="unknown"
    fi
  fi

fi

# Convert bash booleans to Python booleans
PY_INQUIRY_EXISTS="False"
[ "${OUTCOME_INQUIRY_EXISTS}" = "true" ] && PY_INQUIRY_EXISTS="True"
PY_PAPER_GRADING="False"
[ "${PAPER_RUBRIC_GRADING}" = "true" ] && PY_PAPER_GRADING="True"
PY_ESSAY_GRADING="False"
[ "${ESSAY_RUBRIC_GRADING}" = "true" ] && PY_ESSAY_GRADING="True"

# ── Write result JSON ──
TEMP_JSON=$(mktemp "/tmp/${TASK_NAME}_result.XXXXXX.json")
python3 -c "
import json
result = {
    'task_name': '${TASK_NAME}',
    'course_id': '${COURSE_ID}',
    'start_ts': int('${START_TS}' or '0'),
    'feature_outcome_gradebook': '${FEATURE_OUTCOME_GB}',
    'feature_student_gradebook': '${FEATURE_STUDENT_GB}',
    'outcome_count': int('${OUTCOME_COUNT}' or '0'),
    'outcome_inquiry_exists': ${PY_INQUIRY_EXISTS},
    'outcome_inquiry_mastery': '${OUTCOME_INQUIRY_MASTERY}',
    'outcome_design_mastery': '${OUTCOME_DESIGN_MASTERY}',
    'outcome_comm_mastery': '${OUTCOME_COMM_MASTERY}',
    'rubric_count': int('${RUBRIC_COUNT}' or '0'),
    'paper_rubric_criteria': int('${PAPER_RUBRIC_CRITERIA}' or '0'),
    'paper_rubric_points': '${PAPER_RUBRIC_POINTS}',
    'paper_rubric_grading': ${PY_PAPER_GRADING},
    'essay_rubric_criteria': int('${ESSAY_RUBRIC_CRITERIA}' or '0'),
    'essay_rubric_points': '${ESSAY_RUBRIC_POINTS}',
    'essay_rubric_grading': ${PY_ESSAY_GRADING},
    'weight_written': '${WEIGHT_WRITTEN}',
    'weight_lab': '${WEIGHT_LAB}',
    'weight_quiz': '${WEIGHT_QUIZ}',
    'weight_part': '${WEIGHT_PART}',
    'ecology_group': '${ECOLOGY_GROUP}',
    'late_deduction': '${LATE_DEDUCTION}',
    'late_minimum': '${LATE_MINIMUM}',
    'late_enabled': '${LATE_ENABLED}',
    'mod4_prereq': '${MOD4_PREREQ_NAME}',
    'exported_at': '$(date -Iseconds)'
}
with open('${TEMP_JSON}', 'w') as f:
    json.dump(result, f, indent=2)
"

safe_write_json "${TEMP_JSON}" "/tmp/${TASK_NAME}_result.json"
echo "=== Export Complete ==="
