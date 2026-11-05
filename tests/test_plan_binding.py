import importlib.util,json,unittest,tempfile
from pathlib import Path
from types import SimpleNamespace
p=Path(__file__).with_name('test_core_independent.py');s=importlib.util.spec_from_file_location('fixtures',p);fx=importlib.util.module_from_spec(s);s.loader.exec_module(fx);core=fx.core
class PlanBindingTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.source={'1':'Shop','2':'Operators'};self.raw=fx.spark(self.source);meta,name=fx.metadata(self.raw,[('Data/TableCfg/I18nTextTable_EN.bytes',0,self.raw,False)])
  inputs={'original.bytes':self.raw,'metadata.plain':meta}
  for n,b in inputs.items():(self.root/n).write_bytes(b)
  self.ctx={'Version':12345678,'Chunk':name,'FileName':'Data/TableCfg/I18nTextTable_EN.bytes','Offset':0,'Length':len(self.raw),'ChunkLength':len(self.raw),'IvSeed':'0'}
  self.row=fx.row();values={'source.json':self.source,'context.json':self.ctx,'refs.json':{'1':self.row['references']},'catalog.json':fx.catalog([self.row])}
  for n,o in values.items():(self.root/n).write_text(json.dumps(o,ensure_ascii=False),'utf-8')
  self.out=self.root/'build';core.prepare(SimpleNamespace(original_bytes=self.root/'original.bytes',source_json=self.root/'source.json',metadata_plain=self.root/'metadata.plain',context=self.root/'context.json',references=self.root/'refs.json',catalog=self.root/'catalog.json',output=self.out))
  self.encrypted=self.root/'encrypted.bin';self.encrypted.write_bytes((self.out/'translated.bytes').read_bytes());self.chunk=self.root/'original.chk';self.chunk.write_bytes(self.raw)
  self.args=SimpleNamespace(plan=self.out/'build_plan.json',encrypted_file=self.encrypted,original_chunk=self.chunk)
 def tearDown(self):self.temp.cleanup()
 def test_repeated_finalize_is_identical(self):
  first=core.finalize(self.args);before=(self.out/'translated.chk').read_bytes();second=core.finalize(self.args);self.assertEqual(first,second);self.assertEqual(before,(self.out/'translated.chk').read_bytes())
 def test_added_identity_row_cannot_inflate_translation_count(self):
  p=self.out/'selected_translations.json';m=json.loads(p.read_text('utf-8'));m['2']='Operators';p.write_text(json.dumps(m),'utf-8')
  with self.assertRaisesRegex(core.CoreError,'Selected translations changed'):core.finalize(self.args)
 def test_identity_row_refused_even_if_plan_hash_is_altered(self):
  p=self.out/'selected_translations.json';m=json.loads(p.read_text('utf-8'));m['2']='Operators';p.write_text(json.dumps(m),'utf-8');bp=self.out/'build_plan.json';plan=json.loads(bp.read_text('utf-8'));plan['selected_translations_sha256']=core.sha(p.read_bytes());bp.write_text(json.dumps(plan),'utf-8')
  with self.assertRaisesRegex(core.CoreError,'Invalid selected translation'):core.finalize(self.args)
if __name__=='__main__':unittest.main(verbosity=2)
