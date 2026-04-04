# Task: telecom_campus_network_design

## Domain Context

Telecom Network Specialists design campus network infrastructure for enterprises, universities, and government facilities. A complete network design document includes a physical/logical topology diagram plus an IP addressing plan — two distinct page types that together constitute a full design deliverable. This task uses EdrawMax's Network Diagram shape library.

## Occupation

**Telecommunications Specialists** (top EdrawMax user group by economic impact)

## Task Overview

Create a complete campus network topology diagram plus IP addressing plan in EdrawMax across 2 pages, saved as `/home/ga/campus_network_topology.eddx`.

## Goal / End State

The completed file must contain:

- **Page 1**: Physical/logical network topology for a university campus, including: perimeter firewall, core router (ISP uplink), core distribution switch, ≥2 access layer switches, ≥3 server nodes (file/web/DNS-DHCP), ≥4 end-user devices, ≥2 wireless access points, all connected with cable links.
- **Page 2**: IP Addressing Plan as a table or list showing subnet assignments, IP ranges, VLAN IDs, and device roles.
- Professional color theme applied.

## Difficulty

**hard** — Task gives specific component types and counts (agent knows what to build) but no UI navigation steps (agent must discover EdrawMax's network shape library and drawing tools independently).

## Success Criteria

| Criterion | Points | What is checked |
|-----------|--------|-----------------|
| A: Valid EDDX archive | 15 | File at correct path, valid ZIP |
| B: Modified after task start | 10 | File mtime > start timestamp |
| C: Multi-page (≥ 2 pages) | 20 | ≥ 2 page XML files in archive |
| D: Network device keywords | 15 | ≥ 5 network device terms in XML (router, switch, firewall, server, AP, etc.) |
| E: Shape density | 20 | ≥ 15 Shape elements AND ≥ 8 ConnectLine elements |
| F: Security device | 10 | Firewall/DMZ/security keyword present |
| G: IP plan on page 2 | 10 | IP/subnet/VLAN keywords on page 2 or ≥ 8 text elements |

**Pass threshold: 60/100**

## Verification Strategy

`verifier.py::verify_telecom_campus_network_design` — copies EDDX, parses ZIP XML, searches for network device keywords in all text content and shape type names, counts pages/shapes/connectors.

## Anti-Gaming

- `setup_task.sh` deletes the output file and records start timestamp before launch.

## Edge Cases

- Agent may use generic box shapes instead of network icons — verifier checks text labels so labeled shapes still satisfy criterion D.
- Agent may produce a minimal topology with only a few shapes — criterion E (20 pts) penalizes inadequate density.
- Agent may omit the IP Addressing Plan page — criteria C (20 pts) and G (10 pts) fail.
