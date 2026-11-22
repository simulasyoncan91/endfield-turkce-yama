"""Check both downloadable data channels and the newer percentage exceptions."""
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("catalog_core", REPO / "bin/translation_core.py")
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)


class CurrentChannelTests(unittest.TestCase):
    def test_full_catalog_matches_public_descriptor_and_coverage(self):
        base = REPO / "translations/current"
        descriptor = json.loads((base / "latest.json").read_bytes())
        progress = json.loads((base / "progress.json").read_bytes())
        self.assertEqual(descriptor["catalog_path"], "translations/current/catalog.json")
        data = (REPO / descriptor["catalog_path"]).read_bytes()
        self.assertEqual(len(data), descriptor["catalog_bytes"])
        self.assertLessEqual(len(data), 64 * 1024**2)
        self.assertEqual(hashlib.sha256(data).hexdigest(), descriptor["catalog_sha256"])
        catalog = json.loads(data)
        rows = catalog["records"]
        self.assertEqual(progress["release"], descriptor["version"])
        self.assertEqual(progress["release"], catalog["translation_release"])
        self.assertEqual(catalog["source_build"], progress["source_build"])
        self.assertEqual(len(rows), len({r["id"] for r in rows}))
        self.assertEqual(len(rows), progress["translated"])
        self.assertEqual(len(rows) + progress["unchanged"], progress["source_total"])
        allowed = {"id", "tr", "source_sha256", "refs", "protected_tokens"}
        for row in rows:
            self.assertEqual(set(row), allowed)
            self.assertTrue(all(set(ref) == {"table", "row", "field"} for ref in row["refs"]))
            self.assertNotEqual(hashlib.sha256(row["tr"].encode()).hexdigest(), row["source_sha256"])

    def test_percentage_exception_rejects_other_text_or_id(self):
        for identifier, (_, _, literal) in core.REVIEWED_PERCENTAGE_PINS.items():
            self.assertFalse(core.reviewed_percentage_tokens_match(identifier, "changed", "değişti", [literal], []))
            self.assertFalse(core.reviewed_percentage_tokens_match("1", "changed", "değişti", [literal], []))
            self.assertFalse(core.reviewed_percentage_tokens_match(identifier, "changed", "değişti", ["%s"], []))


if __name__ == "__main__":
    unittest.main()
