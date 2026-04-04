#!/bin/bash
echo "=== Exporting create_case_correspondence results ==="
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CASE_ID=$(cat /tmp/target_case_id.txt 2>/dev/null || echo "")
INITIAL_COUNT=$(cat /tmp/initial_corr_count.txt 2>/dev/null || echo "0")

echo "Task Start: $TASK_START"
echo "Case ID: $CASE_ID"

# 1. API Verification
CORRESPONDENCE_FOUND="false"
SUBJECT_MATCH="false"
BODY_MATCH="false"
NEW_COUNT=0
MATCHING_CORR_ID=""
CORR_DATE=0

if [ -n "$CASE_ID" ]; then
    echo "Querying correspondence for case $CASE_ID..."
    
    # Get all correspondence for the case
    # Note: ArkCase API structure may vary, we check the standard plugin/complaint endpoint
    CORR_RESPONSE=$(arkcase_api GET "plugin/complaint/${CASE_ID}/correspondence" 2>/dev/null || echo "[]")
    
    # Save response for debugging
    echo "$CORR_RESPONSE" > /tmp/debug_correspondence_response.json
    
    # Python script to analyze the correspondence list
    # We look for:
    # 1. Created AFTER task start
    # 2. Matches expected subject
    # 3. Matches body keywords
    python3 -c "
import sys, json, time

try:
    data = json.load(open('/tmp/debug_correspondence_response.json'))
    task_start = $TASK_START
    
    if not isinstance(data, list):
        data = []
        
    final_count = len(data)
    
    found = False
    subj_match = False
    body_match = False
    corr_id = ''
    
    target_subject = 'Official Response - Records Request Determination'
    target_snippets = ['Freedom of Information Act', 'releasable in full']
    
    # Iterate through correspondence to find the best match
    for item in data:
        # Check timestamp (createdDate is usually ms epoch)
        created_ms = item.get('createdDate', 0)
        created_sec = created_ms / 1000
        
        # Allow a small buffer for clock skew, but generally must be > task_start
        if created_sec > (task_start - 60):
            found = True
            c_subject = item.get('topic', item.get('subject', ''))
            c_body = item.get('content', item.get('body', ''))
            
            # Check subject
            if target_subject.lower() in c_subject.lower():
                subj_match = True
                
            # Check body
            snippet_hits = 0
            for snippet in target_snippets:
                if snippet.lower() in c_body.lower():
                    snippet_hits += 1
            if snippet_hits >= 1:
                body_match = True
                
            if subj_match:
                corr_id = item.get('id', '')
                break
    
    print(f'count={final_count}')
    print(f'found={str(found).lower()}')
    print(f'subj_match={str(subj_match).lower()}')
    print(f'body_match={str(body_match).lower()}')
    print(f'corr_id={corr_id}')

except Exception as e:
    print('count=0')
    print('found=false')
    print('subj_match=false')
    print('body_match=false')
    print('corr_id=')
" > /tmp/analysis_result.txt

    # Read analysis results
    NEW_COUNT=$(grep "count=" /tmp/analysis_result.txt | cut -d= -f2)
    CORRESPONDENCE_FOUND=$(grep "found=" /tmp/analysis_result.txt | cut -d= -f2)
    SUBJECT_MATCH=$(grep "subj_match=" /tmp/analysis_result.txt | cut -d= -f2)
    BODY_MATCH=$(grep "body_match=" /tmp/analysis_result.txt | cut -d= -f2)
    MATCHING_CORR_ID=$(grep "corr_id=" /tmp/analysis_result.txt | cut -d= -f2)
fi

# 2. Solr Search Fallback
# If API list failed (sometimes nested objects update slowly), try Solr
if [ "$CORRESPONDENCE_FOUND" = "false" ]; then
    echo "Checking Solr search index..."
    SEARCH_RESPONSE=$(arkcase_api GET "plugin/search?query=Official+Response&objectType=CORRESPONDENCE" 2>/dev/null || echo "{}")
    SOLR_HITS=$(echo "$SEARCH_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('response', {}).get('numFound', 0))" 2>/dev/null || echo "0")
    
    if [ "$SOLR_HITS" -gt "0" ]; then
        # We assume if it's in Solr and wasn't before (implied), it's the one
        # Ideally we'd check timestamps in Solr docs too
        CORRESPONDENCE_FOUND="true"
        # Can't verify exact body easily via simple search query without parsing docs
        # We'll give partial credit in verifier
    fi
fi

# 3. Capture Evidence
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
[ -f /tmp/task_final.png ] && SCREENSHOT_EXISTS="true"

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "case_id": "$CASE_ID",
    "initial_count": $INITIAL_COUNT,
    "final_count": ${NEW_COUNT:-0},
    "correspondence_found": $CORRESPONDENCE_FOUND,
    "subject_match": $SUBJECT_MATCH,
    "body_match": $BODY_MATCH,
    "matching_id": "$MATCHING_CORR_ID",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="