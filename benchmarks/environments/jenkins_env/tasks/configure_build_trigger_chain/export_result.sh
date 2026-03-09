#!/bin/bash
set -e
echo "=== Exporting build trigger chain results ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/trigger_chain_result.json"

# Initialize result structure (defaults)
cat > "$RESULT_FILE" <<'EOF'
{
  "jobs_exist": {},
  "build_config": {},
  "test_config": {},
  "deploy_config": {},
  "trigger_build_to_test": false,
  "trigger_test_to_deploy": false,
  "trigger_method_build_test": "none",
  "trigger_method_test_deploy": "none",
  "trigger_threshold_build_test": "unknown",
  "trigger_threshold_test_deploy": "unknown",
  "chain_execution": {},
  "configs_changed_from_baseline": {}
}
EOF

# Check job existence
echo "Checking job existence..."
BUILD_EXISTS=false
TEST_EXISTS=false
DEPLOY_EXISTS=false

job_exists "inventory-build" && BUILD_EXISTS=true
job_exists "inventory-test" && TEST_EXISTS=true
job_exists "inventory-deploy" && DEPLOY_EXISTS=true

# Get config XMLs
echo "Fetching job configurations..."
BUILD_CONFIG=""
TEST_CONFIG=""
DEPLOY_CONFIG=""

if [ "$BUILD_EXISTS" = "true" ]; then
    BUILD_CONFIG=$(jenkins_api "job/inventory-build/config.xml" 2>/dev/null || echo "")
fi
if [ "$TEST_EXISTS" = "true" ]; then
    TEST_CONFIG=$(jenkins_api "job/inventory-test/config.xml" 2>/dev/null || echo "")
fi
if [ "$DEPLOY_EXISTS" = "true" ]; then
    DEPLOY_CONFIG=$(jenkins_api "job/inventory-deploy/config.xml" 2>/dev/null || echo "")
fi

# Check for build→test trigger (Pattern A: post-build trigger on inventory-build)
PATTERN_A_BUILD_TEST=false
if echo "$BUILD_CONFIG" | grep -q "hudson.tasks.BuildTrigger"; then
    BUILD_CHILD_PROJECTS=$(echo "$BUILD_CONFIG" | python3 -c "
import sys
from lxml import etree
try:
    tree = etree.parse(sys.stdin)
    triggers = tree.findall('.//publishers/hudson.tasks.BuildTrigger')
    for t in triggers:
        cp = t.find('childProjects')
        if cp is not None and cp.text:
            print(cp.text.strip())
except:
    pass
" 2>/dev/null || echo "")
    if echo "$BUILD_CHILD_PROJECTS" | grep -qi "inventory-test"; then
        PATTERN_A_BUILD_TEST=true
    fi
fi

# Check for build→test trigger (Pattern B: reverse trigger on inventory-test)
PATTERN_B_BUILD_TEST=false
if echo "$TEST_CONFIG" | grep -q "ReverseBuildTrigger"; then
    TEST_UPSTREAM_PROJECTS=$(echo "$TEST_CONFIG" | python3 -c "
import sys
from lxml import etree
try:
    tree = etree.parse(sys.stdin)
    triggers = tree.findall('.//triggers/jenkins.triggers.ReverseBuildTrigger')
    for t in triggers:
        up = t.find('upstreamProjects')
        if up is not None and up.text:
            print(up.text.strip())
except:
    pass
" 2>/dev/null || echo "")
    if echo "$TEST_UPSTREAM_PROJECTS" | grep -qi "inventory-build"; then
        PATTERN_B_BUILD_TEST=true
    fi
fi

# Check for test→deploy trigger (Pattern A: post-build trigger on inventory-test)
PATTERN_A_TEST_DEPLOY=false
if echo "$TEST_CONFIG" | grep -q "hudson.tasks.BuildTrigger"; then
    TEST_CHILD_PROJECTS=$(echo "$TEST_CONFIG" | python3 -c "
import sys
from lxml import etree
try:
    tree = etree.parse(sys.stdin)
    triggers = tree.findall('.//publishers/hudson.tasks.BuildTrigger')
    for t in triggers:
        cp = t.find('childProjects')
        if cp is not None and cp.text:
            print(cp.text.strip())
except:
    pass
" 2>/dev/null || echo "")
    if echo "$TEST_CHILD_PROJECTS" | grep -qi "inventory-deploy"; then
        PATTERN_A_TEST_DEPLOY=true
    fi
fi

# Check for test→deploy trigger (Pattern B: reverse trigger on inventory-deploy)
PATTERN_B_TEST_DEPLOY=false
if echo "$DEPLOY_CONFIG" | grep -q "ReverseBuildTrigger"; then
    DEPLOY_UPSTREAM_PROJECTS=$(echo "$DEPLOY_CONFIG" | python3 -c "
import sys
from lxml import etree
try:
    tree = etree.parse(sys.stdin)
    triggers = tree.findall('.//triggers/jenkins.triggers.ReverseBuildTrigger')
    for t in triggers:
        up = t.find('upstreamProjects')
        if up is not None and up.text:
            print(up.text.strip())
except:
    pass
" 2>/dev/null || echo "")
    if echo "$DEPLOY_UPSTREAM_PROJECTS" | grep -qi "inventory-test"; then
        PATTERN_B_TEST_DEPLOY=true
    fi
fi

# Determine trigger methods
TRIGGER_BUILD_TEST=false
TRIGGER_METHOD_BT="none"
if [ "$PATTERN_A_BUILD_TEST" = "true" ]; then
    TRIGGER_BUILD_TEST=true
    TRIGGER_METHOD_BT="post-build-action"
fi
if [ "$PATTERN_B_BUILD_TEST" = "true" ]; then
    TRIGGER_BUILD_TEST=true
    TRIGGER_METHOD_BT="reverse-build-trigger"
fi
if [ "$PATTERN_A_BUILD_TEST" = "true" ] && [ "$PATTERN_B_BUILD_TEST" = "true" ]; then
    TRIGGER_METHOD_BT="both"
fi

TRIGGER_TEST_DEPLOY=false
TRIGGER_METHOD_TD="none"
if [ "$PATTERN_A_TEST_DEPLOY" = "true" ]; then
    TRIGGER_TEST_DEPLOY=true
    TRIGGER_METHOD_TD="post-build-action"
fi
if [ "$PATTERN_B_TEST_DEPLOY" = "true" ]; then
    TRIGGER_TEST_DEPLOY=true
    TRIGGER_METHOD_TD="reverse-build-trigger"
fi
if [ "$PATTERN_A_TEST_DEPLOY" = "true" ] && [ "$PATTERN_B_TEST_DEPLOY" = "true" ]; then
    TRIGGER_METHOD_TD="both"
fi

# Extract thresholds (check if SUCCESS, UNSTABLE, or FAILURE)
THRESHOLD_BT="unknown"
if [ "$PATTERN_A_BUILD_TEST" = "true" ]; then
    THRESHOLD_BT=$(echo "$BUILD_CONFIG" | python3 -c "
import sys
from lxml import etree
try:
    tree = etree.parse(sys.stdin)
    # Finding specific trigger
    trigger = tree.find('.//publishers/hudson.tasks.BuildTrigger')
    if trigger is not None:
        th = trigger.find('.//threshold/name')
        print(th.text.strip() if th is not None else 'SUCCESS')
    else:
        print('unknown')
except:
    print('unknown')
" 2>/dev/null)
elif [ "$PATTERN_B_BUILD_TEST" = "true" ]; then
    THRESHOLD_BT=$(echo "$TEST_CONFIG" | python3 -c "
import sys
from lxml import etree
try:
    tree = etree.parse(sys.stdin)
    trigger = tree.find('.//triggers/jenkins.triggers.ReverseBuildTrigger')
    if trigger is not None:
        th = trigger.find('.//threshold/name')
        print(th.text.strip() if th is not None else 'SUCCESS')
    else:
        print('unknown')
except:
    print('unknown')
" 2>/dev/null)
fi

THRESHOLD_TD="unknown"
if [ "$PATTERN_A_TEST_DEPLOY" = "true" ]; then
    THRESHOLD_TD=$(echo "$TEST_CONFIG" | python3 -c "
import sys
from lxml import etree
try:
    tree = etree.parse(sys.stdin)
    trigger = tree.find('.//publishers/hudson.tasks.BuildTrigger')
    if trigger is not None:
        th = trigger.find('.//threshold/name')
        print(th.text.strip() if th is not None else 'SUCCESS')
    else:
        print('unknown')
except:
    print('unknown')
" 2>/dev/null)
elif [ "$PATTERN_B_TEST_DEPLOY" = "true" ]; then
    THRESHOLD_TD=$(echo "$DEPLOY_CONFIG" | python3 -c "
import sys
from lxml import etree
try:
    tree = etree.parse(sys.stdin)
    trigger = tree.find('.//triggers/jenkins.triggers.ReverseBuildTrigger')
    if trigger is not None:
        th = trigger.find('.//threshold/name')
        print(th.text.strip() if th is not None else 'SUCCESS')
    else:
        print('unknown')
except:
    print('unknown')
" 2>/dev/null)
fi


# Check anti-gaming: configs must differ from baseline
echo "$BUILD_CONFIG" > /tmp/current_build.xml
echo "$TEST_CONFIG" > /tmp/current_test.xml
echo "$DEPLOY_CONFIG" > /tmp/current_deploy.xml

BUILD_CHANGED=false
TEST_CHANGED=false
DEPLOY_CHANGED=false

# Simple size comparison or diff
if ! diff -q /tmp/baseline_configs/inventory-build.xml /tmp/current_build.xml >/dev/null 2>&1; then BUILD_CHANGED=true; fi
if ! diff -q /tmp/baseline_configs/inventory-test.xml /tmp/current_test.xml >/dev/null 2>&1; then TEST_CHANGED=true; fi
if ! diff -q /tmp/baseline_configs/inventory-deploy.xml /tmp/current_deploy.xml >/dev/null 2>&1; then DEPLOY_CHANGED=true; fi

# Chain execution verification
CHAIN_SUCCESS=false
CHAIN_BUILD_RAN=false
CHAIN_TEST_RAN=false
CHAIN_DEPLOY_RAN=false

if [ "$TRIGGER_BUILD_TEST" = "true" ] && [ "$TRIGGER_TEST_DEPLOY" = "true" ]; then
    echo "Triggers detected. Verifying execution chain..."
    
    # Get current build numbers
    BN_BUILD=$(jenkins_api "job/inventory-build/api/json" | jq '.lastBuild.number // 0')
    BN_TEST=$(jenkins_api "job/inventory-test/api/json" | jq '.lastBuild.number // 0')
    BN_DEPLOY=$(jenkins_api "job/inventory-deploy/api/json" | jq '.lastBuild.number // 0')
    
    # Trigger first job
    jenkins_cli build inventory-build
    
    # Wait loop
    echo "Waiting for chain execution..."
    for i in {1..60}; do
        sleep 2
        CUR_BUILD=$(jenkins_api "job/inventory-build/api/json" | jq '.lastBuild.number // 0')
        CUR_TEST=$(jenkins_api "job/inventory-test/api/json" | jq '.lastBuild.number // 0')
        CUR_DEPLOY=$(jenkins_api "job/inventory-deploy/api/json" | jq '.lastBuild.number // 0')
        
        if [ "$CUR_BUILD" -gt "$BN_BUILD" ]; then CHAIN_BUILD_RAN=true; fi
        if [ "$CUR_TEST" -gt "$BN_TEST" ]; then CHAIN_TEST_RAN=true; fi
        if [ "$CUR_DEPLOY" -gt "$BN_DEPLOY" ]; then CHAIN_DEPLOY_RAN=true; fi
        
        # If all ran, check statuses
        if [ "$CHAIN_DEPLOY_RAN" = "true" ]; then
            # Wait a moment for deploy to finish
            STATUS=$(jenkins_api "job/inventory-deploy/lastBuild/api/json" | jq -r '.result')
            BUILDING=$(jenkins_api "job/inventory-deploy/lastBuild/api/json" | jq -r '.building')
            
            if [ "$BUILDING" = "false" ]; then
                if [ "$STATUS" = "SUCCESS" ]; then
                    CHAIN_SUCCESS=true
                fi
                break
            fi
        fi
    done
fi

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Construct JSON result
python3 -c "
import json
result = {
    'jobs_exist': {
        'inventory_build': '$BUILD_EXISTS' == 'true',
        'inventory_test': '$TEST_EXISTS' == 'true',
        'inventory_deploy': '$DEPLOY_EXISTS' == 'true'
    },
    'trigger_build_to_test': '$TRIGGER_BUILD_TEST' == 'true',
    'trigger_test_to_deploy': '$TRIGGER_TEST_DEPLOY' == 'true',
    'trigger_method_build_test': '$TRIGGER_METHOD_BT',
    'trigger_method_test_deploy': '$TRIGGER_METHOD_TD',
    'trigger_threshold_build_test': '$THRESHOLD_BT',
    'trigger_threshold_test_deploy': '$THRESHOLD_TD',
    'configs_changed': {
        'inventory_build': '$BUILD_CHANGED' == 'true',
        'inventory_test': '$TEST_CHANGED' == 'true',
        'inventory_deploy': '$DEPLOY_CHANGED' == 'true'
    },
    'chain_execution': {
        'build_ran': '$CHAIN_BUILD_RAN' == 'true',
        'test_ran': '$CHAIN_TEST_RAN' == 'true',
        'deploy_ran': '$CHAIN_DEPLOY_RAN' == 'true',
        'all_success': '$CHAIN_SUCCESS' == 'true'
    }
}
print(json.dumps(result, indent=2))
" > "$RESULT_FILE"

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="