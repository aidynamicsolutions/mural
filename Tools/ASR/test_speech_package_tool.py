import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("publisher", Path(__file__).with_name("make_speech_package.py"))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)

class PackageToolTests(unittest.TestCase):
    def test_canonical_encoding(self):
        self.assertEqual(publisher.canonical({"z":1,"a":"臺灣"}), '{"a":"臺灣","z":1}'.encode())
    def test_paths(self):
        publisher.safe("support/TextDecoder.mlmodelc/weights/weight.bin")
        for path in ("../x", "/x", "support//a", "a\\b", "a/%2e%2e", "a/.", "a/"):
            with self.assertRaises(ValueError): publisher.safe(path)
    def test_duplicates(self):
        with self.assertRaises(ValueError): publisher.no_duplicates([("id",1),("id",2)])
    def test_inventory_checks_all_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); (root/"b").write_bytes(b"b"); (root/"a").write_bytes(b"a")
            rows=publisher.inventory(root,"support")
            self.assertEqual([r["path"] for r in rows], ["support/a","support/b"])
            self.assertEqual(sum(r["bytes"] for r in rows),2)
            (root/"a").write_bytes(b"c")
            self.assertNotEqual(rows[0]["sha256"], publisher.inventory(root,"support")[0]["sha256"])
    def test_symlink_is_not_followed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); (root/"link").symlink_to("/does-not-exist")
            with self.assertRaises(ValueError): publisher.inventory(root,"support")
    def test_wrong_reviewed_pin_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); (root/"manifest.json").write_text("{}")
            with self.assertRaises(ValueError): publisher.pinned_json(root, publisher.BREEZE_PIN)

if __name__ == "__main__": unittest.main()
