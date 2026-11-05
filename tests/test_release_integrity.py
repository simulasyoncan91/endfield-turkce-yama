"""Verify the shipped catalog descriptor against the actual release bytes."""
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class ReleaseIntegrityTests(unittest.TestCase):
    def test_published_catalog_bytes_and_progress(self):
        latest = json.loads((ROOT / "translations/latest.json").read_text("utf-8"))
        data = (ROOT / latest["catalog_path"]).read_bytes()
        self.assertEqual(len(data), latest["catalog_bytes"])
        self.assertEqual(hashlib.sha256(data).hexdigest(), latest["catalog_sha256"])
        catalog = json.loads(data)
        progress = json.loads((ROOT / "translations/progress.json").read_text("utf-8"))
        self.assertEqual(catalog["translation_release"], latest["version"])
        self.assertEqual(progress["release"], latest["version"])
        self.assertEqual(len(catalog["records"]), progress["translated"])
        self.assertEqual(len({r["id"] for r in catalog["records"]}), len(catalog["records"]))
        self.assertTrue(all("source_en" not in r for r in catalog["records"]))
        self.assertEqual(progress["translated"] + progress["retained_not_translation"] + progress["pending"], progress["source_total"])

if __name__ == "__main__":
    unittest.main()
