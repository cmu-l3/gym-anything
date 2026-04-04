#!/bin/bash
set -e

echo "=== Setting up AWS HA Architecture Migration Task ==="

# 1. Create Directories
mkdir -p /home/ga/Diagrams
mkdir -p /home/ga/Desktop

# 2. Create the Findings Document
cat > /home/ga/Desktop/wa_review_findings.txt << 'EOF'
AWS WELL-ARCHITECTED REVIEW - FINDINGS REPORT
Company: StartupCo
Date: 2024-11-15
Severity: HIGH

Finding REL-001: Single Availability Zone Deployment
  Current: All resources deployed in a single AZ (us-east-1a).
  Risk: Complete service outage if AZ becomes unavailable.
  Action: Add a second AZ (AZ-b) with mirrored public and private subnets.

Finding REL-002: No Load Balancing
  Current: Route 53 points directly to a single EC2 instance public IP.
  Risk: No failover capability, no health checks.
  Action: Add an Application Load Balancer (ALB) in public subnets spanning both AZs.

Finding REL-003: No Auto Scaling
  Current: Single EC2 instance ("web-app-01").
  Risk: Cannot handle traffic spikes; single point of failure.
  Action: Replace single EC2 with an Auto Scaling Group (ASG) spanning both AZs.

Finding REL-004: Single-AZ Database
  Current: RDS MySQL in single-AZ mode.
  Action: Update RDS label to indicate "Multi-AZ" deployment.

Finding PERF-001: No CDN / Edge Caching
  Current: Direct access to origin.
  Action: Add Amazon CloudFront distribution in front of the ALB.

Finding PERF-002: No In-Memory Caching
  Current: No caching layer.
  Action: Add ElastiCache Redis node in private subnet.

Finding SEC-001: No NAT Gateway
  Current: Private subnet has no internet access for patches.
  Action: Add NAT Gateway in public subnet(s).

DELIVERABLE:
- Update the architecture diagram in ~/Diagrams/startup_aws_arch.drawio
- Export the final design to ~/Diagrams/startup_aws_arch.pdf
EOF

# 3. Create the Starter Diagram (Single AZ)
# This XML represents a basic VPC with 1 AZ, 1 EC2, 1 RDS, 1 S3
cat > /home/ga/Diagrams/startup_aws_arch.drawio << 'EOF'
<mxfile host="Electron" modified="2024-01-01T10:00:00.000Z" agent="Mozilla/5.0" version="22.1.0" type="device">
  <diagram id="aws-starter" name="Page-1">
    <mxGraphModel dx="1422" dy="800" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <mxCell id="vpc" value="VPC" style="group;whiteSpace=wrap;html=1;container=1;" vertex="1" parent="1">
          <mxGeometry x="120" y="120" width="480" height="400" as="geometry" />
        </mxCell>
        <mxCell id="az-a" value="Availability Zone A" style="group;whiteSpace=wrap;html=1;container=1;dashed=1;" vertex="1" parent="vpc">
          <mxGeometry x="20" y="40" width="440" height="340" as="geometry" />
        </mxCell>
        <mxCell id="pub-sub" value="Public Subnet" style="group;whiteSpace=wrap;html=1;container=1;fillColor=#dae8fc;strokeColor=#6c8ebf;" vertex="1" parent="az-a">
          <mxGeometry x="20" y="30" width="400" height="120" as="geometry" />
        </mxCell>
        <mxCell id="ec2" value="EC2 Instance" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#ffcc99;strokeColor=#36393d;" vertex="1" parent="pub-sub">
          <mxGeometry x="140" y="40" width="120" height="60" as="geometry" />
        </mxCell>
        <mxCell id="priv-sub" value="Private Subnet" style="group;whiteSpace=wrap;html=1;container=1;fillColor=#d5e8d4;strokeColor=#82b366;" vertex="1" parent="az-a">
          <mxGeometry x="20" y="180" width="400" height="120" as="geometry" />
        </mxCell>
        <mxCell id="rds" value="RDS MySQL" style="shape=cylinder3;whiteSpace=wrap;html=1;boundedLbl=1;backgroundOutline=1;size=15;fillColor=#ffe6cc;strokeColor=#d79b00;" vertex="1" parent="priv-sub">
          <mxGeometry x="150" y="30" width="100" height="70" as="geometry" />
        </mxCell>
        <mxCell id="igw" value="Internet Gateway" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#f8cecc;strokeColor=#b85450;" vertex="1" parent="vpc">
          <mxGeometry x="400" y="10" width="100" height="40" as="geometry" />
        </mxCell>
        <mxCell id="s3" value="S3 Bucket" style="shape=cylinder3;whiteSpace=wrap;html=1;boundedLbl=1;backgroundOutline=1;size=15;fillColor=#e1d5e7;strokeColor=#9673a6;" vertex="1" parent="1">
          <mxGeometry x="640" y="200" width="80" height="80" as="geometry" />
        </mxCell>
        <mxCell id="r53" value="Route 53" style="ellipse;whiteSpace=wrap;html=1;fillColor=#fff2cc;strokeColor=#d6b656;" vertex="1" parent="1">
          <mxGeometry x="40" y="40" width="80" height="80" as="geometry" />
        </mxCell>
        <mxCell id="users" value="Users" style="ellipse;shape=cloud;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="20" y="150" width="80" height="60" as="geometry" />
        </mxCell>
        <mxCell id="edge1" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;" edge="1" parent="1" source="users" target="igw">
          <mxGeometry relative="1" as="geometry" />
        </mxCell>
        <mxCell id="edge2" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;" edge="1" parent="1" source="igw" target="ec2">
          <mxGeometry relative="1" as="geometry" />
        </mxCell>
        <mxCell id="edge3" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;" edge="1" parent="1" source="ec2" target="rds">
          <mxGeometry relative="1" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF

# Set permissions
chown ga:ga /home/ga/Desktop/wa_review_findings.txt
chown ga:ga /home/ga/Diagrams/startup_aws_arch.drawio
chmod 644 /home/ga/Desktop/wa_review_findings.txt
chmod 644 /home/ga/Diagrams/startup_aws_arch.drawio

# 4. Record Initial State (Anti-Gaming)
date +%s > /tmp/task_start_time.txt
grep -c '<mxCell' /home/ga/Diagrams/startup_aws_arch.drawio > /tmp/initial_cell_count.txt

# 5. Launch Application
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/startup_aws_arch.drawio > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Dismiss Update Dialog (Aggressive)
echo "Dismissing update dialogs..."
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape
    sleep 0.5
done

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="