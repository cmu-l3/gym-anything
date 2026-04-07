#!/bin/bash
set -e
echo "=== Setting up level_resources task ==="

# 1. Kill any existing ProjectLibre instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# 2. Generate the Over-Allocated Project File
# We use Python to generate a valid MSPDI (Microsoft Project XML) file
# that ProjectLibre can open. We structure it with parallel tasks
# assigned to the same resource to force over-allocation.

PROJECT_FILE="/home/ga/Projects/construction_retrofit.xml"
mkdir -p /home/ga/Projects

python3 -c '
import sys

# MSPDI XML Template with deliberate conflicts
xml_content = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Project xmlns="http://schemas.microsoft.com/project">
    <Name>Construction Retrofit Project</Name>
    <Title>Retrofit Schedule</Title>
    <CreationDate>2025-02-01T08:00:00</CreationDate>
    <LastSaved>2025-02-01T08:00:00</LastSaved>
    <ScheduleFromStart>1</ScheduleFromStart>
    <StartDate>2025-02-03T08:00:00</StartDate>
    <FinishDate>2025-04-18T17:00:00</FinishDate>
    <CalendarUID>1</CalendarUID>
    <Calendars>
        <Calendar>
            <UID>1</UID>
            <Name>Standard</Name>
            <IsBaseCalendar>1</IsBaseCalendar>
            <WeekDays>
                <WeekDay><DayType>1</DayType><DayWorking>0</DayWorking></WeekDay>
                <WeekDay><DayType>2</DayType><DayWorking>1</DayWorking>
                    <WorkingTimes><WorkingTime><FromTime>08:00:00</FromTime><ToTime>12:00:00</ToTime></WorkingTime>
                    <WorkingTime><FromTime>13:00:00</FromTime><ToTime>17:00:00</ToTime></WorkingTime></WorkingTimes>
                </WeekDay>
                <WeekDay><DayType>3</DayType><DayWorking>1</DayWorking>
                    <WorkingTimes><WorkingTime><FromTime>08:00:00</FromTime><ToTime>12:00:00</ToTime></WorkingTime>
                    <WorkingTime><FromTime>13:00:00</FromTime><ToTime>17:00:00</ToTime></WorkingTime></WorkingTimes>
                </WeekDay>
                <WeekDay><DayType>4</DayType><DayWorking>1</DayWorking>
                    <WorkingTimes><WorkingTime><FromTime>08:00:00</FromTime><ToTime>12:00:00</ToTime></WorkingTime>
                    <WorkingTime><FromTime>13:00:00</FromTime><ToTime>17:00:00</ToTime></WorkingTime></WorkingTimes>
                </WeekDay>
                <WeekDay><DayType>5</DayType><DayWorking>1</DayWorking>
                    <WorkingTimes><WorkingTime><FromTime>08:00:00</FromTime><ToTime>12:00:00</ToTime></WorkingTime>
                    <WorkingTime><FromTime>13:00:00</FromTime><ToTime>17:00:00</ToTime></WorkingTime></WorkingTimes>
                </WeekDay>
                <WeekDay><DayType>6</DayType><DayWorking>1</DayWorking>
                    <WorkingTimes><WorkingTime><FromTime>08:00:00</FromTime><ToTime>12:00:00</ToTime></WorkingTime>
                    <WorkingTime><FromTime>13:00:00</FromTime><ToTime>17:00:00</ToTime></WorkingTime></WorkingTimes>
                </WeekDay>
                <WeekDay><DayType>7</DayType><DayWorking>0</DayWorking></WeekDay>
            </WeekDays>
        </Calendar>
    </Calendars>
    <Resources>
        <Resource><UID>1</UID><ID>1</ID><Name>Alice Johnson</Name><Type>1</Type><MaxUnits>1.0</MaxUnits></Resource>
        <Resource><UID>2</UID><ID>2</ID><Name>Bob Smith</Name><Type>1</Type><MaxUnits>1.0</MaxUnits></Resource>
        <Resource><UID>3</UID><ID>3</ID><Name>Carol Williams</Name><Type>1</Type><MaxUnits>1.0</MaxUnits></Resource>
        <Resource><UID>4</UID><ID>4</ID><Name>David Brown</Name><Type>1</Type><MaxUnits>1.0</MaxUnits></Resource>
        <Resource><UID>5</UID><ID>5</ID><Name>Emma Davis</Name><Type>1</Type><MaxUnits>1.0</MaxUnits></Resource>
    </Resources>
    <Tasks>
        <Task><UID>0</UID><ID>0</ID><Name>Project Root</Name><OutlineNumber>0</OutlineNumber><OutlineLevel>0</OutlineLevel></Task>
        
        <!-- Phase 1: Planning -->
        <Task><UID>1</UID><ID>1</ID><Name>Project Kickoff</Name><Duration>PT0H0M0S</Duration><Start>2025-02-03T08:00:00</Start><Finish>2025-02-03T08:00:00</Finish><OutlineLevel>1</OutlineLevel></Task>
        
        <Task><UID>2</UID><ID>2</ID><Name>Site Survey</Name><Duration>PT80H0M0S</Duration><Start>2025-02-03T08:00:00</Start><Finish>2025-02-14T17:00:00</Finish><OutlineLevel>1</OutlineLevel></Task>
        
        <!-- CONFLICT 1: Alice assigned to both Task 3 and 4 concurrently -->
        <Task>
            <UID>3</UID><ID>3</ID><Name>Structural Engineering</Name>
            <Duration>PT80H0M0S</Duration> <!-- 10 days -->
            <Start>2025-02-03T08:00:00</Start><Finish>2025-02-14T17:00:00</Finish>
            <ConstraintType>0</ConstraintType> <!-- As Soon As Possible -->
            <OutlineLevel>1</OutlineLevel>
        </Task>
        
        <Task>
            <UID>4</UID><ID>4</ID><Name>Electrical Systems Design</Name>
            <Duration>PT80H0M0S</Duration> <!-- 10 days -->
            <Start>2025-02-03T08:00:00</Start><Finish>2025-02-14T17:00:00</Finish>
            <ConstraintType>0</ConstraintType>
            <OutlineLevel>1</OutlineLevel>
        </Task>
        
        <Task><UID>5</UID><ID>5</ID><Name>Design Review</Name><Duration>PT0H0M0S</Duration><Start>2025-02-17T08:00:00</Start><Finish>2025-02-17T08:00:00</Finish><Milestone>1</Milestone><OutlineLevel>1</OutlineLevel>
            <PredecessorLink><PredecessorUID>3</PredecessorUID></PredecessorLink>
            <PredecessorLink><PredecessorUID>4</PredecessorUID></PredecessorLink>
        </Task>
        
        <!-- Phase 2: Implementation -->
        <Task><UID>6</UID><ID>6</ID><Name>Procurement</Name><Duration>PT160H0M0S</Duration><Start>2025-02-18T08:00:00</Start><Finish>2025-03-17T17:00:00</Finish><OutlineLevel>1</OutlineLevel>
            <PredecessorLink><PredecessorUID>5</PredecessorUID></PredecessorLink>
        </Task>
        
        <Task><UID>7</UID><ID>7</ID><Name>Installation</Name><Duration>PT160H0M0S</Duration><Start>2025-03-18T08:00:00</Start><Finish>2025-04-14T17:00:00</Finish><OutlineLevel>1</OutlineLevel>
            <PredecessorLink><PredecessorUID>6</PredecessorUID></PredecessorLink>
        </Task>
        
        <!-- CONFLICT 2: Emma assigned to both Task 8 and 9 concurrently -->
        <Task>
            <UID>8</UID><ID>8</ID><Name>Systems Integration Testing</Name>
            <Duration>PT80H0M0S</Duration>
            <Start>2025-04-15T08:00:00</Start><Finish>2025-04-28T17:00:00</Finish>
            <OutlineLevel>1</OutlineLevel>
            <PredecessorLink><PredecessorUID>7</PredecessorUID></PredecessorLink>
        </Task>
        
        <Task>
            <UID>9</UID><ID>9</ID><Name>Safety Compliance Audit</Name>
            <Duration>PT80H0M0S</Duration>
            <Start>2025-04-15T08:00:00</Start><Finish>2025-04-28T17:00:00</Finish>
            <OutlineLevel>1</OutlineLevel>
            <PredecessorLink><PredecessorUID>7</PredecessorUID></PredecessorLink>
        </Task>

        <Task><UID>10</UID><ID>10</ID><Name>Project Handover</Name><Duration>PT0H0M0S</Duration><Start>2025-04-29T08:00:00</Start><Finish>2025-04-29T08:00:00</Finish><Milestone>1</Milestone><OutlineLevel>1</OutlineLevel>
            <PredecessorLink><PredecessorUID>8</PredecessorUID></PredecessorLink>
            <PredecessorLink><PredecessorUID>9</PredecessorUID></PredecessorLink>
        </Task>
        
    </Tasks>
    <Assignments>
        <!-- Alice on Task 3 and 4 (Conflict) -->
        <Assignment><UID>1</UID><TaskUID>3</TaskUID><ResourceUID>1</ResourceUID><Units>1.0</Units></Assignment>
        <Assignment><UID>2</UID><TaskUID>4</TaskUID><ResourceUID>1</ResourceUID><Units>1.0</Units></Assignment>
        
        <!-- Bob on Task 2 -->
        <Assignment><UID>3</UID><TaskUID>2</TaskUID><ResourceUID>2</ResourceUID><Units>1.0</Units></Assignment>
        
        <!-- Carol on Task 6 -->
        <Assignment><UID>4</UID><TaskUID>6</TaskUID><ResourceUID>3</ResourceUID><Units>1.0</Units></Assignment>
        
        <!-- David on Task 7 -->
        <Assignment><UID>5</UID><TaskUID>7</TaskUID><ResourceUID>4</ResourceUID><Units>1.0</Units></Assignment>
        
        <!-- Emma on Task 8 and 9 (Conflict) -->
        <Assignment><UID>6</UID><TaskUID>8</TaskUID><ResourceUID>5</ResourceUID><Units>1.0</Units></Assignment>
        <Assignment><UID>7</UID><TaskUID>9</TaskUID><ResourceUID>5</ResourceUID><Units>1.0</Units></Assignment>
    </Assignments>
</Project>
"""
with open("construction_retrofit.xml", "w") as f:
    f.write(xml_content)
'
mv construction_retrofit.xml "$PROJECT_FILE"
chown ga:ga "$PROJECT_FILE"

# 3. Clean up any previous results
rm -f /home/ga/Projects/leveled_project.xml
rm -f /tmp/task_result.json

# 4. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Launch ProjectLibre with the project
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$PROJECT_FILE' > /tmp/projectlibre_launch.log 2>&1 &"

# 6. Wait for window and maximize
echo "Waiting for ProjectLibre window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "projectlibre"; then
        echo "Window found."
        break
    fi
    sleep 1
done

sleep 5 # Allow project to fully load

# Maximize
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="