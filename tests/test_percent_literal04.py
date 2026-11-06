import copy,hashlib,importlib.util,unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('percent_core',ROOT/'bin/translation_core.py')
core=importlib.util.module_from_spec(spec);spec.loader.exec_module(core)

class FourthLiteralPercentTests(unittest.TestCase):
    def row(self):
        source="Now I'm 1000% looking forward to it."
        return {'id':'3117923866152746089','source_en':source,'translation_tr':'Şimdi heyecanım 1000%!','source_sha256':hashlib.sha256(source.encode()).hexdigest(),'references':[],'protected_tokens':core.TOKEN_RE.findall(source)}

    def test_exact_literal_case_is_supported(self):
        core.validate_catalog_row(self.row())

    def test_other_id_does_not_get_the_exception(self):
        row=self.row();row['id']='3117923866152746090'
        with self.assertRaises(core.CoreError):core.validate_catalog_row(row)

    def test_changed_source_does_not_get_the_exception(self):
        row=self.row();row['source_en']+=' Changed.';row['source_sha256']=hashlib.sha256(row['source_en'].encode()).hexdigest()
        with self.assertRaises(core.CoreError):core.validate_catalog_row(row)

    def test_real_format_token_cannot_be_added(self):
        row=self.row();row['translation_tr']+=' %s'
        with self.assertRaises(core.CoreError):core.validate_catalog_row(row)

if __name__=='__main__':unittest.main()
