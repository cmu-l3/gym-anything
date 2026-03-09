#!/bin/bash
# Export script for Longitudinal ANC Visit Entry task

echo "=== Exporting Longitudinal ANC Visit Entry Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get timestamps
TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2024-01-01T00:00:00")

# We need to extract the data for Hawa Jalloh created AFTER the task start.
# We will use SQL via docker exec to get precise data.

echo "Querying database for patient and events..."

# SQL Query Explanation:
# 1. Find TEI matching Hawa Jalloh created after task start
# 2. Join with Enrollment (ProgramInstance)
# 3. Join with Events (ProgramStageInstance)
# 4. Join with DataValues (TrackedEntityDataValue)
# 5. Output as JSON-like structure

# Create a temporary SQL file
cat > /tmp/query_data.sql << SQLEOF
WITH target_tei AS (
    SELECT DISTINCT tei.trackedentityinstanceid, tei.uid, tei.created
    FROM trackedentityinstance tei
    JOIN trackedentityattributevalue teav1 ON tei.trackedentityinstanceid = teav1.trackedentityinstanceid
    JOIN trackedentityattributevalue teav2 ON tei.trackedentityinstanceid = teav2.trackedentityinstanceid
    WHERE teav1.value ILIKE 'Hawa' 
      AND teav2.value ILIKE 'Jalloh'
      AND tei.created >= '$TASK_START_ISO'::timestamp
    ORDER BY tei.created DESC
    LIMIT 1
)
SELECT 
    json_build_object(
        'tei_uid', t.uid,
        'tei_created', t.created,
        'enrollments', (
            SELECT json_agg(json_build_object(
                'program', p.name,
                'enrollment_date', pi.enrollmentdate,
                'org_unit', ou.name,
                'events', (
                    SELECT json_agg(json_build_object(
                        'event_uid', psi.uid,
                        'date', psi.executiondate,
                        'status', psi.status,
                        'data_values', (
                            SELECT json_agg(json_build_object(
                                'data_element', de.name,
                                'value', tedv.value
                            ))
                            FROM trackedentitydatavalue tedv
                            JOIN dataelement de ON tedv.dataelementid = de.dataelementid
                            WHERE tedv.programstageinstanceid = psi.programstageinstanceid
                        )
                    ))
                    FROM programstageinstance psi
                    WHERE psi.programinstanceid = pi.programinstanceid
                    AND psi.deleted = false
                )
            ))
            FROM programinstance pi
            JOIN program p ON pi.programid = p.programid
            JOIN organisationunit ou ON pi.organisationunitid = ou.organisationunitid
            WHERE pi.trackedentityinstanceid = t.trackedentityinstanceid
        )
    )
FROM target_tei t;
SQLEOF

# Execute Query
JSON_OUTPUT=$(docker exec dhis2-db psql -U dhis -d dhis2 -t -f /tmp/query_data.sql 2>/dev/null | head -n 1)

# Check if we got data
FOUND="false"
if [ -n "$JSON_OUTPUT" ] && [ "$JSON_OUTPUT" != " " ]; then
    FOUND="true"
else
    JSON_OUTPUT="{}"
fi

# Construct final JSON result
cat > /tmp/longitudinal_anc_result.json << JSONEOF
{
    "task_start_iso": "$TASK_START_ISO",
    "patient_found": $FOUND,
    "data": $JSON_OUTPUT,
    "screenshot_path": "/tmp/task_end_screenshot.png"
}
JSONEOF

echo "Exported Data:"
cat /tmp/longitudinal_anc_result.json

# Clean up
rm -f /tmp/query_data.sql

echo "=== Export Complete ==="