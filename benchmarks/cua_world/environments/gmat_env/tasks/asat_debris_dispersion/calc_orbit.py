import math
import numpy as np

# Constants
mu = 398600.4415
Re = 6378.1363
J2 = 0.0010826269

# Initial Keplerian elements
a = 6858.0
e = 0.0021
i = math.radians(82.58)
raan = math.radians(236.43)
omega = math.radians(220.73)
nu = math.radians(140.00)

def kep2cart(a, e, i, raan, omega, nu, mu):
    p = a * (1 - e**2)
    r_mag = p / (1 + e * math.cos(nu))
    
    # Position and velocity in orbital plane
    r_pqw = np.array([r_mag * math.cos(nu), r_mag * math.sin(nu), 0])
    v_pqw = np.array([-math.sqrt(mu/p) * math.sin(nu), math.sqrt(mu/p) * (e + math.cos(nu)), 0])
    
    # Rotation matrices
    R3_W = np.array([[math.cos(-raan), -math.sin(-raan), 0],
                     [math.sin(-raan), math.cos(-raan), 0],
                     [0, 0, 1]])
    R1_i = np.array([[1, 0, 0],
                     [0, math.cos(-i), -math.sin(-i)],
                     [0, math.sin(-i), math.cos(-i)]])
    R3_w = np.array([[math.cos(-omega), -math.sin(-omega), 0],
                     [math.sin(-omega), math.cos(-omega), 0],
                     [0, 0, 1]])
    
    T = R3_W @ R1_i @ R3_w
    
    r_ijk = T @ r_pqw
    v_ijk = T @ v_pqw
    
    return r_ijk, v_ijk

def cart2kep(r_ijk, v_ijk, mu):
    h = np.cross(r_ijk, v_ijk)
    n = np.cross(np.array([0, 0, 1]), h)
    
    r_mag = np.linalg.norm(r_ijk)
    v_mag = np.linalg.norm(v_ijk)
    
    E = 0.5 * v_mag**2 - mu / r_mag
    
    a = -mu / (2 * E)
    
    e_vec = (1/mu) * ((v_mag**2 - mu/r_mag) * r_ijk - np.dot(r_ijk, v_ijk) * v_ijk)
    e = np.linalg.norm(e_vec)
    
    i = math.acos(h[2] / np.linalg.norm(h))
    
    return a, e, i

r_ijk, v_ijk = kep2cart(a, e, i, raan, omega, nu, mu)

# Propagate for 90 days = 90 * 86400 seconds
t = 90 * 86400

def raan_drift(a, e, i, t):
    p = a * (1 - e**2)
    n = math.sqrt(mu / a**3)
    raan_dot = -1.5 * n * J2 * (Re / p)**2 * math.cos(i)
    return raan_dot * t

dvs = np.arange(-100, 101, 10) / 1000.0  # km/s

raans = []
for dv in dvs:
    v_dir = v_ijk / np.linalg.norm(v_ijk)
    v_new = v_ijk + dv * v_dir
    
    a_new, e_new, i_new = cart2kep(r_ijk, v_new, mu)
    
    drift = raan_drift(a_new, e_new, i_new, t)
    # the drift is in radians, convert to degrees
    drift_deg = math.degrees(drift)
    raans.append(236.43 + drift_deg)

print("Min RAAN:", min(raans))
print("Max RAAN:", max(raans))
print("Spread:", max(raans) - min(raans))

