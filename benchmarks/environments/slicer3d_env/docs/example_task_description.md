Task 1: Brain Tumor Segmentation
 
(Already designed in detail above) 
 
Dataset: BraTS 2021
Pre-loaded: 4 MRI modalities (FLAIR, T1, T1ce, T2) 
Goal: Segment the tumor, report volume 
Verification: Dice score against expert mask
 
---
Task 2: Lung Nodule Detection & Measurement
 
Dataset: https://www.cancerimagingarchive.net/collection/lidc-idri/
- 1018 chest CT scans
- Each scanned by 4 thoracic radiologists independently
- Annotations: nodule location (x,y,z), diameter, malignancy rating (1-5)
- Format: DICOM + XML annotations
 
Download:
# Via TCIA NBIA Data Retriever 
# https://www.cancerimagingarchive.net/collection/lidc-idri/
# Or via NBIA REST API 
 
# Annotations (separate download): 
# https://www.cancerimagingarchive.net/collection/lidc-idri/
# File: LIDC-XML-only.zip (contains per-patient XML with nodule annotations)
 
Pre-loaded state:
- One chest CT volume loaded (e.g., LIDC-IDRI-0001)
- Default window/level (mediastinal window, NOT lung window)
- Agent must realize it needs to change to lung window (W:1500 L:-600) to see nodules
 
Task prompt:
You are given a chest CT scan of a patient undergoing lung cancer screening.
 
Your goal: 
1. Find all lung nodules that are 3mm or larger in diameter
2. For each nodule found, report:
 - Its approximate location (which lobe: RUL, RML, RLL, LUL, LLL)
 - Its longest diameter in millimeters
3. Place a fiducial marker on each nodule you identify 
 
Note: You may need to adjust the display settings to properly
visualize lung parenchyma. 
 
Why this is fundamentally different from Task 1:
- Search problem, not segmentation - agent must scan entire lung volume
- Tests window/level knowledge (must switch to lung window)
- Tests Markups module (fiducials, rulers) not Segment Editor
- Finding small objects in a large volume vs delineating a known large structure
 
Verification:
import xml.etree.ElementTree as ET 
import numpy as np 
 
# Parse LIDC-IDRI XML annotations for ground truth 
def parse_lidc_annotations(xml_path):
"""Extract nodule locations and sizes from LIDC XML."""
tree = ET.parse(xml_path)
root = tree.getroot()
ns = {'lidc': 'http://www.nih.gov'}# LIDC namespace
 
nodules = []
for reading_session in root.findall('.//readingSession'):
for nodule in reading_session.findall('unblindedReadNodule'):
# Get centroid and diameter from ROIs
rois = nodule.findall('roi')
if rois:
# Compute centroid from all ROI points 
all_x, all_y, all_z = [], [], []
for roi in rois:
z = float(roi.find('imageZposition').text) 
for edge in roi.findall('edgeMap'):
x = float(edge.find('xCoord').text)
y = float(edge.find('yCoord').text)
all_x.append(x); all_y.append(y); all_z.append(z)
 
centroid = (np.mean(all_x), np.mean(all_y), np.mean(all_z))
diameter = max(max(all_x)-min(all_x), max(all_y)-min(all_y))
 
# Only nodules >= 3mm
if diameter >= 3.0:
nodules.append({
'centroid': centroid,
'diameter_mm': diameter,
}) 
return nodules 
 
# Load agent's placed fiducials (exported from 3D Slicer)
def load_agent_fiducials(fcsv_path):
"""Load fiducial points from 3D Slicer .fcsv file."""
points = []
with open(fcsv_path) as f: 
for line in f: 
if line.startswith('#'):
continue
parts = line.strip().split(',')
if len(parts) >= 4:
x, y, z = float(parts[1]), float(parts[2]), float(parts[3])
points.append((x, y, z))
return points
 
# Match agent fiducials to ground truth nodules
def evaluate_detection(agent_points, gt_nodules, tolerance_mm=15.0):
"""Compute precision, recall for nodule detection."""
matched_gt = set() 
true_positives = 0 
 
for ap in agent_points:
best_dist = float('inf')
best_idx = -1
for i, gt in enumerate(gt_nodules):
dist = np.sqrt(sum((a-g)**2 for a,g in zip(ap, gt['centroid'])))
if dist < best_dist:
best_dist = dist
best_idx = i
 
if best_dist <= tolerance_mm and best_idx not in matched_gt:
true_positives += 1
matched_gt.add(best_idx)
 
precision = true_positives / len(agent_points) if agent_points else 0
recall = true_positives / len(gt_nodules) if gt_nodules else 0 
f1 = 2*precision*recall/(precision+recall) if (precision+recall) > 0 else 0
 
return {
'true_positives': true_positives,
'false_positives': len(agent_points) - true_positives, 
'missed': len(gt_nodules) - true_positives,
'precision': precision,
'recall': recall,
'f1': f1,
'pass': recall >= 0.60 and precision >= 0.50
}
 
Pass/fail: 
Recall >= 0.60 (found at least 60% of nodules) 
Precision >= 0.50 (at least half of marked points are real nodules)
 
---
Task 3: Liver Surgical Planning
 
Dataset: https://www.ircad.fr/research/data-sets/liver-segmentation-3d-ircadb-01/
- 20 patients, 75% with hepatic tumors 
- Masks for: liver, tumors, portal vein, hepatic veins 
- Format: DICOM
- Also available as 3D Slicer sample data (easiest)
 
Download:
# From IRCAD website (requires registration):
# https://www.ircad.fr/research/data-sets/liver-segmentation-3d-ircadb-01/ 
 
# Or directly in 3D Slicer:
# File → Download Sample Data → 3D_IRCAD_B_5_Liver 
 
Pre-loaded state:
- Abdominal CT volume loaded
- Portal-venous phase (contrast-enhanced, vessels visible) 
- No segmentations 
 
Task prompt:
You are given an abdominal CT scan of a patient with liver tumors
being evaluated for surgical resection.
 
Your goal: 
1. Segment the liver parenchyma
2. Segment all visible liver tumors
3. Segment the portal vein (the large vessel entering the liver)
4. Determine the minimum distance between the tumor(s) and the 
 portal vein 
5. Report: 
 - Total tumor volume (mL)
 - Number of distinct tumors 
 - Minimum tumor-to-portal-vein distance (mm)
 - Whether any tumor appears to be in direct contact with the
portal vein (yes/no)
 
Why this is different from Task 1: 
- Multiple structures that must be segmented separately
- Spatial relationship analysis (distance between structures)
- Clinical decision component (vascular invasion yes/no)
- Single modality CT vs multi-modal MRI
- Abdominal anatomy vs brain anatomy
 
Verification:
import nibabel as nib
import numpy as np 
from scipy.ndimage import distance_transform_edt
 
def verify_liver_planning(agent_seg_path, gt_masks_dir, voxel_spacing):
"""Verify liver surgical planning task.""" 
 
# Load ground truth masks
gt_liver = load_mask(gt_masks_dir + "/liver/") 
gt_tumor = load_mask(gt_masks_dir + "/livertumor/")
gt_portal = load_mask(gt_masks_dir + "/portalvein/")
 
# Load agent segmentation (multi-label)
agent = nib.load(agent_seg_path).get_fdata().astype(int)
agent_liver = (agent == 1) 
agent_tumor = (agent == 2) 
agent_portal = (agent == 3)
 
# 1. Dice scores
dice_liver = dice_coefficient(agent_liver, gt_liver)
dice_tumor = dice_coefficient(agent_tumor, gt_tumor)
dice_portal = dice_coefficient(agent_portal, gt_portal)
 
# 2. Tumor volume comparison
voxel_vol_ml = np.prod(voxel_spacing) / 1000
gt_tumor_vol = np.sum(gt_tumor) * voxel_vol_ml 
agent_tumor_vol = np.sum(agent_tumor) * voxel_vol_ml
vol_error = abs(agent_tumor_vol - gt_tumor_vol) / gt_tumor_vol * 100
 
# 3. Tumor-to-vessel distance
if np.any(gt_tumor) and np.any(gt_portal): 
# Distance from every tumor voxel to nearest portal vein voxel 
portal_dt = distance_transform_edt(~gt_portal, sampling=voxel_spacing) 
gt_min_distance = portal_dt[gt_tumor].min()
 
agent_portal_dt = distance_transform_edt(~agent_portal, sampling=voxel_spacing)
agent_min_distance = agent_portal_dt[agent_tumor].min() if np.any(agent_tumor) else float('inf')
 
# 4. Vascular invasion (contact = distance < 1mm)
gt_invasion = gt_min_distance < 1.0
agent_invasion = agent_min_distance < 1.0# from agent's report
invasion_correct = (gt_invasion == agent_invasion) 
 
# 5. Tumor count
from scipy.ndimage import label
gt_count = label(gt_tumor)[1]
agent_count = label(agent_tumor)[1]
 
return {
'dice_liver': dice_liver,
'dice_tumor': dice_tumor,
'dice_portal_vein': dice_portal,
'tumor_volume_error_pct': vol_error,
'distance_error_mm': abs(agent_min_distance - gt_min_distance),
'invasion_correct': invasion_correct,
'tumor_count_correct': (agent_count == gt_count),
'pass': (dice_liver > 0.85 and dice_tumor > 0.50
and invasion_correct) 
}
 
Pass/fail: 
Liver Dice > 0.85
Tumor Dice > 0.50 (tumors are harder, smaller) 
Vascular invasion call correct (binary)
Distance error < 5mm
 
---
Task 4: Abdominal Aorta Measurement
 
Dataset: https://amos22.grand-challenge.org/
- 500 CT + 100 MRI scans
- 15 organ labels including aorta (label 10)
- Format: NIfTI
- License: CC BY 4.0
 
Download:
# From Zenodo (no registration):
# https://zenodo.org/records/7155725
 
wget https://zenodo.org/records/7155725/files/amos22.zip
unzip amos22.zip
# Use a case where aorta is clearly visible, e.g., amos_0001.nii.gz
 
Pre-loaded state:
- Abdominal CT volume loaded
- Default window/level settings
- No markups or measurements
 
Task prompt:
You are given an abdominal CT scan. The patient is being evaluated 
for possible abdominal aortic aneurysm (AAA).
 
Your goal: 
1. Locate the abdominal aorta
2. Scroll through the aorta to find its widest cross-sectional point
3. Measure the maximum outer diameter of the aorta at that level
 (in millimeters) using a measurement tool
4. Report: 
 - The maximum diameter (mm) 
 - The vertebral level where the maximum diameter was found
 - Clinical assessment: Normal (<30mm), Ectatic (30-35mm),
or Aneurysmal (>35mm) 
 
Why this is fundamentally different from Tasks 1-3:
- Zero segmentation - purely measurement
- Tests Markups ruler tool, not Segment Editor 
- Tests navigation skill - must scroll through volume to find widest point 
- Tests clinical reasoning - must classify based on measurement
- Quick task (1-2 minutes) vs longer segmentation tasks
 
Verification:
import nibabel as nib
import numpy as np 
from scipy.ndimage import label
 
def compute_gt_aorta_diameter(amos_label_path, aorta_label=10):
"""Compute ground truth max aorta diameter from segmentation mask."""
 
seg = nib.load(amos_label_path)
data = seg.get_fdata().astype(int) 
spacing = seg.header.get_zooms()[:3]# (x_spacing, y_spacing, z_spacing)
 
aorta = (data == aorta_label)
 
max_diameter = 0
max_slice_idx = 0
 
# For each axial slice, compute the aorta diameter 
for z in range(aorta.shape[2]):
slice_mask = aorta[:, :, z]
if not np.any(slice_mask): 
continue
 
# Find bounding box of aorta in this slice 
rows = np.any(slice_mask, axis=1)
cols = np.any(slice_mask, axis=0)
rmin, rmax = np.where(rows)[0][[0, -1]]
cmin, cmax = np.where(cols)[0][[0, -1]]
 
# Diameter in mm (max of height and width of bounding box) 
diameter_y = (rmax - rmin + 1) * spacing[1]
diameter_x = (cmax - cmin + 1) * spacing[0]
diameter = max(diameter_x, diameter_y) 
 
if diameter > max_diameter:
max_diameter = diameter
max_slice_idx = z
 
return {
'max_diameter_mm': max_diameter,
'max_slice_index': max_slice_idx,
'classification': (
'Normal' if max_diameter < 30
else 'Ectatic' if max_diameter < 35
else 'Aneurysmal'
)
}
 
def verify_aorta_measurement(agent_diameter_mm, agent_classification, gt): 
"""Verify agent's aorta measurement."""
 
diameter_error = abs(agent_diameter_mm - gt['max_diameter_mm'])
classification_correct = (agent_classification == gt['classification'])
 
return {
'gt_diameter_mm': gt['max_diameter_mm'],
'agent_diameter_mm': agent_diameter_mm,
'diameter_error_mm': diameter_error,
'classification_correct': classification_correct,
'pass': diameter_error <= 5.0 and classification_correct
}
 
Pass/fail: 
Diameter error <= 5mm
Clinical classification correct (Normal/Ectatic/Aneurysmal)
 
---
Task 5: Segmentation Quality Control (Find & Fix Errors)
 
Dataset: BraTS 2021 (same as Task 1, but modified) 
 
Setup: Creating the "broken" segmentation: 
import nibabel as nib
import numpy as np 
from scipy.ndimage import binary_dilation, binary_erosion, label
 
def create_broken_segmentation(gt_seg_path, output_path, seed=42): 
"""Create a deliberately flawed segmentation for QC task."""
 
rng = np.random.RandomState(seed)
seg = nib.load(gt_seg_path)
data = seg.get_fdata().astype(int) 
broken = data.copy()
 
# ERROR 1: Remove a chunk of the tumor (under-segmentation)
# Find a connected region and delete ~20% of it
tumor_mask = (data > 0)
labeled, n_components = label(tumor_mask)
if n_components > 0:
# Pick the largest component
largest = np.argmax([np.sum(labeled == i) for i in range(1, n_components+1)]) + 1
component_coords = np.argwhere(labeled == largest) 
 
# Remove a spherical region from one end
centroid = component_coords.mean(axis=0)
edge_point = component_coords[ 
np.argmax(np.linalg.norm(component_coords - centroid, axis=1)) 
]
 
# Zero out voxels within 10mm of the edge point
distances = np.linalg.norm(component_coords - edge_point, axis=1)
remove_mask = distances < 12
for coord in component_coords[remove_mask]:
broken[coord[0], coord[1], coord[2]] = 0
 
# ERROR 2: Add a false positive region (over-segmentation) 
# Add a blob 15mm away from the real tumor 
offset = rng.choice([-20, 20], size=3) 
fp_center = (centroid + offset).astype(int)
fp_center = np.clip(fp_center, 15, np.array(data.shape) - 15)
 
# Create a small ellipsoid 
for dx in range(-8, 9):
for dy in range(-8, 9):
for dz in range(-5, 6):
if (dx/8)**2 + (dy/8)**2 + (dz/5)**2 <= 1: 
x, y, z = fp_center[0]+dx, fp_center[1]+dy, fp_center[2]+dz
if 0 <= x < data.shape[0] and 0 <= y < data.shape[1] and 0 <= z < data.shape[2]:
if data[x, y, z] == 0:# Only in non-tumor area
broken[x, y, z] = 1# Mark as tumor
 
# ERROR 3: Jagged boundary (erode then dilate asymmetrically)
# Makes the boundary look rough/incorrect in some areas
remaining_tumor = (broken > 0) 
eroded = binary_erosion(remaining_tumor, iterations=1) 
# Only apply to top half of tumor
mid_z = int(centroid[2])
partial_eroded = remaining_tumor.copy()
partial_eroded[:, :, mid_z:] = eroded[:, :, mid_z:]
broken[~partial_eroded & (broken > 0)] = 0 
 
# Save broken segmentation 
broken_nii = nib.Nifti1Image(broken.astype(np.int16), seg.affine, seg.header)
nib.save(broken_nii, output_path)
 
# Record what errors were introduced (for verification)
errors = { 
'under_segmentation': {
'location': edge_point.tolist(),
'voxels_removed': int(remove_mask.sum())
}, 
'false_positive': {
'center': fp_center.tolist(),
'approximate_radius_voxels': 8 
}, 
'boundary_roughening': {
'affected_region': f'z >= {mid_z}' 
}
}
return errors
 
Pre-loaded state:
- 4 MRI modalities (FLAIR, T1, T1ce, T2) loaded
- A pre-made "AI segmentation" loaded as a segmentation node (the broken one)
- The broken segmentation is visible as an overlay on the MRI
 
Task prompt:
You are given a brain MRI scan with a pre-existing tumor segmentation
that was generated by an AI algorithm. The segmentation may contain
errors.
 
Your goal: 
1. Review the segmentation by examining how well it overlaps with
 the actual tumor visible on MRI 
2. Identify any errors you find:
 - Regions where the tumor is present but NOT segmented
(under-segmentation)
 - Regions marked as tumor that are NOT actually tumor
(over-segmentation / false positives) 
 - Boundary inaccuracies 
3. Correct all errors you find using the Segment Editor
4. Report what errors you found and what corrections you made
 
Why this is fundamentally different from all other tasks:
- Agent is reviewing and correcting, not creating from scratch 
- Tests comparison skill (overlay + visual inspection) 
- Tests error detection (finding what's wrong) 
- Tests precise editing (fixing without breaking what's already correct)
- More realistic - this is increasingly the actual clinical workflow (AI proposes, human corrects) 
 
Verification:
def verify_qc_corrections(agent_corrected_path, gt_seg_path, broken_seg_path): 
"""Verify the agent correctly identified and fixed errors."""
 
gt = nib.load(gt_seg_path).get_fdata().astype(int) 
broken = nib.load(broken_seg_path).get_fdata().astype(int) 
corrected = nib.load(agent_corrected_path).get_fdata().astype(int) 
 
gt_binary = (gt > 0).astype(int)
broken_binary = (broken > 0).astype(int)
corrected_binary = (corrected > 0).astype(int) 
 
# Dice: broken vs ground truth (baseline - how bad was the input?) 
dice_before = dice_coefficient(broken_binary, gt_binary)
 
# Dice: corrected vs ground truth (how much did agent improve it?) 
dice_after = dice_coefficient(corrected_binary, gt_binary) 
 
# Improvement
dice_improvement = dice_after - dice_before
 
# Did agent fix under-segmentation? (added voxels where GT has tumor)
under_seg_region = gt_binary & ~broken_binary# regions that were missing 
fixed_under = corrected_binary & under_seg_region
under_seg_recall = np.sum(fixed_under) / np.sum(under_seg_region) if np.sum(under_seg_region) > 0 else 1.0 
 
# Did agent fix over-segmentation? (removed false positive region) 
over_seg_region = broken_binary & ~gt_binary# regions that were false positive
fixed_over = ~corrected_binary & over_seg_region
over_seg_recall = np.sum(fixed_over) / np.sum(over_seg_region) if np.sum(over_seg_region) > 0 else 1.0 
 
# Did agent break anything that was correct?
correctly_segmented = broken_binary & gt_binary# was correct in broken
still_correct = corrected_binary & correctly_segmented 
preservation = np.sum(still_correct) / np.sum(correctly_segmented) if np.sum(correctly_segmented) > 0 else 1.0 
 
return {
'dice_before': dice_before,
'dice_after': dice_after,
'dice_improvement': dice_improvement,
'under_seg_fixed_pct': under_seg_recall * 100, 
'over_seg_fixed_pct': over_seg_recall * 100,
'preservation_pct': preservation * 100,
'pass': (dice_after > dice_before# Must improve
and dice_after >= 0.80 # Must reach reasonable quality
and preservation >= 0.95# Must not break correct regions
and over_seg_recall >= 0.50)# Must find the false positive 
}
 
Pass/fail: 
Dice improved (after > before) 
Final Dice >= 0.80 
Preserved >= 95% of already-correct regions
Found the false positive region (over-seg recall >= 50%)
 
---
Summary: The Final 5
┌─────┬─────────────────────────┬───────────────────────────────────────┬────────────────┬──────────┬────────────────────────────────┐ 
│#│Task│ Skill Tested│Dataset │ Modality │Verification│ 
├─────┼─────────────────────────┼───────────────────────────────────────┼────────────────┼──────────┼────────────────────────────────┤ 
│ 1│ Brain Tumor │ Create segmentation, multi-modal│ BraTS 2021 │ MRI│ Dice score │ 
│ │ Segmentation│ reasoning ││││ 
├─────┼─────────────────────────┼───────────────────────────────────────┼────────────────┼──────────┼────────────────────────────────┤ 
│ 2│ Lung Nodule Detection│ Visual search, measurement│ LIDC-IDRI│ CT│ Precision/Recall of found│ 
│ │ ││││ nodules│ 
├─────┼─────────────────────────┼───────────────────────────────────────┼────────────────┼──────────┼────────────────────────────────┤ 
│ 3│ Liver Surgical Planning │ Multi-structure seg, spatial analysis │ 3D-IRCADb│ CT│ Dice + distance + invasion │ 
│ │ ││││ call│ 
├─────┼─────────────────────────┼───────────────────────────────────────┼────────────────┼──────────┼────────────────────────────────┤ 
│ 4│ Aortic Aneurysm │ Navigation, measurement, clinical │ AMOS 2022│ CT│ Diameter error +│ 
│ │ Assessment│ decision│││ classification │ 
├─────┼─────────────────────────┼───────────────────────────────────────┼────────────────┼──────────┼────────────────────────────────┤ 
│ 5│ Segmentation QC │ Error detection, correction,│ BraTS│ MRI│ Dice improvement + error│ 
│ │ │ comparison│ (modified) ││ detection│ 
└─────┴─────────────────────────┴───────────────────────────────────────┴────────────────┴──────────┴────────────────────────────────┘ 
Diversity matrix:
┌─────────────────┬─────────┬────────────────┬──────────┬────────────┬───────────┬──────────────┐
│ │ Segment │ Search │ Measure│Compare│Decide│ Multi-struct │
├─────────────────┼─────────┼────────────────┼──────────┼────────────┼───────────┼──────────────┤
│ T1: Brain tumor │ ⭐││ volume││││
├─────────────────┼─────────┼────────────────┼──────────┼────────────┼───────────┼──────────────┤
│ T2: Lung nodule │ │ ⭐ │ diameter ││││
├─────────────────┼─────────┼────────────────┼──────────┼────────────┼───────────┼──────────────┤
│ T3: Liver plan│ ⭐││ distance ││ invasion? │ ⭐│
├─────────────────┼─────────┼────────────────┼──────────┼────────────┼───────────┼──────────────┤
│ T4: Aorta│ │ ⭐ find widest │ diameter ││ aneurysm? ││
├─────────────────┼─────────┼────────────────┼──────────┼────────────┼───────────┼──────────────┤
│ T5: Seg QC│ edit│ ⭐ find errors ││ ⭐ overlay │││
└─────────────────┴─────────┴────────────────┴──────────┴────────────┴───────────┴──────────────┘
Each task tests a distinct primary skill. No two tasks have the same core workflow.