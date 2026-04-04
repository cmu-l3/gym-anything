#!/bin/bash
# Export script for Scheduled Analytics Job Config task

echo "=== Exporting Scheduled Analytics Job Config Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        local endpoint="$1"
        local method="${2:-GET}"
        curl -s -u admin:district -X "$method" "http://localhost:8080/api/$endpoint"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")
INITIAL_JOB_COUNT=$(cat /tmp/initial_job_count 2>/dev/null | tr -d ' ' || echo "0")

echo "Baseline: initial_jobs=$INITIAL_JOB_COUNT, start_time=$TASK_START_ISO"

# Query DHIS2 API for all job configurations
echo "Querying job configurations..."
# Fetching id, name, jobType, cronExpression, enabled, created
JOB_RESULT=$(dhis2_api "jobConfigurations?fields=id,name,jobType,cronExpression,enabled,created,lastUpdated&paging=false" 2>/dev/null)

# Use Python to filter and find the relevant jobs created after task start
PARSED_JOBS=$(echo "$JOB_RESULT" | python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    
    # Simple ISO parsing fallback
    def parse_dt(s):
        try:
            return datetime.fromisoformat(s.replace('Z', '+00:00').replace('+0000', '+00:00'))
        except:
            return datetime(2020, 1, 1)

    task_start = parse_dt(task_start_iso)
    
    jobs = data.get('jobConfigurations', [])
    new_jobs = []
    
    # Identify our target jobs
    analytics_job = None
    resource_job = None
    
    for job in jobs:
        created_str = job.get('created', '')
        created_dt = parse_dt(created_str)
        
        # Check if created after task start (allowing 1 min buffer for clock skew)
        # Note: In a real env, we rely on task_start_iso being accurate.
        # If strict check fails, we might check lastUpdated if created isn't reliable, 
        # but creation is better for 'newly created' tasks.
        
        is_new = created_dt >= task_start
        
        name = job.get('name', '')
        job_type = job.get('jobType', '')
        
        if is_new:
            new_jobs.append(job)
            
            # Check for Analytics Job candidate
            if 'nightly' in name.lower() and 'analytics' in name.lower():
                analytics_job = job
            elif 'analytics' in name.lower() and job_type == 'ANALYTICS_TABLE':
                 # Fallback if name isn't perfect but type is right
                 if not analytics_job: analytics_job = job

            # Check for Resource Job candidate
            if 'weekly' in name.lower() and 'resource' in name.lower():
                resource_job = job
            elif 'resource' in name.lower() and job_type == 'RESOURCE_TABLE':
                 if not resource_job: resource_job = job

    result = {
        'total_jobs_now': len(jobs),
        'new_jobs_count': len(new_jobs),
        'analytics_job': analytics_job,
        'resource_job': resource_job
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null || echo '{"error": "Python parsing failed"}')

echo "Job parsing complete."

# Write result JSON
cat > /tmp/scheduled_job_config_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "initial_job_count": $INITIAL_JOB_COUNT,
    "parsed_jobs": $PARSED_JOBS,
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

chmod 666 /tmp/scheduled_job_config_result.json 2>/dev/null || true
echo "Result JSON saved to /tmp/scheduled_job_config_result.json"
echo ""
echo "=== Export Complete ==="