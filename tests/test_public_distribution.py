import json,unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

class PublicDistributionTests(unittest.TestCase):
    def test_existing_installer_channel_holds_unsupported_row(self):
        catalog=json.loads((ROOT/'translations/catalog.json').read_text('utf-8'))
        progress=json.loads((ROOT/'translations/progress.json').read_text('utf-8'))
        self.assertNotIn('3117923866152746089',{r['id']for r in catalog['records']})
        self.assertEqual(progress['compatibility_held'],1)
        self.assertEqual(progress['prepared_total'],len(catalog['records'])+1)

    def test_compact_rows_cannot_carry_private_source_fields(self):
        catalog=json.loads((ROOT/'translations/catalog.json').read_text('utf-8'))
        allowed={'id','tr','source_sha256','refs','protected_tokens'}
        self.assertEqual(catalog['schema'],'endfield.translation_catalog.compact.v1')
        for row in catalog['records']:
            self.assertEqual(set(row),allowed)
            self.assertIsInstance(row['tr'],str)
        self.assertLess((ROOT/'translations/catalog.json').stat().st_size,33554432)

if __name__=='__main__':unittest.main()
