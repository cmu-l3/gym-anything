#!/bin/bash
echo "=== Exporting buffer_world_capitals result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF' > /tmp/buffer_world_capitals_result.json
import json, sys, os
try:
    from osgeo import ogr

    shp = '/home/ga/gvsig_exports/capital_buffers.shp'
    src = '/home/ga/gvsig_data/cities/ne_110m_populated_places.shp'

    result = {
        'file_exists': os.path.isfile(shp),
        'feature_count': None,
        'source_capital_count': None,
        'geom_type': None,
        'is_polygon': False,
        'has_name_field': False,
        'has_featurecla_field': False,
        'fields': [],
        'error': None,
    }

    # Count source Admin-0 capitals
    ds_src = ogr.Open(src)
    if ds_src:
        lyr_src = ds_src.GetLayer()
        count = 0
        for feat in lyr_src:
            fc = feat.GetField('FEATURECLA') or ''
            if fc == 'Admin-0 capital':
                count += 1
        result['source_capital_count'] = count
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

    defn = lyr.GetLayerDefn()
    fields = [defn.GetFieldDefn(i).GetName() for i in range(defn.GetFieldCount())]
    result['fields'] = fields[:20]
    fields_upper = [f.upper() for f in fields]
    result['has_name_field'] = 'NAME' in fields_upper
    result['has_featurecla_field'] = 'FEATURECLA' in fields_upper

    # Check geometry type
    first = lyr.GetNextFeature()
    if first:
        geom = first.GetGeometryRef()
        if geom:
            geom_name = geom.GetGeometryName()
            result['geom_type'] = geom_name
            result['is_polygon'] = geom_name in ('POLYGON', 'MULTIPOLYGON', 'Polygon', 'MultiPolygon')
    lyr.ResetReading()

    ds = None
    print(json.dumps(result))

except Exception as e:
    import traceback
    print(json.dumps({'error': str(e), 'tb': traceback.format_exc()}))
PYEOF

chmod 666 /tmp/buffer_world_capitals_result.json 2>/dev/null || true
echo "Result JSON:"
cat /tmp/buffer_world_capitals_result.json
echo ""
echo "=== Export Complete ==="
