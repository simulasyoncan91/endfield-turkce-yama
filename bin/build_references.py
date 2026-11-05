"""Build localization reference index from freshly decoded tables; no game writes."""
import argparse,json,hashlib
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--tables',required=True);p.add_argument('--source',required=True);p.add_argument('--output',required=True);a=p.parse_args()
source=json.loads(Path(a.source).read_text('utf-8-sig'));refs={k:[]for k in source}
def walk(value,table,row,path):
 if isinstance(value,dict):
  if 'id'in value and 'text'in value and str(value['id'])in refs:refs[str(value['id'])].append({'table':table,'row':row,'field':path or '(row)'})
  for k,v in value.items():walk(v,table,row,path+'/'+k)
 elif isinstance(value,list):
  for i,v in enumerate(value):walk(v,table,row,path+'/'+str(i))
for file in sorted(Path(a.tables).glob('*.json')):
 value=json.loads(file.read_text('utf-8-sig'))
 if isinstance(value,dict):
  for row,body in value.items():walk(body,file.stem,row,'')
 else:walk(value,file.stem,'(root)','')
out=Path(a.output);data=(json.dumps(refs,ensure_ascii=False,separators=(',',':'))+'\n').encode()
if out.exists()and out.read_bytes()!=data:raise ValueError('Refusing to overwrite a different reference index')
out.write_bytes(data);print(json.dumps({'records':len(refs),'referenced':sum(bool(v)for v in refs.values())}))
