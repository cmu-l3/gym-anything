#!/bin/bash
# Do NOT use set -e

echo "=== Setting up aws_saas_architecture task ==="

# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Clean up any previous outputs
rm -f /home/ga/Desktop/aws_architecture.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/aws_architecture.png 2>/dev/null || true

# Create architecture requirements document.
# Based on AWS Well-Architected Framework reference architecture for multi-tenant SaaS
# (https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/welcome.html)
cat > /home/ga/Desktop/saas_arch_requirements.txt << 'REQEOF'
AWS SaaS Architecture Requirements
===================================
Client: Meridian Analytics Inc.
Document Type: Cloud Architecture Specification
Reference: AWS Well-Architected Framework (SaaS Lens)
Review: Security Board Pre-Launch Review

REQUIRED ARCHITECTURE COMPONENTS
----------------------------------

1. REGION & NETWORK LAYER
   - AWS Region: us-east-1
   - 1 x Virtual Private Cloud (VPC): CIDR 10.0.0.0/16
   - 2 x Availability Zones: us-east-1a, us-east-1b
   - Public Subnets:  10.0.1.0/24 (AZ-a), 10.0.2.0/24 (AZ-b)
   - Private Subnets: 10.0.11.0/24 (AZ-a), 10.0.12.0/24 (AZ-b)
   - 1 x Internet Gateway (IGW) attached to VPC
   - 2 x NAT Gateways (one per public subnet) for private subnet egress

2. COMPUTE LAYER
   - 1 x Application Load Balancer (ALB) — spans both public subnets
   - 2 x EC2 instances (t3.large) — one in each private subnet
   - 1 x Auto Scaling Group (ASG) — wraps both EC2 instances (min=2, max=10)
   - Instance type: Amazon Linux 2, running Docker containers

3. DATA LAYER
   - 1 x Amazon RDS Multi-AZ (PostgreSQL 14) — private subnets
     Primary in AZ-a, Standby in AZ-b
   - 1 x Amazon ElastiCache (Redis, cluster mode) — private subnets
   - 1 x Amazon S3 Bucket — static assets & user uploads

4. EDGE / CDN LAYER
   - 1 x Amazon CloudFront Distribution — in front of ALB
   - 1 x Amazon Route 53 Hosted Zone — DNS management

5. SECURITY BOUNDARIES (show as dashed-border rectangles/zones)
   - Security Group A: Public Subnet Zone (ALB, NAT GW)
   - Security Group B: Application Zone (EC2 instances, ASG)
   - Security Group C: Data Zone (RDS, ElastiCache)

6. ADDITIONAL SERVICES
   - AWS WAF attached to CloudFront
   - AWS Certificate Manager (ACM) for TLS
   - Amazon CloudWatch for monitoring

DIAGRAM REQUIREMENTS
---------------------
Page 1 — "Architecture Overview":
  - All components above drawn with AWS-standard shapes
  - Security group boundaries as dashed rectangles
  - Network connections between all components
  - Subnet/AZ labels clearly visible

Page 2 — "Data Flow":
  - Sequence of labeled arrows showing request path:
    Internet User → CloudFront → ALB → EC2 (App Tier) → RDS (DB write)
                                                       → ElastiCache (cache hit)
    S3 → CloudFront → Internet User (static assets path)

OUTPUT FILES:
  ~/Desktop/aws_architecture.drawio  (draw.io source)
  ~/Desktop/aws_architecture.png     (PNG export of Page 1)
REQEOF

chown ga:ga /home/ga/Desktop/saas_arch_requirements.txt 2>/dev/null || true
echo "Requirements file created: /home/ga/Desktop/saas_arch_requirements.txt"

# Record baseline
INITIAL_COUNT=$(ls /home/ga/Desktop/*.drawio 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_drawio_count
date +%s > /tmp/task_start_timestamp

# Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_aws.log 2>&1 &"

echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i}s"
        break
    fi
    sleep 1
done

sleep 5
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Press Escape for blank canvas
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

DISPLAY=:1 import -window root /tmp/aws_arch_start.png 2>/dev/null || true

echo "=== Setup complete: requirements at ~/Desktop/saas_arch_requirements.txt, draw.io running ==="
