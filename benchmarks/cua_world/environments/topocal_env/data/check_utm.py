import pyproj

# EPSG:32613 is WGS 84 / UTM zone 13N
proj = pyproj.Transformer.from_crs("epsg:32613", "epsg:4326", always_xy=True)
lon, lat = proj.transform(474812.548, 4396771.501)
print(f"Lon: {lon}, Lat: {lat}")
