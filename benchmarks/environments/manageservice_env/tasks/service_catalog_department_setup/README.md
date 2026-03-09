# Task: service_catalog_department_setup

## Domain Context

**Occupation**: ITSM Administrator / IT Manager
**Industry**: Higher Education — Research University IT Services
**Why realistic**: Universities frequently onboard new departments or research groups that need dedicated IT support structures. Setting up the service catalog for a new department involves creating the organizational unit (department), the service taxonomy (categories and subcategories), the support team (technician group), and the intake mechanism (request template). This is a pure ITSM administration workflow requiring knowledge of 5+ different administrative configuration areas within ServiceDesk Plus.

---

## Goal

The Research Computing Services department has been formally established at the university and needs its IT support infrastructure configured in the ITSM system. The end state must include:

1. A **Department** named **"Research Computing Services"** in the organizational structure
2. A top-level **Service Category** named **"Research Computing"** for classifying research-related IT tickets
3. Three **subcategories** under "Research Computing":
   - **"HPC Cluster Access"**
   - **"Research Data Storage"**
   - **"Scientific Software"**
4. A **Technician Group** named **"Research Computing Support Team"**
5. A **Request Template** named **"HPC Cluster Access Request"** that uses the Research Computing category and HPC Cluster Access subcategory

---

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Department created | 15 | 'Research Computing Services' in system |
| Category created | 20 | 'Research Computing' top-level category exists |
| HPC Cluster Access subcategory | 10 | Subcategory under Research Computing |
| Research Data Storage subcategory | 10 | Subcategory under Research Computing |
| Scientific Software subcategory | 10 | Subcategory under Research Computing |
| Technician group created | 20 | 'Research Computing Support Team' group |
| Request template created | 15 | 'HPC Cluster Access Request' template |

**Pass threshold**: 60/100
**Difficulty**: very_hard

---

## Verification Strategy

The `export_result.sh` script:
1. Queries PostgreSQL for departments: `department`, `sdorg`, or similar tables, matching 'research computing%'
2. Queries for categories: `categorydefn` or `category` tables matching 'research computing'
3. Queries for subcategories: looks for 'hpc%cluster%', '%data%storage%', '%scientific%software%' (or similar tables)
4. Queries for technician groups: `supportgroup` table matching 'research computing support%'
5. Queries for request templates: `requesttemplate` or `workordertemplate` table matching 'hpc cluster access request'
6. Cross-checks each via REST API: `GET /api/v3/categories`, `/api/v3/subcategories`, `/api/v3/departments`, `/api/v3/groups`, `/api/v3/request_templates`
7. Writes all results to `/tmp/service_catalog_department_setup_result.json`

The `verifier.py` function `verify_service_catalog_department_setup`:
- **Wrong-target gate**: If neither the category NOR the department exists → score=0
- Individual binary criteria for each of the 7 items
- Subcategory names are matched case-insensitively with keywords: 'hpc', 'storage', 'software'

---

## Schema Reference

**Key tables (PostgreSQL, port 65432, database `servicedesk`):**

```sql
-- Departments
SELECT * FROM department WHERE LOWER(deptname) LIKE '%research computing%';
-- or: SELECT * FROM sdorg WHERE LOWER(name) LIKE '%research computing%';

-- Categories
SELECT * FROM categorydefn WHERE LOWER(categoryname) LIKE '%research computing%';

-- Subcategories
SELECT * FROM subcategorydefn WHERE parentcategoryid = <category_id>;

-- Technician Groups
SELECT * FROM supportgroup WHERE LOWER(groupname) LIKE '%research computing support%';

-- Request Templates
SELECT * FROM requesttemplate WHERE LOWER(templatename) LIKE '%hpc cluster access%';
-- or: SELECT * FROM workordertemplate WHERE LOWER(name) LIKE '%hpc cluster access%';
```

**REST API (https://localhost:8080/api/v3/):**
- `GET /api/v3/categories` — list service categories
- `GET /api/v3/subcategories` — list subcategories (may accept category_id parameter)
- `GET /api/v3/departments` — list departments
- `GET /api/v3/groups` — list technician groups
- `GET /api/v3/request_templates` — list request templates

---

## Pre-existing Data

None of the target items exist in the baseline system. The categories present at baseline are default ones (Hardware, Software, Network, etc.) that came with the SDP installation.

---

## Edge Cases and Potential Issues

- **Admin navigation**: All 5 deliverables are in different sections of the Admin panel. The agent must discover: Admin > Organizational Details > Departments, Admin > Helpdesk > Categories, Admin > Helpdesk > Subcategories, Admin > Helpdesk > Technician Groups, Admin > Helpdesk > Request Templates.
- **Subcategory dependency**: Subcategories can only be created after the parent category exists. The agent must create the category first.
- **Template category linkage**: When creating the HPC Cluster Access Request template, the agent must set the Category to "Research Computing" and Subcategory to "HPC Cluster Access" — these dropdowns only appear after the category/subcategory exist.
- **Table name uncertainty**: SDP uses different table names across versions for departments (could be `department`, `sdorg`, or `orgdetails`). The export script tries multiple names.
- **Subcategory keyword matching**: The verifier uses keyword matching ('hpc' for HPC Cluster Access, 'storage' for Research Data Storage, 'software' for Scientific Software) to tolerate minor naming variations.
