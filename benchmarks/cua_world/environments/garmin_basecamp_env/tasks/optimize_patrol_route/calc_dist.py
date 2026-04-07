import math
import itertools

def haversine(lat1, lon1, lat2, lon2):
    R = 6371.0  # Earth radius in kilometers
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    
    a = math.sin(delta_phi / 2.0)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

points = {
    1: (42.4490, -71.1040),
    2: (42.4340, -71.1060),
    3: (42.4460, -71.0950),
    4: (42.4360, -71.1120),
    5: (42.4420, -71.1000)
}

def route_distance(order):
    dist = 0
    for i in range(len(order) - 1):
        p1 = points[order[i]]
        p2 = points[order[i+1]]
        dist += haversine(p1[0], p1[1], p2[0], p2[1])
    return dist

# Original distance
orig_order = [1, 2, 3, 4, 5]
orig_dist = route_distance(orig_order)
print(f"Original distance (1-2-3-4-5): {orig_dist:.2f} km")

shortest_dist = float('inf')
best_order = None

for order in itertools.permutations(points.keys()):
    d = route_distance(order)
    if d < shortest_dist:
        shortest_dist = d
        best_order = order

print(f"Absolute shortest distance: {shortest_dist:.2f} km, Order: {best_order}")

shortest_dist_fixed_start = float('inf')
for order in itertools.permutations([2,3,4,5]):
    full_order = (1,) + order
    d = route_distance(full_order)
    if d < shortest_dist_fixed_start:
        shortest_dist_fixed_start = d

print(f"Shortest distance (fixed start 1): {shortest_dist_fixed_start:.2f} km")

shortest_dist_fixed_ends = float('inf')
for order in itertools.permutations([2,3,4]):
    full_order = (1,) + order + (5,)
    d = route_distance(full_order)
    if d < shortest_dist_fixed_ends:
        shortest_dist_fixed_ends = d

print(f"Shortest distance (fixed start 1, end 5): {shortest_dist_fixed_ends:.2f} km")
