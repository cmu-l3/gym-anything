import pandas as pd

data_path = '/tmp/sanfran_public.h5'
buildings = pd.read_hdf(data_path, 'buildings')
print(list(buildings.columns))
