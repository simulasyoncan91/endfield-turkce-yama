import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

ROOT=Path(__file__).resolve().parents[1]
SPEC=importlib.util.spec_from_file_location('translation_core',ROOT/'bin/translation_core.py')
core=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(core)


def spark(values):
    # Minimal known-format EN long/string map. Directory is unused by readers.
    b=bytearray(struct.pack('<iii',12,16,0)+struct.pack('<i',0))
    b.extend(b'\x0aI18nTextTable_EN\x00\x03\x07')
    pointers={}
    for key,value in values.items():
        if value is None: pointers[key]=-1
        else:pointers[key]=len(b);b.extend(value.encode('utf-8')+b'\0')
    while len(b)%4:b.append(0)
    data=len(b);struct.pack_into('<i',b,8,data);b.extend(struct.pack('<i',len(values))+b'\0'*(len(values)*8))
    for key in values:
        while len(b)%8:b.append(0)
        b.extend(struct.pack('<qi',int(key),pointers[key]))
    return bytes(b)


def metadata(chunk, files, version=12345678, code=5, trailer=b'1234567890'):
    identity=bytes.fromhex('11223344556677889900AABBCCDDEEFF')
    b=bytearray(struct.pack('<iiH',code,version,5)+b'Table'+struct.pack('<qi',9876,len(files)))
    b.extend(struct.pack('<qBi',len(chunk),18,1))
    b.extend(identity+hashlib.md5(chunk).digest()+struct.pack('<qB',len(chunk),18))
    tag=struct.pack('<Q',0)if code==5 else struct.pack('<I',0)if code==4 else b''
    b.extend(tag+struct.pack('<i',len(files)))
    for name,offset,payload,encrypted in files:
        nb=name.encode();b.extend(struct.pack('<H',len(nb))+nb+struct.pack('<q',55)+identity+hashlib.md5(payload).digest()+struct.pack('<qqBB',offset,len(payload),18,1 if encrypted else 0))
        if encrypted:b.extend(struct.pack('<q',-216232979))
        b.extend(tag)
    b.extend(trailer);b.extend(struct.pack('<I',zlib.crc32(b)))
    return bytes(b),identity.hex().upper()+'.chk'


def row(identifier='1',source='Shop',tr='Mağaza',refs=None):
    return {'id':identifier,'source_en':source,'translation_tr':tr,'references':refs if refs is not None else [{'table':'TextTable','row':'ui_shop','field':'(row)'}],'protected_tokens':core.TOKEN_RE.findall(source),'source_sha256':hashlib.sha256(source.encode()).hexdigest()}


def catalog(rows):return {'schema':core.CATALOG_SCHEMA,'source_build':12345678,'records':rows}


class CoreIndependentTests(unittest.TestCase):
    def setUp(self):
        self.source={'1':'Shop','2':'Operators','3':'Unchanged','4':''}
        self.payload=spark({**self.source,'4':None})

    def test_two_utf8_values_only_keys_other_values_preserved(self):
        patched=core.patch_i18n(self.payload,self.source,{'1':'Mağaza','2':'Karakterler'})
        result=core.parse_i18n(patched)['values']
        self.assertEqual(result,{**self.source,'1':'Mağaza','2':'Karakterler'})
        self.assertEqual(set(result),set(self.source))
        self.assertGreater(len(patched),len(self.payload))

    def test_repeat_patching_appended_input_is_rejected(self):
        patched=core.patch_i18n(self.payload,self.source,{'1':'Mağaza'})
        with self.assertRaises(core.CoreError):core.patch_i18n(patched,{**self.source,'1':'Mağaza'},{'2':'Karakterler'})

    def test_zero_selection_is_bytewise_identity(self):
        self.assertEqual(core.patch_i18n(self.payload,self.source,{}),self.payload)

    def test_empty_sentinel_is_preserved(self):
        parsed=core.parse_i18n(self.payload,self.source,pristine=True)
        self.assertEqual(parsed['values']['4'],'')
        self.assertEqual(struct.unpack_from('<i',self.payload,parsed['slots']['4'])[0],-1)

    def test_literal_zero_pointer_is_not_treated_as_missing(self):
        b=bytearray(self.payload);parsed=core.parse_i18n(b)
        struct.pack_into('<i',b,parsed['slots']['1'],0)
        value=core.parse_i18n(b)['values']['1']
        self.assertEqual(value,'\x0c') # byte 0 of type-definition offset, NUL at byte 1

    def test_corrupt_map_and_pointer_fail_closed(self):
        bad=bytearray(self.payload);struct.pack_into('<i',bad,8,len(bad)+100)
        with self.assertRaises(core.CoreError):core.parse_i18n(bad)
        bad=bytearray(self.payload);slot=core.parse_i18n(bad)['slots']['1'];struct.pack_into('<i',bad,slot,len(bad)+1)
        with self.assertRaises(core.CoreError):core.parse_i18n(bad)

    def test_source_changed_same_id_is_reviewed(self):
        r=row();selected,review,_=core.select_translations(catalog([r]),{'1':'Store'},{'1':r['references']})
        self.assertEqual(selected,{});self.assertEqual(review[0]['reason'],'source_changed')

    def test_context_change_is_reviewed_but_order_is_not(self):
        refs=[{'table':'TextTable','row':'ui_shop','field':'(row)'},{'table':'Another','row':'item','field':'/name'}];r=row(refs=refs)
        selected,review,_=core.select_translations(catalog([r]),{'1':'Shop'},{'1':list(reversed(refs))})
        self.assertEqual(selected,{'1':'Mağaza'});self.assertFalse(review)
        selected,review,_=core.select_translations(catalog([r]),{'1':'Shop'},{'1':[refs[0]]})
        self.assertFalse(selected);self.assertEqual(review[0]['reason'],'context_changed')

    def test_missing_and_unavailable_context_are_distinct(self):
        r=row();self.assertEqual(core.select_translations(catalog([r]),{},{} )[1][0]['reason'],'removed_from_current_source')
        self.assertEqual(core.select_translations(catalog([r]),{'1':'Shop'},{} )[1][0]['reason'],'fresh_context_unavailable')

    def test_token_and_edge_whitespace_loss_rejected(self):
        for r in [row(source='Value %s',tr='Değer'),row(source=' <@a>Shop</> ',tr='<@a>Mağaza</>')]:
            with self.assertRaises(core.CoreError):core.validate_catalog_row(r)

    def test_percent_exception_is_narrow(self):
        r=row('5807238442710209203','110% ORIGEOMETRY RETURNS!','%110 ORIGEOMETRY İADESİ!')
        # This layout's translated literal percent is no formatting placeholder.
        core.validate_catalog_row(r)
        r['id']='42'
        with self.assertRaises(core.CoreError):core.validate_catalog_row(r)

    def test_duplicate_catalog_id_rejected(self):
        r=row()
        with self.assertRaises(core.CoreError):core.select_translations(catalog([r,r]),{'1':'Shop'},{'1':r['references']})

    def fixture(self,code=5,encrypted=False):
        prefix=b'PREFIX-CONTENT';gap=b'opaque-gap';suffix=b'SUFFIX-CONTENT'
        original=prefix+gap+self.payload+gap+suffix
        begin=len(prefix)+len(gap);end=begin+len(self.payload)
        files=[('before.bin',0,prefix,False),('Data/TableCfg/I18nTextTable_EN.bytes',begin,self.payload,encrypted),('after.bin',end+len(gap),suffix,False)]
        meta,chname=metadata(original,files,code=code)
        ctx={'Version':12345678,'Chunk':chname,'FileName':files[1][0],'Offset':begin,'Length':len(self.payload),'ChunkLength':len(original),'IvSeed':-216232979 if encrypted else 0}
        return original,meta,ctx,begin,end,prefix,gap,suffix

    def test_multifile_chunk_preserves_other_bytes_shifts_offsets(self):
        original,meta,ctx,begin,end,prefix,gap,suffix=self.fixture()
        translated=core.patch_i18n(self.payload,self.source,{'1':'Mağaza','2':'Karakterler'})
        new_chunk,new_meta=core.rebuild_container(meta,ctx,self.payload,translated,original,translated)
        self.assertEqual(new_chunk,original[:begin]+translated+original[end:])
        old=core.parse_metadata(meta);new=core.parse_metadata(new_meta)
        oldf={x['name']:x for x in old['files']};newf={x['name']:x for x in new['files']};delta=len(translated)-len(self.payload)
        self.assertEqual(newf['before.bin']['offset'],oldf['before.bin']['offset'])
        self.assertEqual(newf['after.bin']['offset'],oldf['after.bin']['offset']+delta)
        for n in ['before.bin','after.bin']:
            self.assertEqual(newf[n]['data_md5'],oldf[n]['data_md5'])
            self.assertEqual(new_chunk[newf[n]['offset']:newf[n]['offset']+newf[n]['length']],original[oldf[n]['offset']:oldf[n]['offset']+oldf[n]['length']])
        self.assertEqual(new['trailer'],old['trailer'])
        self.assertEqual(new['chunks'][0]['identity'],old['chunks'][0]['identity'])

    def test_encrypted_chunk_ciphertext_hash_separate_from_plaintext(self):
        original,meta,ctx,begin,end,*_=self.fixture(encrypted=True)
        # Actual crypto is the bridge's job. Use an arbitrary same-length byte transform.
        translated=core.patch_i18n(self.payload,self.source,{'1':'Mağaza'});encrypted=bytes(b^0xA5 for b in translated)
        new_chunk,new_meta=core.rebuild_container(meta,ctx,self.payload,translated,original,encrypted)
        parsed=core.parse_metadata(new_meta);target=next(x for x in parsed['files']if x['name']==ctx['FileName'])
        self.assertEqual(target['data_md5'],hashlib.md5(translated).hexdigest())
        self.assertEqual(parsed['chunks'][0]['content_md5'],hashlib.md5(new_chunk).hexdigest())
        self.assertEqual(new_chunk[begin:begin+len(encrypted)],encrypted)
        self.assertNotEqual(hashlib.md5(encrypted).hexdigest(),target['data_md5'])

    def test_three_supported_metadata_versions(self):
        for code in (3,4,5):
            with self.subTest(code=code):
                _,meta,_,*_=self.fixture(code=code);self.assertEqual(core.parse_metadata(meta)['code_version'],code)

    def test_bad_crc_and_unknown_version_refused(self):
        _,meta,_,*_=self.fixture();bad=bytearray(meta);bad[-1]^=1
        with self.assertRaises(core.CoreError):core.parse_metadata(bad)
        bad=bytearray(meta);struct.pack_into('<i',bad,0,6);struct.pack_into('<I',bad,len(bad)-4,zlib.crc32(bad[:-4]))
        with self.assertRaises(core.CoreError):core.parse_metadata(bad)

    def test_context_or_original_chunk_tampering_refused(self):
        original,meta,ctx,*_=self.fixture();translated=core.patch_i18n(self.payload,self.source,{'1':'Mağaza'})
        wrong=dict(ctx);wrong['Chunk']='CHANGED.chk'
        with self.assertRaises(core.CoreError):core.rebuild_container(meta,wrong,self.payload,translated,original,translated)
        wrong_chunk=bytearray(original);wrong_chunk[0]^=1
        with self.assertRaises(core.CoreError):core.rebuild_container(meta,ctx,self.payload,translated,wrong_chunk,translated)

    def test_rebuild_zero_change_is_bytewise_identity(self):
        original,meta,ctx,*_=self.fixture()
        new_chunk,new_meta=core.rebuild_container(meta,ctx,self.payload,self.payload,original,self.payload)
        self.assertEqual(new_chunk,original);self.assertEqual(new_meta,meta)


if __name__=='__main__':unittest.main(verbosity=2)
