#!/bin/bash
set -euo pipefail

TASK_NAME="bio201_outcomes_assessment_migration"

echo "=== Setting up ${TASK_NAME} ==="
source /workspace/scripts/task_utils.sh

if ! ensure_canvas_ready_for_task 5; then
  echo "CRITICAL: Canvas did not become ready."
  exit 1
fi

# ── Ensure BIO201 exists ──
COURSE_ID=$(canvas_query "SELECT id FROM courses WHERE LOWER(TRIM(course_code))='bio201' AND workflow_state='available' LIMIT 1" | tr -d '[:space:]')
if [ -z "${COURSE_ID}" ]; then
  echo "BIO201 not found, creating via Rails..."
  cat << 'RUBY_CREATE' | docker exec -i canvas-lms tee /tmp/create_bio201.rb > /dev/null
bio = Course.create!(
  name: 'Advanced Biology',
  course_code: 'BIO201',
  workflow_state: 'available',
  root_account_id: 1,
  account_id: 1,
  enrollment_term_id: 1
)
puts bio.id
RUBY_CREATE
  docker exec canvas-lms bash -lc "cd /opt/canvas/canvas-lms && RAILS_ENV=development GEM_HOME=/opt/canvas/.gems /opt/canvas/.gems/bin/bundle exec rails runner /tmp/create_bio201.rb"
  COURSE_ID=$(canvas_query "SELECT id FROM courses WHERE LOWER(TRIM(course_code))='bio201' AND workflow_state='available' LIMIT 1" | tr -d '[:space:]')
fi

if [ -z "${COURSE_ID}" ]; then
  echo "CRITICAL: Could not find or create BIO201."
  exit 1
fi
echo "BIO201 course_id=${COURSE_ID}"

# ── Delete stale outputs BEFORE recording timestamp ──
rm -f /tmp/${TASK_NAME}_result.json 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_result.*.json 2>/dev/null || true

# ── Write the main Ruby setup script into the container ──
cat << 'RUBY_EOF' | docker exec -i canvas-lms tee /tmp/setup_bio201_migration.rb > /dev/null
# ============================================================
# BIO201 Outcomes-Based Assessment Migration — Broken State Setup
# ============================================================

bio = Course.find_by(course_code: 'BIO201', workflow_state: 'available')
raise "BIO201 not found" unless bio

# ── CLEAN SLATE ──

# Delete module items then modules
bio.context_modules.each do |m|
  m.content_tags.each { |ct| ct.destroy rescue nil }
  m.destroy rescue nil
end

# Delete rubric associations and rubrics
RubricAssociation.where(context: bio).each { |ra| ra.destroy rescue nil }
Rubric.where(context: bio).each { |r| r.destroy rescue nil }

# Delete learning outcome content tags and outcomes
ContentTag.where(context: bio, content_type: 'LearningOutcome').each { |ct| ct.destroy rescue nil }
LearningOutcome.where(context: bio).each { |lo| lo.destroy rescue nil }

# Delete late policies
LatePolicy.where(course_id: bio.id).destroy_all rescue nil

# Delete wiki pages
bio.wiki_pages.each { |wp| wp.destroy rescue nil }

# Soft-delete all assignments
bio.assignments.where.not(workflow_state: 'deleted').each do |a|
  a.workflow_state = 'deleted'
  a.save! rescue nil
end

# Delete assignment groups
bio.assignment_groups.where.not(workflow_state: 'deleted').each do |ag|
  ag.workflow_state = 'deleted'
  ag.save! rescue nil
end

# Delete feature flags for outcomes
FeatureFlag.where(context: bio, feature: ['outcome_gradebook', 'student_outcome_gradebook']).destroy_all rescue nil

puts "Clean slate complete"

# ── ENROLLMENTS ──

teacher1 = Pseudonym.find_by(unique_id: 'teacher1')&.user
if teacher1 && bio.teacher_enrollments.where(user_id: teacher1.id).empty?
  bio.enroll_teacher(teacher1)
  puts "  Enrolled teacher1"
end

%w[jsmith mjones awilson bbrown cgarcia dlee epatel fkim].each do |login|
  student = Pseudonym.find_by(unique_id: login)&.user
  if student && bio.student_enrollments.where(user_id: student.id).empty?
    bio.enroll_student(student)
    puts "  Enrolled #{login}"
  end
end

# ── ENABLE WEIGHTED GRADING ──
bio.group_weighting_scheme = 'percent'
bio.save!

# ── ASSIGNMENT GROUPS (with WRONG weights) ──
# Target: Written=25%, Lab=30%, Quiz=25%, Participation=20%
# Actual: Written=35%, Lab=15%, Quiz=25%, Participation=25%
ag_written = bio.assignment_groups.create!(name: 'Written Assignments', group_weight: 35, position: 1)
ag_lab     = bio.assignment_groups.create!(name: 'Laboratory Reports',  group_weight: 15, position: 2)
ag_quiz    = bio.assignment_groups.create!(name: 'Quizzes & Exams',     group_weight: 25, position: 3)
ag_part    = bio.assignment_groups.create!(name: 'Participation',       group_weight: 25, position: 4)

puts "  Assignment groups created (weights: #{ag_written.group_weight}/#{ag_lab.group_weight}/#{ag_quiz.group_weight}/#{ag_part.group_weight})"

# ── ASSIGNMENTS ──
a_intro   = bio.assignments.create!(title: 'Course Introduction Post',            points_possible: 10,  assignment_group: ag_part,    workflow_state: 'published', submission_types: 'online_text_entry')
a_celllab = bio.assignments.create!(title: 'Cell Biology Lab Report',              points_possible: 50,  assignment_group: ag_lab,     workflow_state: 'published', submission_types: 'online_upload')
a_molbio  = bio.assignments.create!(title: 'Molecular Biology Analysis Paper',     points_possible: 80,  assignment_group: ag_written, workflow_state: 'published', submission_types: 'online_upload')
# WRONG GROUP: Ecology Field Report in Written Assignments (should be Laboratory Reports)
a_ecology = bio.assignments.create!(title: 'Ecology Field Report',                 points_possible: 50,  assignment_group: ag_written, workflow_state: 'published', submission_types: 'online_upload')
a_paper   = bio.assignments.create!(title: 'Final Research Paper',                 points_possible: 150, assignment_group: ag_written, workflow_state: 'published', submission_types: 'online_upload',
              description: '<p>Students will research and write a comprehensive paper on an advanced biology topic. Must include primary literature review, methodology section, and original analysis.</p>')
a_essay   = bio.assignments.create!(title: 'Midterm Essay',                        points_possible: 100, assignment_group: ag_written, workflow_state: 'published', submission_types: 'online_upload',
              description: '<p>In-class essay examining a core concept from the first half of the course. Students will demonstrate understanding of experimental design and scientific reasoning.</p>')

puts "  #{bio.assignments.where(workflow_state: 'published').count} assignments created"

# ── GENETICS CHECKPOINT (as graded assignment in Quizzes & Exams group) ──
a_genetics = bio.assignments.create!(
  title: 'Genetics Checkpoint',
  points_possible: 30,
  assignment_group: ag_quiz,
  workflow_state: 'published',
  submission_types: 'online_quiz',
  description: '<p>Short assessment covering genetic principles and inheritance patterns from Week 3.</p>'
)
puts "  Genetics Checkpoint assignment created"

# ── MODULES (correct order — this is NOT an error) ──
mod1 = bio.context_modules.create!(name: 'Week 1: Introduction to Advanced Biology', position: 1, workflow_state: 'active')
mod2 = bio.context_modules.create!(name: 'Week 2: Cell Biology Fundamentals',        position: 2, workflow_state: 'active')
mod3 = bio.context_modules.create!(name: 'Week 3: Genetics and Heredity',            position: 3, workflow_state: 'active')
mod4 = bio.context_modules.create!(name: 'Week 4: Molecular Biology',                position: 4, workflow_state: 'active')
mod5 = bio.context_modules.create!(name: 'Week 5: Ecology and Ecosystems',           position: 5, workflow_state: 'active')

# Wiki pages for module content
p_syl  = bio.wiki_pages.create!(title: 'Syllabus',              body: '<p>BIO201 Advanced Biology course syllabus.</p>',                              workflow_state: 'active')
p_cell = bio.wiki_pages.create!(title: 'Cell Structure Review',  body: '<p>Review of eukaryotic and prokaryotic cell structure and organelles.</p>',   workflow_state: 'active')
p_gen  = bio.wiki_pages.create!(title: 'Genetic Principles',     body: '<p>Mendelian genetics, inheritance patterns, and genetic variation.</p>',     workflow_state: 'active')
p_dna  = bio.wiki_pages.create!(title: 'DNA and RNA',            body: '<p>Structure and function of nucleic acids, replication, and transcription.</p>', workflow_state: 'active')
p_eco  = bio.wiki_pages.create!(title: 'Ecosystem Dynamics',     body: '<p>Energy flow, nutrient cycling, and trophic interactions in ecosystems.</p>',  workflow_state: 'active')

# Add items to modules
mod1.add_item(type: 'wiki_page', id: p_syl.id)
mod1.add_item(type: 'assignment', id: a_intro.id)
mod2.add_item(type: 'wiki_page', id: p_cell.id)
mod2.add_item(type: 'assignment', id: a_celllab.id)
mod3.add_item(type: 'wiki_page', id: p_gen.id)
mod3.add_item(type: 'assignment', id: a_genetics.id)
mod4.add_item(type: 'wiki_page', id: p_dna.id)
mod4.add_item(type: 'assignment', id: a_molbio.id)
mod5.add_item(type: 'wiki_page', id: p_eco.id)
mod5.add_item(type: 'assignment', id: a_ecology.id)

# Prerequisites are set via SQL after this script completes (Rails setter is broken in this Canvas version)
puts "  5 modules created (prerequisites will be set via SQL)"

# ── LEARNING OUTCOMES ──
# Scientific Communication — CORRECT (false positive trap: mastery=3, decaying_average)
lo_comm = LearningOutcome.new(
  context: bio,
  short_description: 'Scientific Communication',
  description: 'Students can communicate scientific ideas clearly and effectively in written form',
  calculation_method: 'decaying_average',
  calculation_int: 65,
  workflow_state: 'active'
)
lo_comm.rubric_criterion = {
  description: 'Scientific Communication',
  mastery_points: 3.0,
  points_possible: 5.0,
  ratings: [
    {description: 'Exceeds Expectations', points: 5.0},
    {description: 'Meets Expectations', points: 3.0},
    {description: 'Approaching', points: 2.0},
    {description: 'Below Expectations', points: 1.0},
    {description: 'No Evidence', points: 0.0}
  ]
}
lo_comm.save!
# Link to course via content tag
ContentTag.create!(content: lo_comm, content_type: 'LearningOutcome', context: bio, context_type: 'Course', tag_type: 'learning_outcome_association') rescue nil

# Experimental Design — WRONG mastery (2/5 instead of 3/5)
lo_design = LearningOutcome.new(
  context: bio,
  short_description: 'Experimental Design',
  description: 'Students can design controlled experiments with appropriate variables and controls',
  calculation_method: 'highest',
  workflow_state: 'active'
)
lo_design.rubric_criterion = {
  description: 'Experimental Design',
  mastery_points: 2.0,
  points_possible: 5.0,
  ratings: [
    {description: 'Exceeds Expectations', points: 5.0},
    {description: 'Meets Expectations', points: 3.0},
    {description: 'Near Mastery', points: 2.0},
    {description: 'Below Expectations', points: 1.0},
    {description: 'No Evidence', points: 0.0}
  ]
}
lo_design.save!
ContentTag.create!(content: lo_design, content_type: 'LearningOutcome', context: bio, context_type: 'Course', tag_type: 'learning_outcome_association') rescue nil

# Scientific Inquiry — MISSING (agent must create this)
# NOT created here — that is the agent's job

puts "  2 learning outcomes created (Scientific Communication correct, Experimental Design mastery=2 wrong)"

# ── LATE POLICY (WRONG values) ──
# Target: 10%/day, floor 40%
# Actual: 5%/day, floor 50%
LatePolicy.create!(
  course_id: bio.id,
  late_submission_deduction_enabled: true,
  late_submission_deduction: 5.0,
  late_submission_minimum_percent: 50.0,
  missing_submission_deduction_enabled: false,
  missing_submission_deduction: 0.0
)
puts "  Late policy created (5%/day, floor 50% — both wrong)"

# ── FEATURE FLAGS: DELETE to ensure OFF ──
FeatureFlag.where(context: bio, feature: ['outcome_gradebook', 'student_outcome_gradebook']).destroy_all rescue nil
puts "  Feature flags for outcomes gradebook removed (off by default)"

# ── MIGRATION PLAN WIKI PAGE ──
plan_html = <<~HTML
<h2>BIO201 Outcomes-Based Assessment Migration Plan</h2>
<p><em>Department of Biological Sciences &mdash; Spring 2026</em></p>

<h3>Overview</h3>
<p>BIO201 is transitioning to outcomes-based assessment per the department&rsquo;s
accreditation improvement initiative. This document specifies the complete
target configuration. All items below must be implemented exactly as described.</p>

<h3>Step 1: Enable Outcomes Features</h3>
<p>Enable both <strong>Learning Mastery Gradebook</strong> and
<strong>Student Learning Mastery Gradebook</strong> in
Course Settings &rarr; Feature Options.</p>

<h3>Step 2: Learning Outcomes</h3>
<p>The course requires exactly three learning outcomes:</p>
<ul>
  <li><strong>Scientific Inquiry</strong> &mdash; mastery at 3 out of 5,
      calculation method: Latest Score</li>
  <li><strong>Experimental Design</strong> &mdash; mastery at 3 out of 5,
      calculation method: Highest Score</li>
  <li><strong>Scientific Communication</strong> &mdash; mastery at 3 out of 5,
      calculation method: Decaying Average</li>
</ul>

<h3>Step 3: Assessment Rubric</h3>
<p>Create a rubric titled <strong>&ldquo;BIO201 Research Assessment Rubric&rdquo;</strong>
with the following criteria:</p>
<table border="1" cellpadding="6" cellspacing="0">
  <thead>
    <tr><th>Criterion</th><th>Points</th><th>Aligned Outcome</th></tr>
  </thead>
  <tbody>
    <tr><td>Research Question</td><td>25</td><td>Scientific Inquiry</td></tr>
    <tr><td>Methodology</td><td>30</td><td>Experimental Design</td></tr>
    <tr><td>Analysis &amp; Evidence</td><td>25</td><td>Scientific Inquiry</td></tr>
    <tr><td>Written Communication</td><td>20</td><td>Scientific Communication</td></tr>
  </tbody>
</table>
<p>Attach this rubric <strong>for grading</strong> to both
<strong>&ldquo;Final Research Paper&rdquo;</strong> and
<strong>&ldquo;Midterm Essay&rdquo;</strong>.</p>

<h3>Step 4: Grading Structure</h3>
<p>Assignment group weights must be configured as follows:</p>
<ul>
  <li>Written Assignments: <strong>25%</strong></li>
  <li>Laboratory Reports: <strong>30%</strong></li>
  <li>Quizzes &amp; Exams: <strong>25%</strong></li>
  <li>Participation: <strong>20%</strong></li>
</ul>
<p><em>Note: &ldquo;Ecology Field Report&rdquo; belongs in the Laboratory Reports group.</em></p>
<p>Late submission policy: <strong>10% deduction per day</strong>,
minimum score floor of <strong>40%</strong>.</p>

<h3>Step 5: Module Prerequisites</h3>
<p>Each weekly module must require completion of the immediately preceding module
(Week 2 requires Week 1, Week 3 requires Week 2, Week 4 requires Week 3,
Week 5 requires Week 4).</p>
HTML

bio.wiki_pages.create!(
  title: 'Outcomes-Based Assessment Migration Plan',
  body: plan_html,
  workflow_state: 'active'
)
puts "  Migration Plan wiki page created"

puts ""
puts "=== BIO201 Setup Summary ==="
puts "  Course ID: #{bio.id}"
puts "  Modules: #{bio.context_modules.count}"
puts "  Assignments: #{bio.assignments.where(workflow_state: 'published').count}"
puts "  Assignment Groups: #{bio.assignment_groups.where.not(workflow_state: 'deleted').count}"
puts "  Learning Outcomes: #{LearningOutcome.where(context: bio, workflow_state: 'active').count}"
puts "  Wiki Pages: #{bio.wiki_pages.where(workflow_state: 'active').count}"
puts "  Late Policy: #{LatePolicy.where(course_id: bio.id).count}"
puts ""
puts "  PLANTED ERRORS:"
puts "    1. Assignment group weights: Written=35 Lab=15 Participation=25 (should be 25/30/20)"
puts "    2. Ecology Field Report in Written Assignments (should be Laboratory Reports)"
puts "    3. Late policy: 5%/day floor 50% (should be 10%/day floor 40%)"
puts "    4. Week 4 prerequisite: Week 2 (should be Week 3)"
puts "    5. Experimental Design mastery: 2/5 (should be 3/5)"
puts "    6. Scientific Inquiry outcome: MISSING (agent must create)"
puts "    7. Feature flags: OFF (agent must enable)"
puts "    8. No rubric exists (agent must create and attach)"
puts ""
puts "  CORRECT ITEMS (false positives):"
puts "    - Module order (Weeks 1-5 sequential)"
puts "    - Prerequisites for Weeks 2, 3, 5"
puts "    - Scientific Communication outcome (mastery=3, decaying_average)"
puts "    - Quizzes & Exams weight (25%)"
puts "    - Most assignment categorizations"
RUBY_EOF

# Run the setup script
echo "Running Rails setup script..."
docker exec canvas-lms bash -lc "cd /opt/canvas/canvas-lms && RAILS_ENV=development GEM_HOME=/opt/canvas/.gems /opt/canvas/.gems/bin/bundle exec rails runner /tmp/setup_bio201_migration.rb"

# ── Set module prerequisites via SQL (Rails setter is broken in this Canvas version) ──
echo "Setting module prerequisites via SQL..."
MOD1_ID=$(canvas_query "SELECT id FROM context_modules WHERE context_id=${COURSE_ID} AND context_type='Course' AND name LIKE 'Week 1%' AND workflow_state='active' LIMIT 1" | tr -d '[:space:]')
MOD2_ID=$(canvas_query "SELECT id FROM context_modules WHERE context_id=${COURSE_ID} AND context_type='Course' AND name LIKE 'Week 2%' AND workflow_state='active' LIMIT 1" | tr -d '[:space:]')
MOD3_ID=$(canvas_query "SELECT id FROM context_modules WHERE context_id=${COURSE_ID} AND context_type='Course' AND name LIKE 'Week 3%' AND workflow_state='active' LIMIT 1" | tr -d '[:space:]')
MOD4_ID=$(canvas_query "SELECT id FROM context_modules WHERE context_id=${COURSE_ID} AND context_type='Course' AND name LIKE 'Week 4%' AND workflow_state='active' LIMIT 1" | tr -d '[:space:]')
MOD5_ID=$(canvas_query "SELECT id FROM context_modules WHERE context_id=${COURSE_ID} AND context_type='Course' AND name LIKE 'Week 5%' AND workflow_state='active' LIMIT 1" | tr -d '[:space:]')

echo "Module IDs: mod1=${MOD1_ID} mod2=${MOD2_ID} mod3=${MOD3_ID} mod4=${MOD4_ID} mod5=${MOD5_ID}"

# Week 2 requires Week 1 (CORRECT)
canvas_query "UPDATE context_modules SET prerequisites = E'---\n- :type: context_module\n  :id: ${MOD1_ID}\n  :name: \"Week 1: Introduction to Advanced Biology\"\n' WHERE id = ${MOD2_ID}"

# Week 3 requires Week 2 (CORRECT)
canvas_query "UPDATE context_modules SET prerequisites = E'---\n- :type: context_module\n  :id: ${MOD2_ID}\n  :name: \"Week 2: Cell Biology Fundamentals\"\n' WHERE id = ${MOD3_ID}"

# Week 4 requires Week 2 (WRONG — should require Week 3)
canvas_query "UPDATE context_modules SET prerequisites = E'---\n- :type: context_module\n  :id: ${MOD2_ID}\n  :name: \"Week 2: Cell Biology Fundamentals\"\n' WHERE id = ${MOD4_ID}"

# Week 5 requires Week 4 (CORRECT)
canvas_query "UPDATE context_modules SET prerequisites = E'---\n- :type: context_module\n  :id: ${MOD4_ID}\n  :name: \"Week 4: Molecular Biology\"\n' WHERE id = ${MOD5_ID}"

echo "Module prerequisites set via SQL"

# ── Record baseline state ──
START_TS=$(date +%s)

OUTCOME_COUNT=$(canvas_query "SELECT COUNT(*) FROM learning_outcomes WHERE context_type='Course' AND context_id=${COURSE_ID} AND workflow_state='active'" | tr -d '[:space:]')
RUBRIC_COUNT=$(canvas_query "SELECT COUNT(*) FROM rubrics WHERE context_id=${COURSE_ID} AND context_type='Course'" | tr -d '[:space:]')
AG_COUNT=$(canvas_query "SELECT COUNT(*) FROM assignment_groups WHERE course_id=${COURSE_ID} AND workflow_state!='deleted'" | tr -d '[:space:]')
MODULE_COUNT=$(canvas_query "SELECT COUNT(*) FROM context_modules WHERE context_id=${COURSE_ID} AND context_type='Course' AND workflow_state='active'" | tr -d '[:space:]')
ASSIGN_COUNT=$(canvas_query "SELECT COUNT(*) FROM assignments WHERE context_id=${COURSE_ID} AND context_type='Course' AND workflow_state='published'" | tr -d '[:space:]')

echo "${COURSE_ID}"            > "/tmp/${TASK_NAME}_course_id"
echo "${START_TS}"             > "/tmp/${TASK_NAME}_start_ts"
echo "${OUTCOME_COUNT:-0}"     > "/tmp/${TASK_NAME}_initial_outcome_count"
echo "${RUBRIC_COUNT:-0}"      > "/tmp/${TASK_NAME}_initial_rubric_count"
echo "${AG_COUNT:-0}"          > "/tmp/${TASK_NAME}_initial_ag_count"
echo "${MODULE_COUNT:-0}"      > "/tmp/${TASK_NAME}_initial_module_count"
echo "${ASSIGN_COUNT:-0}"      > "/tmp/${TASK_NAME}_initial_assign_count"
echo "${START_TS}"             > /tmp/task_start_timestamp

take_screenshot "/tmp/${TASK_NAME}_start.png"

echo ""
echo "BIO201 course_id=${COURSE_ID}"
echo "Outcomes=${OUTCOME_COUNT:-0} Rubrics=${RUBRIC_COUNT:-0} AG=${AG_COUNT:-0} Modules=${MODULE_COUNT:-0} Assignments=${ASSIGN_COUNT:-0}"
echo "Start timestamp=${START_TS}"
echo "=== Setup Complete ==="
