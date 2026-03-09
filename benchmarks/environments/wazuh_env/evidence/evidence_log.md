# Wazuh Environment Evidence Log

**Date:** 2026-02-18
**Environment:** wazuh_env@0.1
**VM SSH Port:** 2351, VNC Port:** 6018

---

## Environment Health (post_start complete)

### Docker Containers
```
wazuh-wazuh.dashboard-1    Up 10+ minutes  443/tcp -> 5601/tcp
wazuh-wazuh.indexer-1      Up 10+ minutes  9200/tcp
wazuh-wazuh.manager-1      Up 10+ minutes  1514,1515,55000/tcp
```

### Wazuh Indexer Health
```json
{"status": "green", "number_of_nodes": 1, "number_of_data_nodes": 1, "active_primary_shards": 11}
```

### API Status
- API user `wazuh-wui` JWT authentication: **WORKING** (token prefix: `eyJhbGciOiJFUzU1...`)
- Dashboard login `admin`/`SecretPassword`: **WORKING**

### Real Alert Data
```json
{"count": 187}  // Real Wazuh alerts in wazuh-alerts-* indices
```
Alert severity breakdown (dashboard Overview):
- Critical (level 15+): 0
- High (level 12-14): 0
- Medium (level 7-11): 46
- Low (level 0-6): 141

### SCA Compliance Data (Agent 000 - wazuh-manager)
```json
{
  "policy": "CIS Benchmark for Amazon Linux 2023 Benchmark v1.0.0",
  "score": 52,
  "pass": 51,
  "fail": 46,
  "invalid": 87,
  "end_scan": "2026-02-18T05:21:13+00:00"
}
```

### Agent Groups (pre-created)
- database-servers (0 agents)
- default (0 agents)
- linux-servers (0 agents)
- web-servers (0 agents)
- windows-workstations (0 agents)
- *Note: `dmz-servers` group is NOT present (task start state for `add_agent_group` task)*

---

## Task Start State Verification

### Task: add_agent_group
- **Start URL:** `https://localhost/app/endpoint-groups#/manager/?tab=groups`
- **Start state:** Groups management page showing 5 groups (no `dmz-servers`)
- **Screenshot:** `02_task_add_agent_group_start.png` ✓
- **Task correctness:** Agent must create `dmz-servers` group via "Add new group" button

### Task: create_custom_rule
- **Start URL:** `https://localhost/app/rules#/manager/tab=ruleset`
- **Start state:** Rules page showing 4484 rules, Custom rules tab visible
- **Screenshot:** `03_task_create_custom_rule_start.png` ✓
- **local_rules.xml reset:** Contains rules 100001, 100002, 100003 but NOT 100010
- **Task correctness:** Agent must add rule 100010 (level 9, if_sid 5710) via editor

### Task: configure_email_alerts
- **Start URL:** `https://localhost/app/settings#/manager/?tab=configuration`
- **Start state:** Configuration overview page with "Edit configuration" button
- **Screenshot:** `04_task_configure_email_alerts_start.png` ✓
- **Reset state:** email_notification=no in ossec.conf
- **Task correctness:** Agent must enable email alerts with specific SMTP settings

### Task: manage_sca_policy
- **Start URL:** `https://localhost/app/configuration-assessment#/overview/?tab=sca&agentId=000`
- **Start state:** CIS Benchmark SCA results: 51 passed, 46 failed, 52% score
- **Screenshot:** `05_task_manage_sca_policy_start.png` ✓
- **Task correctness:** Agent must filter to failed checks and view remediation for one

### Task: check_agent_status
- **Start URL:** `https://localhost/app/configuration-assessment#/overview/?tab=sca&agentId=000`
- **Start state:** CIS Benchmark SCA dashboard with compliance statistics
- **Screenshot:** `06_task_check_agent_status_start.png` ✓
- **Task correctness:** Agent must click Checks tab and expand a failed check's detail

---

## Screenshots Index
1. `01_dashboard_main.png` - Wazuh main dashboard (Overview) after login
2. `02_task_add_agent_group_start.png` - Groups page (no dmz-servers group)
3. `03_task_create_custom_rule_start.png` - Rules management page
4. `04_task_configure_email_alerts_start.png` - Configuration Settings page
5. `05_task_manage_sca_policy_start.png` - SCA checks for agent 000
6. `06_task_check_agent_status_start.png` - SCA dashboard for agent 000
