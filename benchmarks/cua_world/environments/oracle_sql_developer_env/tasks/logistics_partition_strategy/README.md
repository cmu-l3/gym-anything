# Logistics Shipment Database Partitioning Strategy (`logistics_partition_strategy@1`)

## Overview
This task evaluates the agent's ability to implement Oracle table partitioning strategies on a logistics shipment tracking database. The agent must convert large unpartitioned tables to range-partitioned, list-partitioned, and composite-partitioned structures, build local partitioned indexes, perform partition exchange loading, and demonstrate partition pruning.

## Rationale
**Why this task is valuable:**
- Tests deep Oracle-specific partitioning knowledge
- Requires understanding of data migration strategies for production tables
- Evaluates ability to create and validate local partitioned indexes
- Tests partition exchange loading — a critical bulk-load optimization technique
- Verifies understanding of partition pruning via execution plans

**Real-world Context:** A logistics analyst must implement partitioning to restore query performance on a massive shipment events table without disrupting ongoing operations.

## Task Description
**Goal:** Convert the LOGISTICS_MGR schema's large unpartitioned tables into properly partitioned structures, create local indexes, perform a partition exchange load, and demonstrate partition pruning.

**Starting State:**
Oracle SQL Developer is open and maximized. The `LOGISTICS_MGR` schema contains 5 tables: CARRIERS, REGIONS, WAREHOUSES, SHIPMENTS (~50,000 rows), and SHIPMENT_EVENTS (~500,000 rows).

**Expected Actions:**
1. Create `SHIPMENT_EVENTS_PART` (Range-partitioned by event_date, 24 monthly + 1 FUTURE) and migrate data.
2. Create `SHIPMENTS_PART` (List-partitioned by dest_region, 5 partitions) and migrate data.
3. Create `SHIPMENT_ANALYTICS` (Composite: Range by created_date, List by dest_region) and populate.
4. Create 3 local indexes (`IDX_EVENTS_PART_SHIPID`, `IDX_SHIPMENTS_PART_CARRIER`, `IDX_ANALYTICS_PART_CREATED`).
5. Create `EVENTS_STAGING`, insert 2025 data, and `EXCHANGE PARTITION P_FUTURE`.
6. Create view `PARTITION_STATS_VW` using `USER_TAB_PARTITIONS`.
7. Generate an `EXPLAIN PLAN` showing partition pruning and save to `/home/ga/Documents/exports/partition_pruning_plan.txt`.

## Verification Strategy
### Primary Verification: Database Metadata Queries
The verifier queries Oracle data dictionary views (`USER_PART_TABLES`, `USER_TAB_PARTITIONS`, `USER_PART_INDEXES`) to validate all structural requirements and row counts.

### Secondary Verification: VLM and GUI Evidence
- Analyzes SQL Developer GUI usage via history files and session states.
- VLM checks trajectory frames to ensure the agent actively worked in the SQL Developer interface.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| SHIPMENT_EVENTS_PART | 25 | Range partitioned, 25 partitions, data migrated |
| SHIPMENTS_PART | 15 | List partitioned, 5 partitions, data migrated |
| SHIPMENT_ANALYTICS | 15 | Composite partitioned, populated |
| Local Indexes | 10 | 3 LOCAL indexes created |
| Partition Exchange | 10 | P_FUTURE contains staging data |
| PARTITION_STATS_VW | 5 | View exists |
| Pruning Plan | 10 | Plan file exported with PARTITION RANGE |
| VLM & GUI Usage | 10 | Real interactions proven |
| **Total** | **100** | |

Pass Threshold: 65 points with at least basic partition structures created.