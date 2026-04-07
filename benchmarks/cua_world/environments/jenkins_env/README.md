# Jenkins CI/CD Environment for Gym-Anything

A complete Jenkins automation server environment for testing AI agents' ability to interact with continuous integration and deployment workflows.

## Overview

This environment provides a fully functional Jenkins server running in Docker-in-QEMU, accessible through a web browser interface. Agents can create jobs, configure pipelines, trigger builds, and interact with real CI/CD workflows.

## Features

- **Jenkins LTS 2.x** with Java 21 runtime
- **Docker-in-QEMU** architecture for HPC compatibility
- **Pre-configured admin access** (no manual setup wizard)
- **Firefox** with optimized profile for Jenkins UI
- **Real GitHub integration** using official Jenkins tutorial repositories
- **REST API** and **CLI** utilities for programmatic verification

## Quick Start

```python
from gym_anything.api import from_config

# Start Jenkins environment with a specific task
env = from_config("examples/jenkins_env", task_id="create_freestyle_job")
obs = env.reset(seed=42, use_cache=False)

# Environment is now ready with Jenkins running at http://localhost:8080
# Admin credentials: admin / Admin123!
```

## Environment Specification

- **Base Image:** ubuntu-gnome-systemd_highres (1920x1080)
- **Resources:** 4 CPU, 8GB RAM
- **Network:** Required (Docker image pull, GitHub access)
- **Services:** Jenkins (port 8080), Docker daemon

## Tasks

### 1. Create Freestyle Job (`create_freestyle_job`)
**Difficulty:** Easy
**Goal:** Create a simple freestyle Jenkins job that executes a shell command

**Task Description:**
> Create a new freestyle Jenkins job named 'HelloWorld-Build' that executes a simple shell command to echo 'Hello from Jenkins!'. Login credentials: Username: admin, Password: Admin123!

**Verification Criteria:**
- Job exists in Jenkins
- Job name matches (case-insensitive)
- Job has shell build step configured
- Shell command contains expected text

### 2. Create Pipeline Job (`create_pipeline_job`)
**Difficulty:** Medium
**Goal:** Create a Pipeline job that builds a Java application from GitHub

**Task Description:**
> Create a new Pipeline job named 'Maven-Build-Pipeline' that builds a Java application from GitHub. Configure it to use the repository: https://github.com/jenkins-docs/simple-java-maven-app and use the Jenkinsfile in the repository. Login credentials: Username: admin, Password: Admin123!

**Real Data Source:**
- Repository: `jenkins-docs/simple-java-maven-app`
- Official Jenkins tutorial repository
- Contains real Java Maven application with tests
- Includes production Jenkinsfile

**Verification Criteria:**
- Job exists and is Pipeline type (WorkflowJob)
- SCM configured as Git
- Repository URL matches expected GitHub repo
- Script path set to Jenkinsfile

### 3. Trigger Build (`trigger_build`)
**Difficulty:** Easy
**Goal:** Manually trigger a Jenkins build and verify completion

**Task Description:**
> Find an existing Jenkins job and trigger a build manually. Wait for the build to complete and verify it was successful. Login credentials: Username: admin, Password: Admin123!

**Setup:**
- Task creates a test job programmatically via Jenkins CLI
- Job executes simple shell commands with ~2 second duration

**Verification Criteria:**
- Build was triggered (build count increases)
- Build completed (not still running)
- Build result is SUCCESS
- Build metadata captured (number, duration, timestamp)

## API Utilities

The environment provides helper scripts for interacting with Jenkins:

```bash
# Jenkins CLI operations
jenkins-cli list-jobs
jenkins-cli create-job <name> < config.xml
jenkins-cli build <job-name>

# Jenkins REST API queries
jenkins-api 'api/json?pretty=true'
jenkins-api 'job/<job-name>/api/json'
```

## Verification Pattern

All tasks follow a consistent two-part verification:

1. **Export Script** (runs in VM):
   - Queries Jenkins REST API
   - Extracts job configuration via XML
   - Parses JSON responses with `jq`
   - Saves structured data to `/tmp/<task>_result.json`

2. **Verifier** (runs on host):
   - Uses `copy_from_env()` to retrieve JSON
   - Evaluates multiple criteria with subscores
   - Provides detailed feedback
   - Returns pass/fail with 0-100 score

## Directory Structure

```
jenkins_env/
├── env.json                    # Environment specification
├── config/
│   ├── docker-compose.yml      # Jenkins container configuration
│   └── init-jenkins.groovy     # Auto-configuration script
├── scripts/
│   ├── install_jenkins.sh      # pre_start: Install Docker, tools
│   ├── setup_jenkins.sh        # post_start: Start Jenkins, configure Firefox
│   └── task_utils.sh           # Shared utilities for tasks
├── tasks/
│   ├── create_freestyle_job/   # Task 1
│   │   ├── task.json
│   │   ├── setup_task.sh
│   │   ├── export_result.sh
│   │   └── verifier.py
│   ├── create_pipeline_job/    # Task 2
│   └── trigger_build/          # Task 3
└── evidence_docs/
    └── README.md               # Documentation of real data sources
```

## Real Data Sources

### GitHub Repositories
- **jenkins-docs/simple-java-maven-app**: Official Jenkins tutorial repository for Maven builds
  - URL: https://github.com/jenkins-docs/simple-java-maven-app
  - Content: Real Java application with unit tests and Jenkinsfile
  - Maintained by: Jenkins documentation team

### Docker Images
- **jenkins/jenkins:lts-jdk21**: Official Jenkins LTS image with Java 21

### Documentation References
- Jenkins Installation - Docker: https://www.jenkins.io/doc/book/installing/docker/
- Build a Java app with Maven: https://www.jenkins.io/doc/tutorials/build-a-java-app-with-maven/
- Jenkins Configuration as Code: https://www.jenkins.io/projects/jcasc/

## Technical Details

### Docker-in-QEMU Setup
- Base VM runs systemd with Docker daemon
- Jenkins runs as container inside VM
- Volume persistence via Docker volumes
- Port forwarding: 8080 (HTTP), 50000 (agent communication)

### Jenkins Configuration
- Setup wizard bypassed via Groovy init script
- Admin user created automatically
- CSRF protection enabled
- Full job creation permissions

### Browser Integration
- Firefox with custom profile
- No first-run dialogs or promotions
- Homepage set to Jenkins URL
- Password manager disabled
- Sidebar and distractions removed

## Maintenance Notes

### Environment Registration
The environment is registered in `constants.py`:

```python
jenkins_tasks = ['create_freestyle_job', 'create_pipeline_job', 'trigger_build']

ENV_TASK_SPLITS = {
    'jenkins_env': {
        'all': jenkins_tasks,
        'train': jenkins_tasks,
        'test': [],
    },
}
```

### Cache Compatibility
- Supports checkpoint caching at `post_start` level
- First boot takes ~2-3 minutes (Docker image pull, Jenkins startup)
- Cached boots take ~30-60 seconds

## License

This environment uses:
- Jenkins (MIT License)
- Docker (Apache License 2.0)
- All referenced repositories maintain their original licenses

## Credits

Created following the Gym-Anything environment creation workflow documented in `env_creation_notes/prompt.md`.

Uses official Jenkins Docker image and tutorial repositories to ensure realistic CI/CD workflows.
