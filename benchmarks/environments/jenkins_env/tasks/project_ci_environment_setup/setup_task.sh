#!/bin/bash
# Setup script for Project CI Environment Setup task.
# Ensures a clean slate: removes any pre-existing alpha-* jobs, the Project-Alpha CI view,
# and the npm-registry-token credential so the agent starts from scratch.

echo "=== Setting up Project CI Environment Setup Task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 90; then
    echo "WARNING: Jenkins API may not be ready"
fi

# ── CSRF crumb ────────────────────────────────────────────────
CRUMB_JSON=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" \
    -c /tmp/jenkins_cookies_pces \
    "$JENKINS_URL/crumbIssuer/api/json" 2>/dev/null || echo '{}')
CRUMB_FIELD=$(echo "$CRUMB_JSON" | jq -r '.crumbRequestField // empty' 2>/dev/null)
CRUMB_VALUE=$(echo "$CRUMB_JSON" | jq -r '.crumb // empty' 2>/dev/null)

AUTH_OPTS=(-u "$JENKINS_USER:$JENKINS_PASS" -b /tmp/jenkins_cookies_pces)
if [ -n "$CRUMB_FIELD" ] && [ -n "$CRUMB_VALUE" ]; then
    AUTH_OPTS+=(-H "$CRUMB_FIELD: $CRUMB_VALUE")
fi

# ── Remove pre-existing target jobs (clean slate) ─────────────
for JOB in alpha-backend-build alpha-frontend-build; do
    if job_exists "$JOB"; then
        echo "Removing pre-existing job: $JOB"
        curl -s -o /dev/null -w "  HTTP %{http_code}\n" \
            "${AUTH_OPTS[@]}" \
            -X POST "$JENKINS_URL/job/$JOB/doDelete" 2>/dev/null
        sleep 1
    fi
done

# ── Remove pre-existing view ──────────────────────────────────
echo "Removing 'Project-Alpha CI' view if exists..."
curl -s -o /dev/null \
    "${AUTH_OPTS[@]}" \
    -X POST "$JENKINS_URL/view/Project-Alpha%20CI/doDelete" 2>/dev/null || true

# ── Remove pre-existing credential ───────────────────────────
echo "Removing 'npm-registry-token' credential if exists..."
curl -s -o /dev/null \
    "${AUTH_OPTS[@]}" \
    -X POST "$JENKINS_URL/credentials/store/system/domain/_/credential/npm-registry-token/doDelete" \
    2>/dev/null || true

sleep 1

# ── Record initial state ──────────────────────────────────────
INITIAL_JOB_COUNT=$(count_jobs)
printf '%s' "$INITIAL_JOB_COUNT" > /tmp/initial_job_count_pces
date +%s > /tmp/task_start_timestamp

echo "Initial job count: $INITIAL_JOB_COUNT"

# ── Start Firefox ─────────────────────────────────────────────
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox "$JENKINS_URL" > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

if ! wait_for_window "firefox\|mozilla\|jenkins" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Project CI Environment Setup — Setup Complete ==="
echo ""
echo "Clean slate confirmed. No alpha-* jobs, no 'Project-Alpha CI' view,"
echo "and no 'npm-registry-token' credential exist."
echo ""
echo "The agent must create from scratch:"
echo "  1. alpha-backend-build  (Pipeline, Git SCM github.com/jenkinsci/pipeline-examples, H/15 polling)"
echo "  2. alpha-frontend-build (any type, NODE_VERSION choice param 16/18/20, keep 7 builds)"
echo "  3. npm-registry-token   (secret text credential)"
echo "  4. Project-Alpha CI     (list view containing both jobs)"
echo ""
