import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from log_archive import ArchiveError, archive_segment, verify_archive


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "closed.log"
        self.data = b"subscriber=example src=192.0.2.1 port=4567 time=2026-11-10T10:00:00Z\r\n" * 20000 + b"\x00\xfflast"
        self.source.write_bytes(self.data)

    def pack(self, **kwargs):
        return archive_segment(self.source, self.root / "archives", "tenant-a", "nas-1", "ipdr", sealed=True, **kwargs)

    def test_exact_bytes_verified_and_source_preserved(self):
        path, manifest = self.pack()
        self.assertEqual(verify_archive(path, "tenant-a")["raw_bytes"], len(self.data))
        self.assertEqual(self.source.read_bytes(), self.data)
        self.assertFalse(manifest["source_deleted"])
        self.assertLess(manifest["compressed_bytes"], manifest["raw_bytes"])

    def test_corruption_detected(self):
        path, _ = self.pack()
        with (path / "records.zst").open("ab") as stream:
            stream.write(b"corrupt")
        with self.assertRaises(ArchiveError):
            verify_archive(path, "tenant-a")

    def test_wrong_tenant_denied(self):
        path, _ = self.pack()
        with self.assertRaises(ArchiveError):
            verify_archive(path, "tenant-b")

    def test_manifest_raw_checksum_mismatch_detected(self):
        path, manifest = self.pack()
        manifest["raw_sha256"] = "0" * 64
        (path / "manifest.json").write_text(json.dumps(manifest))
        with self.assertRaises(ArchiveError):
            verify_archive(path, "tenant-a")

    def test_requires_rotated_source(self):
        with self.assertRaises(ArchiveError):
            archive_segment(self.source, self.root, "tenant-a", "nas-1", "ipdr")

    def test_path_traversal_rejected(self):
        with self.assertRaises(ArchiveError):
            archive_segment(self.source, self.root, "../tenant-b", "nas-1", "ipdr", sealed=True)

    def test_symlink_source_rejected(self):
        link = self.root / "link.log"
        link.symlink_to(self.source)
        with self.assertRaises(OSError):
            archive_segment(link, self.root, "tenant-a", "nas-1", "ipdr", sealed=True)

    def test_existing_archive_is_never_overwritten(self):
        first, _ = self.pack()
        second, _ = self.pack()
        self.assertNotEqual(first, second)
        verify_archive(first, "tenant-a")

    def test_failed_verification_does_not_publish_or_delete_source(self):
        with patch("log_archive.verify_archive", side_effect=ArchiveError("failed")):
            with self.assertRaises(ArchiveError):
                self.pack()
        self.assertEqual(list((self.root / "archives").rglob("records.zst")), [])
        self.assertEqual(self.source.read_bytes(), self.data)

    def test_empty_file_round_trip(self):
        self.source.write_bytes(b"")
        path, _ = self.pack()
        self.assertEqual(verify_archive(path, "tenant-a")["raw_bytes"], 0)


if __name__ == "__main__":
    unittest.main()
