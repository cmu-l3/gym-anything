#!/bin/bash
# Shared utilities for Jenkins tasks

# Jenkins credentials
JENKINS_URL="http://localhost:8080"
JENKINS_USER="admin"
JENKINS_PASS="Admin123!"

# Screenshot function
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Jenkins API query function
jenkins_api() {
    local endpoint="$1"
    curl -s -u "$JENKINS_USER:$JENKINS_PASS" "$JENKINS_URL/$endpoint"
}

# Jenkins CLI function
jenkins_cli() {
    # Download CLI jar if not exists
    if [ ! -f /tmp/jenkins-cli.jar ]; then
        curl -s "$JENKINS_URL/jnlpJars/jenkins-cli.jar" -o /tmp/jenkins-cli.jar
    fi

    java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" "$@"
}

# Check if job exists
job_exists() {
    local job_name="$1"
    jenkins_api "job/${job_name}/api/json" 2>/dev/null | grep -q '"_class"' && return 0 || return 1
}

# Get job config
get_job_config() {
    local job_name="$1"
    jenkins_api "job/${job_name}/config.xml"
}

# Get job status
get_job_status() {
    local job_name="$1"
    jenkins_api "job/${job_name}/api/json?pretty=true"
}

# Get last build info
get_last_build() {
    local job_name="$1"
    jenkins_api "job/${job_name}/lastBuild/api/json?pretty=true"
}

# Get build console output
get_build_console() {
    local job_name="$1"
    local build_number="${2:-lastBuild}"
    jenkins_api "job/${job_name}/${build_number}/consoleText"
}

# Count jobs
count_jobs() {
    jenkins_api "api/json" | jq -r '.jobs | length' 2>/dev/null || echo "0"
}

# List all jobs
list_jobs() {
    jenkins_api "api/json" | jq -r '.jobs[].name' 2>/dev/null
}

# Wait for window to appear
wait_for_window() {
    local pattern="$1"
    local timeout="${2:-30}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$pattern"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

# Get Firefox window ID
get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}'
}

# Focus window
focus_window() {
    local wid="$1"
    DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
}

# Wait for Jenkins API to be ready
wait_for_jenkins_api() {
    local timeout="${1:-60}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if jenkins_api "api/json" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}
