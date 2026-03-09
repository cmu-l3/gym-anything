#!/bin/bash
echo "=== Exporting filter_south_america_major result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF' > /tmp/filter_south_america_major_result.json
import json, sys, os
try:
    from osgeo import ogr

    shp = '/home/ga/gvsig_exports/south_america_major.shp'
    src = '/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shp'

    result = {
        'file_exists': os.path.isfile(shp),
        'feature_count': None,
        'source_feature_count': None,
        'has_continent_field': False,
        'has_pop_est_field': False,
        'all_south_america': False,
        'all_pop_gt_5m': False,
        'continent_values': [],
        'min_pop': None,
        'max_pop': None,
        'country_names': [],
        'error': None,
    }

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

    defn = lyr.GetLayerDefn()
    fields_upper = [defn.GetFieldDefn(i).GetName().upper() for i in range(defn.GetFieldCount())]
    result['has_continent_field'] = 'CONTINENT' in fields_upper
    result['has_pop_est_field'] = 'POP_EST' in fields_upper

    if result['has_continent_field'] and result['has_pop_est_field']:
        continents = set()
        pops = []
        names = []
        for feat in lyr:
            cont = feat.GetField('CONTINENT') or ''
            pop = feat.GetField('POP_EST')
            name = feat.GetField('NAME') or feat.GetField('name') or ''
            if cont:
                continents.add(cont)
            if pop is not None:
                pops.append(pop)
            if name:
                names.append(name)
        lyr.ResetReading()

        result['continent_values'] = sorted(list(continents))
        result['all_south_america'] = (continents == {'South America'}) if continents else False
        result['all_pop_gt_5m'] = all(p > 5000000 for p in pops) if pops else False
        result['min_pop'] = min(pops) if pops else None
        result['max_pop'] = max(pops) if pops else None
        result['country_names'] = sorted(names)

    ds = None
    print(json.dumps(result))

except Exception as e:
    import traceback
    print(json.dumps({'error': str(e), 'tb': traceback.format_exc()}))
PYEOF

chmod 666 /tmp/filter_south_america_major_result.json 2>/dev/null || true
echo "Result JSON:"
cat /tmp/filter_south_america_major_result.json
echo ""
echo "=== Export Complete ==="
