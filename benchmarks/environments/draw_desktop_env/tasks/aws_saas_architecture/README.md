# aws_saas_architecture — AWS 3-Tier SaaS Architecture Diagram

## Domain Context

**Occupation**: Solutions Architect / Computer Systems Analyst ($2.5B top GDP occupation)

Solutions Architects create formal AWS architecture diagrams as deliverables for security review boards, procurement approvals, and infrastructure planning. A well-formed architecture diagram must use the official AWS icon shapes, clearly delineate VPC/subnet boundaries, show security group scopes, and document the data flow path — all of which are standard documentation artifacts in enterprise cloud deployments.

The AWS Well-Architected Framework defines the canonical patterns for 3-tier SaaS deployments (multi-tenant, multi-AZ, separate compute/data layers). This task reflects a real deliverable a Solutions Architect would produce for a client.

## Task Description

A Solutions Architect at a cloud consulting firm must produce a formal architecture diagram for a client's multi-tenant SaaS application on AWS, required by the client's security review board. The architecture requirements document is provided at `~/Desktop/saas_arch_requirements.txt`.

**End state**: A multi-page draw.io diagram (`~/Desktop/aws_architecture.drawio`) and a PNG export (`~/Desktop/aws_architecture.png`) that contain:
- A complete network topology: 1 VPC, 2 AZs, 4 subnets (2 public, 2 private), Internet Gateway, 2 NAT Gateways
- Compute layer: ALB in public subnets, 2 EC2 instances in private subnets, Auto Scaling Group
- Data layer: RDS Multi-AZ (PostgreSQL), ElastiCache Redis, S3 bucket
- Edge/CDN: CloudFront distribution, Route 53
- Security boundaries: dashed rectangles showing security group scopes for public/private/data zones
- A second page titled "Data Flow" with the request path: User → CloudFront → ALB → EC2 → RDS/ElastiCache

## Why This Is Hard

- The agent must use draw.io's AWS shape library (not built-in by default — must be enabled from Extra Shapes)
- 14 distinct AWS component types must be identified and placed correctly
- Understanding AWS networking hierarchy (VPC > AZ > subnet > instance) requires cloud architecture knowledge
- Security group boundaries must be drawn as dashed rectangles scoping specific resource sets
- Multi-AZ placement requires spatial organization across two parallel AZ columns
- Two distinct pages with different diagram types (topology map vs. sequence flow)

## Success Criteria

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| File saved after task start | 10 | Required (early exit if missing) |
| ≥15 total shapes | 15 | Partial: 6+ shapes = 6 pts |
| ≥8 connection edges | 10 | Partial: 4+ edges = 4 pts |
| ≥8 AWS component types identified | 25 | Partial: 5+ = 12 pts, 3+ = 5 pts |
| ≥2 diagram pages | 15 | — |
| Security zone dashed shapes (≥2) | 10 | — |
| PNG exported (≥2000 bytes) | 15 | Partial: any PNG = 5 pts |
| **Total** | **100** | **Pass: ≥60** |

## Verification Strategy

The verifier (`verify_aws_saas_architecture`):
1. Reads `/tmp/task_result.json` from `export_result.sh`
2. Checks file existence and modification timestamp
3. Counts AWS component types via keyword matching in shape labels and styles (vpc, subnet, ec2, rds, s3, alb, cloudfront, route53, elasticache, igw, nat, autoscaling, sg/securitygroup, elb)
4. Counts security zone rectangles via dashed style detection (`dashed=1`)
5. Counts total shapes and edges
6. Counts diagram pages
7. Checks PNG file existence and validates size

## Data Source

Based on the AWS Well-Architected Framework SaaS Lens and AWS Reference Architecture for multi-tenant web applications. Component names and configurations reflect real AWS service documentation.

**Key AWS components required**:
- VPC with CIDR block
- 4 subnets (public-1a, public-1b, private-1a, private-1b)
- Internet Gateway (IGW)
- NAT Gateway (in each public subnet)
- Application Load Balancer (ALB)
- EC2 instances (2, one per AZ)
- Auto Scaling Group
- RDS (PostgreSQL, Multi-AZ)
- ElastiCache (Redis)
- S3 bucket
- CloudFront distribution
- Route 53

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task specification, metadata, scoring hook |
| `setup_task.sh` | Creates `~/Desktop/saas_arch_requirements.txt`, records start timestamp, launches draw.io blank |
| `export_result.sh` | Parses draw.io XML for AWS keyword matches, dashed shapes, page count, PNG check |
| `verifier.py` | Multi-criterion scoring function `verify_aws_saas_architecture` |

## Edge Cases

- AWS shape libraries may use icon-style shapes (no text label) — verifier looks for both `label` text and style keywords
- Agent may use generic shapes instead of AWS-specific icons — scoring counts any shape with AWS service keywords in the label
- Security groups may be drawn as any bounding shape (rectangle, group, swimlane) — verifier checks for `dashed=1` style attribute
- A minimal diagram with only 3 AWS components correctly scores ~20 pts (below pass threshold)
