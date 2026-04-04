#!/bin/bash
echo "=== Exporting reproject_rivers_utm33n result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF' > /tmp/reproject_rivers_utm33n_result.json
import json, sys, os
try:
    from osgeo import ogr, osr

    shp = '/home/ga/gvsig_exports/rivers_utm33n.shp'
    src = '/home/ga/gvsig_data/rivers/ne_110m_rivers_lake_centerlines.shp'

    result = {
        'file_exists': os.path.isfile(shp),
        'feature_count': None,
        'source_feature_count': None,
        'epsg_code': None,
        'crs_wkt': None,
        'geom_type': None,
        'error': None,
    }

    # Count source features
    ds_src = ogr.Open(src)
    if ds_src:
        lyr_src = ds_src.GetLayer()
        result['source_feature_count'] = lyr_src.GetFeatureCount()
        ds_src = None

    if not result['file_exists']:
        print(json.dumps(result))
        sys.exit(0)

    ds = ogr.Open(shp)
    if ds is None:
        result['error'] = 'ogr.Open returned None'
        print(json.dumps(result))
        sys.exit(0)

    lyr = ds.GetLayer()
    result['feature_count'] = lyr.GetFeatureCount()

    # Check first feature geometry type
    first = lyr.GetNextFeature()
    if first:
        geom = first.GetGeometryRef()
        if geom:
            result['geom_type'] = geom.GetGeometryName()
    lyr.ResetReading()

    # Check CRS
    srs = lyr.GetSpatialRef()
    if srs:
        result['crs_wkt'] = srs.ExportToWkt()
        srs.AutoIdentifyEPSG()
        auth = srs.GetAuthorityCode(None)
        if auth:
            result['epsg_code'] = int(auth)
        else:
            # Fallback: compare against EPSG:32633
            target_srs = osr.SpatialReference()
            target_srs.ImportFromEPSG(32633)
            if srs.IsSame(target_srs):
                result['epsg_code'] = 32633

    ds = None
    print(json.dumps(result))

except Exception as e:
    import traceback
    print(json.dumps({'error': str(e), 'tb': traceback.format_exc()}))
PYEOF

chmod 666 /tmp/reproject_rivers_utm33n_result.json 2>/dev/null || true
echo "Result JSON:"
cat /tmp/reproject_rivers_utm33n_result.json
echo ""
echo "=== Export Complete ==="
