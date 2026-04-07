import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment
from datetime import datetime, timedelta
import random

wb = openpyxl.Workbook()
ws = wb.active
ws.title = 'Encounters'

headers = ['Encounter_ID', 'Arrival_Time', 'Triage_Time', 'Provider_Seen_Time', 'Discharge_Time', 'ESI_Level']
ws.append(headers)

start_date = datetime(2024, 8, 1, 0, 0, 0)
random.seed(42)  # For reproducibility

# Generate 450 realistically distributed encounters
for i in range(1, 451):
    # Clustered arrivals
    arr_time = start_date + timedelta(minutes=random.randint(0, 30*24*60))
    
    # Triage is usually fast (2 to 25 mins)
    tri_time = arr_time + timedelta(minutes=random.randint(2, 25))
    
    # ESI Distribution (1 is rare/critical, 3 is most common)
    esi = random.choices([1, 2, 3, 4, 5], weights=[2, 15, 50, 25, 8])[0]
    
    # Wait times scale inversely with acuity (with some random variance to force breaches)
    if esi == 1:
        wait_mins = random.randint(0, 15)
    elif esi == 2:
        wait_mins = random.randint(10, 85)
    elif esi == 3:
        wait_mins = random.randint(30, 180)
    elif esi == 4:
        wait_mins = random.randint(45, 240)
    else:
        wait_mins = random.randint(60, 300)
        
    prov_time = arr_time + timedelta(minutes=wait_mins)
    
    # Length of Stay (LOS) scales proportionally with acuity severity
    if esi <= 2:
        los_mins = random.randint(180, 720) # 3-12 hrs
    elif esi == 3:
        los_mins = random.randint(120, 480) # 2-8 hrs
    else:
        los_mins = random.randint(60, 240)  # 1-4 hrs
        
    dis_time = arr_time + timedelta(minutes=los_mins)
    
    ws.append([
        f"ENC{10000+i}",
        arr_time.strftime("%Y-%m-%d %H:%M:%S"),
        tri_time.strftime("%Y-%m-%d %H:%M:%S"),
        prov_time.strftime("%Y-%m-%d %H:%M:%S"),
        dis_time.strftime("%Y-%m-%d %H:%M:%S"),
        esi
    ])

print("Generated.")
