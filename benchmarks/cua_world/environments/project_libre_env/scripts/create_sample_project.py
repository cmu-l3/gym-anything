#!/usr/bin/env python3
"""
Creates a realistic sample project file in MSPDI XML format.

ProjectLibre imports MSPDI (Microsoft Project XML) files natively when the
file has a .xml extension. This format is the de facto standard for
project management data exchange.

The project data represents a real-world software development lifecycle
schedule commonly used in enterprise IT projects.

Usage:
    python3 create_sample_project.py output.xml
"""

import sys
import os

# MSPDI XML for a realistic enterprise software development project
# Based on real-world software project management structures
MSPDI_XML = '''<?xml version="1.0" encoding="UTF-8"?>
<Project xmlns="http://schemas.microsoft.com/project">
  <Name>Enterprise Software Development Project</Name>
  <Title>Software Development Project</Title>
  <Manager>Project Manager</Manager>
  <StartDate>2025-01-01T08:00:00</StartDate>
  <FinishDate>2025-06-30T17:00:00</FinishDate>
  <Tasks>
    <Task>
      <UID>0</UID>
      <ID>0</ID>
      <Name>Enterprise Software Development Project</Name>
      <Duration>PT1200H0M0S</Duration>
      <Summary>1</Summary>
    </Task>
    <Task>
      <UID>1</UID>
      <ID>1</ID>
      <Name>Requirements Gathering</Name>
      <Duration>PT80H0M0S</Duration>
      <Start>2025-01-01T08:00:00</Start>
      <Finish>2025-01-14T17:00:00</Finish>
      <PercentComplete>100</PercentComplete>
      <Milestone>0</Milestone>
      <Summary>0</Summary>
    </Task>
    <Task>
      <UID>2</UID>
      <ID>2</ID>
      <Name>System Architecture Design</Name>
      <Duration>PT64H0M0S</Duration>
      <Start>2025-01-15T08:00:00</Start>
      <Finish>2025-01-24T17:00:00</Finish>
      <PercentComplete>75</PercentComplete>
      <Milestone>0</Milestone>
      <Summary>0</Summary>
      <PredecessorLink>
        <PredecessorUID>1</PredecessorUID>
        <Type>1</Type>
      </PredecessorLink>
    </Task>
    <Task>
      <UID>3</UID>
      <ID>3</ID>
      <Name>Database Schema Design</Name>
      <Duration>PT40H0M0S</Duration>
      <Start>2025-01-15T08:00:00</Start>
      <Finish>2025-01-21T17:00:00</Finish>
      <PercentComplete>100</PercentComplete>
      <Milestone>0</Milestone>
      <Summary>0</Summary>
      <PredecessorLink>
        <PredecessorUID>1</PredecessorUID>
        <Type>1</Type>
      </PredecessorLink>
    </Task>
    <Task>
      <UID>4</UID>
      <ID>4</ID>
      <Name>UI/UX Wireframes</Name>
      <Duration>PT48H0M0S</Duration>
      <Start>2025-01-15T08:00:00</Start>
      <Finish>2025-01-22T17:00:00</Finish>
      <PercentComplete>80</PercentComplete>
      <Milestone>0</Milestone>
      <Summary>0</Summary>
      <PredecessorLink>
        <PredecessorUID>1</PredecessorUID>
        <Type>1</Type>
      </PredecessorLink>
    </Task>
    <Task>
      <UID>5</UID>
      <ID>5</ID>
      <Name>Design Review Milestone</Name>
      <Duration>PT0H0M0S</Duration>
      <Start>2025-01-25T08:00:00</Start>
      <Finish>2025-01-25T08:00:00</Finish>
      <PercentComplete>0</PercentComplete>
      <Milestone>1</Milestone>
      <Summary>0</Summary>
    </Task>
    <Task>
      <UID>6</UID>
      <ID>6</ID>
      <Name>Backend API Development</Name>
      <Duration>PT120H0M0S</Duration>
      <Start>2025-01-27T08:00:00</Start>
      <Finish>2025-02-14T17:00:00</Finish>
      <PercentComplete>40</PercentComplete>
      <Milestone>0</Milestone>
      <Summary>0</Summary>
      <PredecessorLink>
        <PredecessorUID>5</PredecessorUID>
        <Type>1</Type>
      </PredecessorLink>
    </Task>
    <Task>
      <UID>7</UID>
      <ID>7</ID>
      <Name>Frontend Development</Name>
      <Duration>PT120H0M0S</Duration>
      <Start>2025-01-27T08:00:00</Start>
      <Finish>2025-02-14T17:00:00</Finish>
      <PercentComplete>30</PercentComplete>
      <Milestone>0</Milestone>
      <Summary>0</Summary>
      <PredecessorLink>
        <PredecessorUID>5</PredecessorUID>
        <Type>1</Type>
      </PredecessorLink>
    </Task>
    <Task>
      <UID>8</UID>
      <ID>8</ID>
      <Name>Database Implementation</Name>
      <Duration>PT64H0M0S</Duration>
      <Start>2025-01-27T08:00:00</Start>
      <Finish>2025-02-05T17:00:00</Finish>
      <PercentComplete>50</PercentComplete>
      <Milestone>0</Milestone>
      <Summary>0</Summary>
      <PredecessorLink>
        <PredecessorUID>5</PredecessorUID>
        <Type>1</Type>
      </PredecessorLink>
    </Task>
    <Task>
      <UID>9</UID>
      <ID>9</ID>
      <Name>Integration Testing</Name>
      <Duration>PT80H0M0S</Duration>
      <Start>2025-02-17T08:00:00</Start>
      <Finish>2025-02-28T17:00:00</Finish>
      <PercentComplete>0</PercentComplete>
      <Milestone>0</Milestone>
      <Summary>0</Summary>
      <PredecessorLink>
        <PredecessorUID>6</PredecessorUID>
        <Type>1</Type>
      </PredecessorLink>
      <PredecessorLink>
        <PredecessorUID>7</PredecessorUID>
        <Type>1</Type>
      </PredecessorLink>
      <PredecessorLink>
        <PredecessorUID>8</PredecessorUID>
        <Type>1</Type>
      </PredecessorLink>
    </Task>
    <Task>
      <UID>10</UID>
      <ID>10</ID>
      <Name>Performance Testing</Name>
      <Duration>PT40H0M0S</Duration>
      <Start>2025-03-03T08:00:00</Start>
      <Finish>2025-03-07T17:00:00</Finish>
      <PercentComplete>0</PercentComplete>
      <Milestone>0</Milestone>
      <Summary>0</Summary>
      <PredecessorLink>
        <PredecessorUID>9</PredecessorUID>
        <Type>1</Type>
      </PredecessorLink>
    </Task>
    <Task>
      <UID>11</UID>
      <ID>11</ID>
      <Name>Security Audit</Name>
      <Duration>PT40H0M0S</Duration>
      <Start>2025-03-03T08:00:00</Start>
      <Finish>2025-03-07T17:00:00</Finish>
      <PercentComplete>0</PercentComplete>
      <Milestone>0</Milestone>
      <Summary>0</Summary>
      <PredecessorLink>
        <PredecessorUID>9</PredecessorUID>
        <Type>1</Type>
      </PredecessorLink>
    </Task>
    <Task>
      <UID>12</UID>
      <ID>12</ID>
      <Name>User Acceptance Testing</Name>
      <Duration>PT64H0M0S</Duration>
      <Start>2025-03-10T08:00:00</Start>
      <Finish>2025-03-19T17:00:00</Finish>
      <PercentComplete>0</PercentComplete>
      <Milestone>0</Milestone>
      <Summary>0</Summary>
      <PredecessorLink>
        <PredecessorUID>10</PredecessorUID>
        <Type>1</Type>
      </PredecessorLink>
      <PredecessorLink>
        <PredecessorUID>11</PredecessorUID>
        <Type>1</Type>
      </PredecessorLink>
    </Task>
    <Task>
      <UID>13</UID>
      <ID>13</ID>
      <Name>Documentation</Name>
      <Duration>PT80H0M0S</Duration>
      <Start>2025-03-10T08:00:00</Start>
      <Finish>2025-03-21T17:00:00</Finish>
      <PercentComplete>0</PercentComplete>
      <Milestone>0</Milestone>
      <Summary>0</Summary>
      <PredecessorLink>
        <PredecessorUID>9</PredecessorUID>
        <Type>1</Type>
      </PredecessorLink>
    </Task>
    <Task>
      <UID>14</UID>
      <ID>14</ID>
      <Name>Deployment to Staging</Name>
      <Duration>PT24H0M0S</Duration>
      <Start>2025-03-24T08:00:00</Start>
      <Finish>2025-03-26T17:00:00</Finish>
      <PercentComplete>0</PercentComplete>
      <Milestone>0</Milestone>
      <Summary>0</Summary>
      <PredecessorLink>
        <PredecessorUID>12</PredecessorUID>
        <Type>1</Type>
      </PredecessorLink>
      <PredecessorLink>
        <PredecessorUID>13</PredecessorUID>
        <Type>1</Type>
      </PredecessorLink>
    </Task>
    <Task>
      <UID>15</UID>
      <ID>15</ID>
      <Name>Production Deployment</Name>
      <Duration>PT16H0M0S</Duration>
      <Start>2025-03-27T08:00:00</Start>
      <Finish>2025-03-28T17:00:00</Finish>
      <PercentComplete>0</PercentComplete>
      <Milestone>0</Milestone>
      <Summary>0</Summary>
      <PredecessorLink>
        <PredecessorUID>14</PredecessorUID>
        <Type>1</Type>
      </PredecessorLink>
    </Task>
    <Task>
      <UID>16</UID>
      <ID>16</ID>
      <Name>Project Completion Milestone</Name>
      <Duration>PT0H0M0S</Duration>
      <Start>2025-03-31T08:00:00</Start>
      <Finish>2025-03-31T08:00:00</Finish>
      <PercentComplete>0</PercentComplete>
      <Milestone>1</Milestone>
      <Summary>0</Summary>
      <PredecessorLink>
        <PredecessorUID>15</PredecessorUID>
        <Type>1</Type>
      </PredecessorLink>
    </Task>
  </Tasks>
  <Resources>
    <Resource>
      <UID>1</UID>
      <ID>1</ID>
      <Name>Alice Johnson</Name>
      <Type>0</Type>
      <StandardRate>85</StandardRate>
      <OvertimeRate>127.5</OvertimeRate>
      <Notes>Senior Software Engineer</Notes>
    </Resource>
    <Resource>
      <UID>2</UID>
      <ID>2</ID>
      <Name>Bob Smith</Name>
      <Type>0</Type>
      <StandardRate>80</StandardRate>
      <OvertimeRate>120</OvertimeRate>
      <Notes>Backend Developer</Notes>
    </Resource>
    <Resource>
      <UID>3</UID>
      <ID>3</ID>
      <Name>Carol Williams</Name>
      <Type>0</Type>
      <StandardRate>75</StandardRate>
      <OvertimeRate>112.5</OvertimeRate>
      <Notes>Frontend Developer</Notes>
    </Resource>
    <Resource>
      <UID>4</UID>
      <ID>4</ID>
      <Name>David Brown</Name>
      <Type>0</Type>
      <StandardRate>90</StandardRate>
      <OvertimeRate>135</OvertimeRate>
      <Notes>Database Administrator</Notes>
    </Resource>
    <Resource>
      <UID>5</UID>
      <ID>5</ID>
      <Name>Emma Davis</Name>
      <Type>0</Type>
      <StandardRate>70</StandardRate>
      <OvertimeRate>105</OvertimeRate>
      <Notes>QA Engineer</Notes>
    </Resource>
    <Resource>
      <UID>6</UID>
      <ID>6</ID>
      <Name>Frank Miller</Name>
      <Type>0</Type>
      <StandardRate>95</StandardRate>
      <OvertimeRate>142.5</OvertimeRate>
      <Notes>Project Manager</Notes>
    </Resource>
    <Resource>
      <UID>7</UID>
      <ID>7</ID>
      <Name>Grace Wilson</Name>
      <Type>0</Type>
      <StandardRate>78</StandardRate>
      <OvertimeRate>117</OvertimeRate>
      <Notes>UI/UX Designer</Notes>
    </Resource>
  </Resources>
  <Assignments>
    <Assignment>
      <UID>1</UID>
      <TaskUID>1</TaskUID>
      <ResourceUID>6</ResourceUID>
      <Units>1</Units>
      <Work>PT80H0M0S</Work>
    </Assignment>
    <Assignment>
      <UID>2</UID>
      <TaskUID>2</TaskUID>
      <ResourceUID>1</ResourceUID>
      <Units>1</Units>
      <Work>PT64H0M0S</Work>
    </Assignment>
    <Assignment>
      <UID>3</UID>
      <TaskUID>3</TaskUID>
      <ResourceUID>4</ResourceUID>
      <Units>1</Units>
      <Work>PT40H0M0S</Work>
    </Assignment>
    <Assignment>
      <UID>4</UID>
      <TaskUID>4</TaskUID>
      <ResourceUID>7</ResourceUID>
      <Units>1</Units>
      <Work>PT48H0M0S</Work>
    </Assignment>
    <Assignment>
      <UID>5</UID>
      <TaskUID>6</TaskUID>
      <ResourceUID>2</ResourceUID>
      <Units>1</Units>
      <Work>PT120H0M0S</Work>
    </Assignment>
    <Assignment>
      <UID>6</UID>
      <TaskUID>7</TaskUID>
      <ResourceUID>3</ResourceUID>
      <Units>1</Units>
      <Work>PT120H0M0S</Work>
    </Assignment>
    <Assignment>
      <UID>7</UID>
      <TaskUID>8</TaskUID>
      <ResourceUID>4</ResourceUID>
      <Units>1</Units>
      <Work>PT64H0M0S</Work>
    </Assignment>
    <Assignment>
      <UID>8</UID>
      <TaskUID>9</TaskUID>
      <ResourceUID>5</ResourceUID>
      <Units>1</Units>
      <Work>PT80H0M0S</Work>
    </Assignment>
    <Assignment>
      <UID>9</UID>
      <TaskUID>10</TaskUID>
      <ResourceUID>5</ResourceUID>
      <Units>1</Units>
      <Work>PT40H0M0S</Work>
    </Assignment>
    <Assignment>
      <UID>10</UID>
      <TaskUID>12</TaskUID>
      <ResourceUID>5</ResourceUID>
      <Units>1</Units>
      <Work>PT64H0M0S</Work>
    </Assignment>
  </Assignments>
</Project>
'''


def create_project_file(output_path):
    """Create an MSPDI XML project file."""
    os.makedirs(os.path.dirname(output_path) if os.path.dirname(output_path) else '.', exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(MSPDI_XML)
    print(f"Created MSPDI XML project file: {output_path}")
    print(f"File size: {os.path.getsize(output_path)} bytes")
    return True


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 create_sample_project.py output.xml")
        sys.exit(1)

    output_path = sys.argv[1]
    create_project_file(output_path)
