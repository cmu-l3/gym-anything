import urllib.request
import json

url = "https://celestrak.org/NORAD/elements/gp.php?CATNR=13552&FORMAT=tle"
try:
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    html = urllib.request.urlopen(req).read().decode('utf-8')
    print("Celestrak current TLE:")
    print(html)
except Exception as e:
    print("Error:", e)
