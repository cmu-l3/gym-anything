import requests
import time

points = {
    1: (42.4490, -71.1040),
    2: (42.4340, -71.1060),
    3: (42.4460, -71.0950),
    4: (42.4360, -71.1120),
    5: (42.4420, -71.1000)
}

order = [1, 2, 3, 4, 5]
coords = ";".join([f"{points[i][1]},{points[i][0]}" for i in order])

url = f"http://router.project-osrm.org/route/v1/driving/{coords}?overview=false"
r = requests.get(url)
data = r.json()

if data.get('code') == 'Ok':
    dist_meters = data['routes'][0]['distance']
    print(f"OSRM Driving distance: {dist_meters / 1000:.2f} km")
else:
    print(data)

url = f"http://router.project-osrm.org/route/v1/foot/{coords}?overview=false"
r = requests.get(url)
data = r.json()

if data.get('code') == 'Ok':
    dist_meters = data['routes'][0]['distance']
    print(f"OSRM Foot distance: {dist_meters / 1000:.2f} km")
else:
    print(data)

