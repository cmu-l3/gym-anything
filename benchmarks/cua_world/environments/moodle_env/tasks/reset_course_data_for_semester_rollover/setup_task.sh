#!/bin/bash
# Setup script for Reset Course Data task

echo "=== Setting up Reset Course Data Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Define paths
MOODLE_DIR="/var/www/html/moodle"

# 1. Generate Course and Stale Data via PHP
# We use PHP to ensure all Moodle internal links/logs/grades are consistent
echo "Generating course data..."
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('$MOODLE_DIR/config.php');
require_once(\$CFG->dirroot . '/course/lib.php');
require_once(\$CFG->dirroot . '/user/lib.php');
require_once(\$CFG->dirroot . '/mod/assign/lib.php');
require_once(\$CFG->dirroot . '/mod/quiz/lib.php');
require_once(\$CFG->dirroot . '/mod/forum/lib.php');

// 1. Create Course if not exists
\$course = \$DB->get_record('course', ['shortname' => 'BIO101']);
if (!\$course) {
    \$coursedata = new stdClass();
    \$coursedata->fullname = 'Introduction to Biology';
    \$coursedata->shortname = 'BIO101';
    \$coursedata->category = 1;
    \$coursedata->startdate = time() - (86400 * 120); // Started 4 months ago
    \$course = create_course(\$coursedata);
    echo \"Created course BIO101 (ID: \$course->id)\n\";
} else {
    echo \"Course BIO101 exists (ID: \$course->id)\n\";
}

// 2. Create Student if not exists
\$user = \$DB->get_record('user', ['username' => 'jsmith']);
if (!\$user) {
    \$user = create_user_record('jsmith', 'Student1234!');
    \$user->firstname = 'Jane';
    \$user->lastname = 'Smith';
    \$DB->update_record('user', \$user);
    echo \"Created user jsmith\n\";
}

// 3. Enrol Student
if (!is_enrolled(context_course::instance(\$course->id), \$user->id)) {
    \$studentrole = \$DB->get_record('role', ['shortname' => 'student']);
    \$enrol = enrol_get_plugin('manual');
    \$instances = enrol_get_instances(\$course->id, true);
    foreach (\$instances as \$instance) {
        if (\$instance->enrol === 'manual') {
            \$enrol->enrol_user(\$instance, \$user->id, \$studentrole->id);
            echo \"Enrolled jsmith in BIO101\n\";
            break;
        }
    }
}

// 4. Create Activities (Assignment, Quiz, Forum)
\$generator = new testing_data_generator();

// Assignment
if (!\$DB->record_exists('assign', ['course' => \$course->id, 'name' => 'Lab Report 1'])) {
    \$assign = \$generator->create_module('assign', ['course' => \$course->id, 'name' => 'Lab Report 1']);
    
    // Create Submission
    \$submission = new stdClass();
    \$submission->assignment = \$assign->id;
    \$submission->userid = \$user->id;
    \$submission->timecreated = time();
    \$submission->timemodified = time();
    \$submission->status = 'submitted';
    \$submission->latest = 1;
    \$submission->attemptnumber = 0;
    \$submission->groupid = 0;
    \$sid = \$DB->insert_record('assign_submission', \$submission);
    
    // Grade it
    \$grade = new stdClass();
    \$grade->assignment = \$assign->id;
    \$grade->userid = \$user->id;
    \$grade->timecreated = time();
    \$grade->timemodified = time();
    \$grade->grader = 2; // Admin
    \$grade->grade = 85.0;
    \$grade->attemptnumber = 0;
    \$DB->insert_record('assign_grades', \$grade);
    echo \"Created assignment and submission\n\";
}

// Quiz
if (!\$DB->record_exists('quiz', ['course' => \$course->id, 'name' => 'Midterm Exam'])) {
    \$quiz = \$generator->create_module('quiz', ['course' => \$course->id, 'name' => 'Midterm Exam']);
    
    // Create Attempt
    \$attempt = new stdClass();
    \$attempt->quiz = \$quiz->id;
    \$attempt->userid = \$user->id;
    \$attempt->attempt = 1;
    \$attempt->state = 'finished';
    \$attempt->timestart = time() - 3600;
    \$attempt->timefinish = time();
    \$attempt->sumgrades = 10;
    \$DB->insert_record('quiz_attempts', \$attempt);
    echo \"Created quiz and attempt\n\";
}

// Forum
if (!\$DB->record_exists('forum', ['course' => \$course->id, 'name' => 'Class Discussion'])) {
    \$forum = \$generator->create_module('forum', ['course' => \$course->id, 'name' => 'Class Discussion']);
    
    // Create Discussion & Post
    \$discussion = new stdClass();
    \$discussion->course = \$course->id;
    \$discussion->forum = \$forum->id;
    \$discussion->name = 'Introductions';
    \$discussion->userid = \$user->id;
    \$discussion->timemodified = time();
    \$id = \$DB->insert_record('forum_discussions', \$discussion);
    
    \$post = new stdClass();
    \$post->discussion = \$id;
    \$post->parent = 0;
    \$post->userid = \$user->id;
    \$post->created = time();
    \$post->modified = time();
    \$post->subject = 'Hello';
    \$post->message = 'Hi everyone';
    \$DB->insert_record('forum_posts', \$post);
    echo \"Created forum and post\n\";
}
"

# 2. Record Initial State
echo "Recording initial state..."
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
echo "$COURSE_ID" > /tmp/course_id

INIT_SUBMISSIONS=$(moodle_query "SELECT COUNT(*) FROM mdl_assign_submission s JOIN mdl_assign a ON s.assignment=a.id WHERE a.course=$COURSE_ID")
INIT_ATTEMPTS=$(moodle_query "SELECT COUNT(*) FROM mdl_quiz_attempts qa JOIN mdl_quiz q ON qa.quiz=q.id WHERE q.course=$COURSE_ID")
INIT_POSTS=$(moodle_query "SELECT COUNT(*) FROM mdl_forum_posts fp JOIN mdl_forum_discussions fd ON fp.discussion=fd.id WHERE fd.course=$COURSE_ID")
INIT_ENROL=$(get_enrollment_count "$COURSE_ID")

echo "Initial Submissions: $INIT_SUBMISSIONS"
echo "Initial Attempts: $INIT_ATTEMPTS"
echo "Initial Posts: $INIT_POSTS"
echo "Initial Enrollments: $INIT_ENROL"

cat > /tmp/initial_state.json << EOF
{
  "course_id": "$COURSE_ID",
  "submissions": $INIT_SUBMISSIONS,
  "attempts": $INIT_ATTEMPTS,
  "posts": $INIT_POSTS,
  "enrollments": $INIT_ENROL
}
EOF

# 3. Setup Browser
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/course/view.php?id=$COURSE_ID' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Wait and Focus
wait_for_window "firefox\|mozilla\|Moodle" 30
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 4. Anti-gaming Timestamp
date +%s > /tmp/task_start_time

# 5. Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="