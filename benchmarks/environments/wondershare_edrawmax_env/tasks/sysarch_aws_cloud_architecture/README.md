# Task: sysarch_aws_cloud_architecture

## Domain Context

Cloud Systems Architects use diagramming tools like EdrawMax to produce Architecture Review Board (ARB) documentation before deploying infrastructure. A 3-tier AWS architecture diagram is one of the most common deliverables in cloud migration projects. The diagram must communicate multi-AZ redundancy, tier separation, and network boundaries to both technical and non-technical stakeholders.

## Occupation

**Computer Systems Engineers / Architects** (top EdrawMax user group by economic impact)

## Task Overview

Design a production-grade 3-tier AWS cloud architecture diagram in EdrawMax across 2 pages and save it as `/home/ga/aws_cloud_architecture.eddx`.

## Goal / End State

The completed file must contain:

- **Page 1**: Primary Region AWS architecture showing 3 tiers (Presentation/Web, Application, Data) deployed across 2 Availability Zones, with VPC/subnet boundaries, load balancers, compute instances, managed databases, and object storage. AWS-specific shape icons from EdrawMax's AWS library should be used where available.
- **Page 2**: Disaster Recovery (DR) or Multi-Region failover architecture showing how the system remains available if one AZ or region fails.
- A consistent professional theme applied.

## Difficulty

**very_hard** — Goal and end-state structure are provided, but no UI navigation hints. Agent must discover EdrawMax's AWS shape library, know how to set up VPC boundary containers, place shapes in the correct tier groupings, and configure a second page for the DR architecture.

## Success Criteria

| Criterion | Points | What is checked |
|-----------|--------|-----------------|
| A: Valid EDDX archive | 15 | File exists at correct path, valid ZIP |
| B: Modified after task start | 10 | File mtime > task start timestamp |
| C: Multi-page (≥ 2 pages) | 20 | Archive contains ≥ 2 page XML files |
| D: AWS/cloud keywords | 15 | ≥ 4 cloud service keywords (ec2, vpc, rds, subnet, elb, etc.) in XML |
| E: Shape density | 20 | ≥ 12 Shape elements AND ≥ 6 ConnectLine elements |
| F: Three-tier evidence | 10 | Keywords for all 3 tiers: web/frontend, app/backend, data/db |
| G: Page 2 content | 10 | ≥ 4 text elements on page 2 |

**Pass threshold: 60/100**

## Verification Strategy

`verifier.py::verify_sysarch_aws_cloud_architecture` — copies and parses EDDX ZIP, scans all XML for AWS service keywords in shape labels and NameU attributes, counts pages, shapes, and connectors.

## Anti-Gaming

- `setup_task.sh` deletes `/home/ga/aws_cloud_architecture.eddx` and records start timestamp before launching EdrawMax.

## Edge Cases

- Agent may use generic labeled shapes instead of AWS icons — verifier checks text content (Chars values) not just NameU, so labeled shapes with AWS service names will still pass criterion D.
- Agent may omit the DR page — criteria C (20 pts) and G (10 pts) fail.
- Agent may not know EdrawMax's AWS shape library — will fall back to generic shapes; criterion D will still award points if AWS terms appear as text labels.
