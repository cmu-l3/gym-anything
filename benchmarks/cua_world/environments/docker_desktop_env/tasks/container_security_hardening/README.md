# container_security_hardening

## Overview
**Difficulty**: Very Hard
**Domain**: Information Security / DevOps
**Occupation**: Information Security Engineers ($1.9B GDP sector)

A containerized web application has four CIS Docker Benchmark violations. The agent must audit the deployment, discover all issues, and produce a hardened version that passes security checks while keeping the application functional.

## Professional Context
Information security engineers perform container security audits as standard DevOps security practice. CIS Docker Benchmark is the industry reference for container security. This task tests whether the agent can identify common security anti-patterns and apply correct mitigations.

## Starting State
- `/home/ga/insecure-app/` — Web application with insecure Dockerfile + docker-compose.yml
- Container `insecure-web` running with 4 security violations
- Agent must inspect running container and config files to discover issues

## Goal
Fix all security issues and redeploy as `secure-web:hardened`. The hardened container must:
1. Run as a non-root user
2. Not mount the Docker socket
3. Have memory and CPU resource limits
4. Not run in privileged mode

The application must remain accessible on port 8090.

## The Four Security Issues (for verifier — NOT shown to agent)
1. **Root user**: Container runs as root (no USER directive in Dockerfile)
2. **Docker socket mount**: `/var/run/docker.sock` mounted into container
3. **Privileged mode**: `privileged: true` in docker-compose.yml
4. **No resource limits**: No memory or CPU limits configured

## Verification Criteria (100 points)
- **Non-root user** (25 pts): Running container's effective UID is not 0
- **No Docker socket mount** (25 pts): `/var/run/docker.sock` not mounted in hardened container
- **No privileged mode** (20 pts): Container not running in privileged mode
- **Resource limits set** (20 pts): Memory limit configured on the hardened container
- **App still functional** (10 pts): HTTP GET on port 8090 returns 200

**Pass threshold**: 70 points
**Mandatory for pass**: non-root + no socket mount + score >= 70
