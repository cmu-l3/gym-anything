#!/bin/bash
echo "=== Exporting dissolve_by_continent result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF' > /tmp/dissolve_by_continent_result.json
import json, sys, os
try:
    from osgeo import ogr

    shp = '/home/ga/gvsig_exports/continents_dissolved.shp'
    src = '/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shp'

    result = {
        'file_exists': os.path.isfile(shp),
        'feature_count': None,
        'source_continent_count': None,
        'has_continent_field': False,
        'continent_values': [],
        'africa_present': False,
        'asia_present': False,
        'europe_present': False,
        'geom_type': None,
        'error': None,
    }

    # Count source distinct continents
    ds_src = ogr.Open(src)
    if ds_src:
        lyr_src = ds_src.GetLayer()
        conts = set()
        for feat in lyr_src:
            c = feat.GetField('CONTINENT') or ''
            if c:
                conts.add(c)
        result['source_continent_count'] = len(conts)
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
    fields_upper = [defn.GetFieldDefn(i).GetName().upper() for i in range(defn.GetFieldCount())]
    result['has_continent_field'] = 'CONTINENT' in fields_upper

    first = lyr.GetNextFeature()
    if first:
        geom = first.GetGeometryRef()
        if geom:
            result['geom_type'] = geom.GetGeometryName()
    lyr.ResetReading()

    if result['has_continent_field']:
        cont_values = []
        for feat in lyr:
            c = feat.GetField('CONTINENT') or ''
            if c and c not in cont_values:
                cont_values.append(c)
        lyr.ResetReading()

        result['continent_values'] = cont_values
        cv_lower = [v.lower() for v in cont_values]
        result['africa_present'] = 'africa' in cv_lower
        result['asia_present'] = 'asia' in cv_lower
        result['europe_present'] = 'europe' in cv_lower

    ds = None
    print(json.dumps(result))

except Exception as e:
    import traceback
    print(json.dumps({'error': str(e), 'tb': traceback.format_exc()}))
PYEOF

chmod 666 /tmp/dissolve_by_continent_result.json 2>/dev/null || true
echo "Result JSON:"
cat /tmp/dissolve_by_continent_result.json
echo ""
echo "=== Export Complete ==="
