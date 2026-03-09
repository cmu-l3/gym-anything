# Parse Unfamiliar Config Task

**Difficulty**: 🟡 Medium  
**Skills**: YAML navigation, configuration management, careful editing  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Locate and modify rate limiting settings in an unfamiliar YAML configuration file for the payment-service API gateway. The configuration file contains settings for multiple services with nested structures and cryptic abbreviations.

## Scenario

You just joined a team working on a Kubernetes-based microservices project. The senior engineer asks you to update the rate limiting configuration for the API gateway to handle increased traffic during flash sales. The team uses a custom YAML-based configuration format you've never seen before.

## Expected Changes

In the `gateway_config.yaml` file, locate the `payment-service` section and update the rate limiting configuration:

1. Update `bkt_sz` (burst bucket size) from `50` to `200`
2. Update `thr_win` (throttle window) from `60` to `30` 
3. Add new field `priority_bypass: true` to allow premium users to bypass limits

**Critical**: Do NOT modify any other service configurations or the commented-out sections.

## File Structure
