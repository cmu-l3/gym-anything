#!/bin/bash
set -e
echo "=== Setting up fix_cloud_backup_rotator ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Install dependencies
# Using pip from the environment
pip3 install boto3 moto pytest --quiet

# Create project structure
PROJECT_DIR="/home/ga/PycharmProjects/cloud_rotator"
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$PROJECT_DIR/rotator"
mkdir -p "$PROJECT_DIR/tests"

# --- 1. Create Source Code with Bugs ---
cat > "$PROJECT_DIR/rotator/__init__.py" << 'EOF'
EOF

cat > "$PROJECT_DIR/rotator/client.py" << 'EOF'
import boto3

def get_s3_client():
    """Returns a standard S3 client."""
    return boto3.client('s3', region_name='us-east-1')
EOF

cat > "$PROJECT_DIR/rotator/policy.py" << 'EOF'
import logging
from .client import get_s3_client

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def apply_retention_policy(bucket_name, retention_count=5):
    """
    Enforces retention policy on an S3 bucket.
    
    Rules:
    1. Keep the 'retention_count' most recent objects (by LastModified).
    2. Delete all older objects.
    3. NEVER delete objects in 'GLACIER' or 'DEEP_ARCHIVE' storage classes.
    
    Args:
        bucket_name (str): Name of the S3 bucket.
        retention_count (int): Number of most recent backups to keep.
    """
    s3 = get_s3_client()
    
    # 1. List all objects (Handling pagination for large buckets)
    all_objects = []
    continuation_token = None
    
    while True:
        # BUG 1: Pagination implementation is incomplete
        # We check IsTruncated but we never pass the ContinuationToken to the next call properly
        # in the loop logic below.
        if continuation_token:
             response = s3.list_objects_v2(Bucket=bucket_name, ContinuationToken=continuation_token)
        else:
             response = s3.list_objects_v2(Bucket=bucket_name)
        
        if 'Contents' in response:
            all_objects.extend(response['Contents'])
        
        if not response.get('IsTruncated'):
            break
            
        # BUG: Missing line to update token!
        # continuation_token = response.get('NextContinuationToken')
    
    logger.info(f"Found {len(all_objects)} objects in bucket {bucket_name}")
    
    if not all_objects:
        return

    # 2. Sort objects by LastModified (Descending: Newest first)
    # This part is correct
    sorted_objects = sorted(
        all_objects, 
        key=lambda k: k['LastModified'], 
        reverse=True
    )
    
    # 3. Identify objects to delete
    # BUG 2: Slicing logic is inverted.
    # sorted_objects[:retention_count] are the NEWEST files (the ones we want to KEEP).
    # We are selecting them for DELETION.
    objects_to_delete = sorted_objects[:retention_count]
    
    # Perform Deletion
    if objects_to_delete:
        delete_keys = []
        for obj in objects_to_delete:
            # BUG 3: Missing check for GLACIER storage class
            # Should be: if obj.get('StorageClass') in ['GLACIER', 'DEEP_ARCHIVE']: continue
            
            delete_keys.append({'Key': obj['Key']})
            
        if delete_keys:
            # Batch delete in chunks of 1000 (S3 limit)
            for i in range(0, len(delete_keys), 1000):
                batch = delete_keys[i:i+1000]
                logger.info(f"Deleting {len(batch)} objects...")
                s3.delete_objects(
                    Bucket=bucket_name,
                    Delete={'Objects': batch}
                )
                
    logger.info("Retention policy application complete.")
EOF

# --- 2. Create Tests (Ground Truth) ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest
from moto import mock_aws
import boto3
import os

@pytest.fixture(scope='function')
def aws_credentials():
    """Mocked AWS Credentials for moto."""
    os.environ['AWS_ACCESS_KEY_ID'] = 'testing'
    os.environ['AWS_SECRET_ACCESS_KEY'] = 'testing'
    os.environ['AWS_SECURITY_TOKEN'] = 'testing'
    os.environ['AWS_SESSION_TOKEN'] = 'testing'
    os.environ['AWS_DEFAULT_REGION'] = 'us-east-1'

@pytest.fixture(scope='function')
def s3_mock(aws_credentials):
    with mock_aws():
        yield boto3.client('s3', region_name='us-east-1')
EOF

cat > "$PROJECT_DIR/tests/test_policy.py" << 'EOF'
import boto3
import pytest
from rotator.policy import apply_retention_policy

def test_retention_keeps_newest(s3_mock):
    """Verify that the N newest objects are kept and older ones deleted."""
    bucket = "test-retention"
    s3_mock.create_bucket(Bucket=bucket)
    
    # Create 10 objects. In moto, subsequent puts generally have >= timestamps
    # keys: backup_0 ... backup_9
    # backup_9 is the 'newest'
    for i in range(10):
        key = f"backup_{i}.tar.gz"
        s3_mock.put_object(Bucket=bucket, Key=key, Body=b"data")
    
    # Keep 3. We expect backup_9, backup_8, backup_7 to remain.
    apply_retention_policy(bucket, retention_count=3)
    
    resp = s3_mock.list_objects_v2(Bucket=bucket)
    remaining = [obj['Key'] for obj in resp.get('Contents', [])]
    
    assert len(remaining) == 3, f"Expected 3 items, found {len(remaining)}"
    assert "backup_9.tar.gz" in remaining
    assert "backup_8.tar.gz" in remaining
    assert "backup_7.tar.gz" in remaining
    assert "backup_0.tar.gz" not in remaining

def test_skips_glacier(s3_mock):
    """Verify that GLACIER objects are never deleted."""
    bucket = "test-glacier"
    s3_mock.create_bucket(Bucket=bucket)
    
    # Create an old Glacier object (simulate archive)
    s3_mock.put_object(Bucket=bucket, Key="archive_old.dat", Body=b"archived", StorageClass='GLACIER')
    
    # Create 5 standard objects (newer)
    for i in range(5):
        s3_mock.put_object(Bucket=bucket, Key=f"recent_{i}.dat", Body=b"data")
        
    # Policy: Keep 2.
    # Logic:
    # 1. List all -> 6 objects.
    # 2. Sort by date -> recent_4, ..., recent_0, archive_old
    # 3. Identify delete candidates: 
    #    If correct: candidates are recent_2, recent_1, recent_0, archive_old.
    # 4. Filter: Skip archive_old. Delete recent_2, recent_1, recent_0.
    # Result: recent_4, recent_3, archive_old remain.
    
    apply_retention_policy(bucket, retention_count=2)
    
    resp = s3_mock.list_objects_v2(Bucket=bucket)
    remaining = [obj['Key'] for obj in resp.get('Contents', [])]
    
    assert "archive_old.dat" in remaining, "Glacier object was incorrectly deleted!"
    assert len(remaining) == 3 # 2 retained standard + 1 glacier

def test_large_bucket_pagination(s3_mock):
    """Verify that buckets with >1000 items are processed correctly."""
    bucket = "test-pagination"
    s3_mock.create_bucket(Bucket=bucket)
    
    # Create 1100 items to trigger pagination (Moto page size is 1000)
    for i in range(1100):
        s3_mock.put_object(Bucket=bucket, Key=f"log_{i:04d}.txt", Body=b"x")
        
    # Apply policy: Keep 100. Should delete 1000.
    # If pagination fails, it might loop infinitely or only see 1000 items.
    apply_retention_policy(bucket, retention_count=100)
    
    paginator = s3_mock.get_paginator('list_objects_v2')
    count_after = sum(1 for _ in paginator.paginate(Bucket=bucket).search('Contents[]'))
    
    assert count_after == 100, f"Expected 100 items, found {count_after}. Pagination likely broken."
EOF

# --- 3. Create Supporting Files ---
cat > "$PROJECT_DIR/main.py" << 'EOF'
import sys
from rotator.policy import apply_retention_policy

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python main.py <bucket_name> [retention_count]")
        sys.exit(1)
    
    bucket = sys.argv[1]
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    apply_retention_policy(bucket, count)
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch PyCharm
if [ -f /opt/pycharm/bin/pycharm.sh ]; then
    su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh $PROJECT_DIR > /dev/null 2>&1 &"
    
    # Wait for PyCharm
    wait_for_pycharm 60
    
    # Focus and maximize
    focus_pycharm_window
fi

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="