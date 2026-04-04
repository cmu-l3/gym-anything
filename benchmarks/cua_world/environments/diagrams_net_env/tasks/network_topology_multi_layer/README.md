# Task: network_topology_multi_layer

**ID**: network_topology_multi_layer@1
**Difficulty**: very_hard
**Occupation**: Telecommunications Engineering Specialists ($818M GDP impact)
**Timeout**: 900 seconds | **Max Steps**: 100

## Domain Context

Telecommunications engineers designing enterprise network infrastructure routinely create hierarchical network topology diagrams that document multi-layer switching architectures. These follow the Cisco three-tier model (core / distribution / access) and require knowledge of layer-specific conventions, IP addressing schemes, device models, and redundancy patterns. Creating a professionally correct diagram requires understanding network design principles, not just UI manipulation.

## Task Goal

Complete a partially-drawn enterprise campus network topology diagram. The file `~/Diagrams/enterprise_network.drawio` already contains the WAN layer. Using the device specifications in `~/Desktop/network_requirements.txt`, the agent must add three new layers (core, distribution, access), apply standard layer color-coding conventions, label all inter-layer links with bandwidth and protocol, create a second diagram page for the OOB management network, and export the result as PDF.

## What Makes This Hard

1. **Discover shape libraries**: Agent must find and use draw.io's built-in Cisco/network shape library (not default shapes) — not told how
2. **Industry knowledge required**: Must know the hierarchical network design convention (gold/blue/green/orange per layer)
3. **Multi-page creation**: Must create a second diagram page without instructions on how
4. **Judgment calls**: Must interpret requirements doc and populate 14+ new devices with correct connections
5. **Multi-feature usage**: Shape library import, layer styling, edge labeling, multi-page, PDF export

## Success Criteria

| Criterion | Points |
|-----------|--------|
| File modified after task start | 10 |
| Second page (OOB management) created | 15 |
| ≥20 total shapes (core+dist+access layers) | 15 |
| ≥16 edges (well-connected topology) | 10 |
| Core layer devices in diagram | 15 |
| Distribution layer devices | 10 |
| Access layer devices | 10 |
| Bandwidth/protocol labels on links | 10 |
| Layer color-coding (≥3 distinct colors) | 5 |
| PDF exported to ~/Diagrams/enterprise_network.pdf | 10 |

**Pass threshold**: 60 points

## Starting State

- `~/Diagrams/enterprise_network.drawio`: WAN layer only (ISP-A, ISP-B, Border-RTR-01, Border-RTR-02 + links)
- `~/Desktop/network_requirements.txt`: Device specs, IP addressing, color conventions, OOB requirements

## Verification

The verifier parses the final `.drawio` XML (handling both compressed and uncompressed format) and checks shape counts, layer-specific text labels, edge label content, page count, and PDF existence. Independent re-analysis directly copies the file from the VM for tamper-resistance.

## Ground Truth

- Starting shapes: 5 (4 devices + 1 annotation)
- Expected final shapes: ≥20 (adding 2 core + 4 distribution + 8 access + OOB devices)
- Expected pages: 2
- Expected edge labels: containing "Gbps" or "OSPF" or bandwidth notation
