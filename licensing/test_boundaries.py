import copy
import datetime as dt
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from omisha_license import (
    LicenseError, MAX_SIZE, activate, atomic_write, issue, load_json,
    status_response, strict_json, timestamp, verify,
)


class BoundaryTests(unittest.TestCase):
    def setUp(self):
        self.key = Ed25519PrivateKey.generate()
        self.now = dt.datetime.now(dt.timezone.utc)
        self.payload = {"schema": 1, "license_id": "test", "tenant_id": "tenant-a",
                        "installation_id": "install-a", "max_users": 2, "features": ["crm"],
                        "issued_at": (self.now - dt.timedelta(hours=1)).isoformat().replace("+00:00", "Z"),
                        "expires_at": (self.now + dt.timedelta(hours=1)).isoformat().replace("+00:00", "Z")}
        self.signed = issue(self.key, self.payload)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.public = Path(self.temp.name) / "public.pem"
        self.license = Path(self.temp.name) / "license.json"
        self.public.write_bytes(self.key.public_key().public_bytes(
            serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo))
        atomic_write(self.license, json.dumps(self.signed).encode())

    def response(self, path, tenant="tenant-a"):
        return status_response(path, self.public, self.license, tenant, "install-a")

    def test_feature_is_checked_after_signature_and_scope(self):
        verify(self.key.public_key(), self.signed, "tenant-a", "install-a", required_feature="crm")
        for feature in ("hr", "", 1):
            with self.subTest(feature=feature), self.assertRaises(LicenseError):
                verify(self.key.public_key(), self.signed, "tenant-a", "install-a", required_feature=feature)
        altered = copy.deepcopy(self.signed)
        altered["payload"]["features"].append("hr")
        with self.assertRaises(LicenseError):
            verify(self.key.public_key(), altered, "tenant-a", "install-a", required_feature="hr")

    def test_liveness_survives_missing_license_but_readiness_fails(self):
        self.license.unlink()
        self.assertEqual(self.response("/health")[0], 200)
        self.assertEqual(self.response("/readyz"), (503, {"status": "invalid_or_missing"}))

    def test_readiness_scope_is_explicit(self):
        code, body = self.response("/readyz")
        self.assertEqual(code, 200)
        self.assertEqual(body["scope"], "signed_license_only")
        self.assertEqual(body["seat_enforcement"], "not connected")

    def test_cross_tenant_readiness_fails(self):
        self.assertEqual(self.response("/readyz", "tenant-b")[0], 503)

    def test_tampered_license_fails(self):
        self.signed["payload"]["max_users"] = 1000
        atomic_write(self.license, json.dumps(self.signed).encode())
        self.assertEqual(self.response("/license")[0], 503)

    def test_expired_license_fails(self):
        self.payload["issued_at"] = "2020-01-01T00:00:00Z"
        self.payload["expires_at"] = "2021-01-01T00:00:00Z"
        atomic_write(self.license, json.dumps(issue(self.key, self.payload)).encode())
        self.assertEqual(self.response("/readyz")[0], 503)

    def test_ambiguous_and_malformed_json_is_rejected(self):
        for raw in (b'{"schema":1,"schema":2}', b'{"x":NaN}', b'{"x":Infinity}',
                    b'\xff', b'[' * 2000, b'x' * (MAX_SIZE + 1)):
            with self.subTest(raw=raw[:30]), self.assertRaises(LicenseError):
                strict_json(raw)

    def test_oversized_file_is_rejected(self):
        self.license.write_bytes(b" " * (MAX_SIZE + 1))
        with self.assertRaises(LicenseError):
            load_json(self.license)
        self.assertEqual(self.response("/readyz")[0], 503)

    def test_malformed_key_fails_without_leaking_path(self):
        self.public.write_text("not a public key")
        self.assertEqual(self.response("/license"), (503, {"status": "invalid_or_missing"}))

    def test_strict_utc_timestamp(self):
        for value in ("2026-01-01Z", "2026-01-01 00:00:00Z", "2026-01-01T00:00:00+01:00Z", "2026-13-01T00:00:00Z"):
            with self.subTest(value=value), self.assertRaises(LicenseError):
                timestamp(value)

    def test_naive_clock_is_rejected(self):
        with self.assertRaises(LicenseError):
            verify(self.key.public_key(), self.signed, "tenant-a", "install-a", now=dt.datetime(2026, 1, 1))

    def test_invalid_seat_count_types(self):
        for value in (True, -1, 1.5, "1"):
            with self.subTest(value=value), self.assertRaises(LicenseError):
                verify(self.key.public_key(), self.signed, "tenant-a", "install-a", active_users=value)

    def test_duplicate_features_rejected(self):
        self.payload["features"] = ["crm", "crm"]
        with self.assertRaises(LicenseError):
            issue(self.key, self.payload)

    def test_activation_rejects_credentials_and_unsafe_urls_before_network(self):
        with patch("omisha_license.urllib.request.build_opener") as opener:
            for url in ("http://authority.example/activate", "https://user:pass@authority.example/activate", "https://authority.example/#fragment"):
                with self.subTest(url=url), self.assertRaises(LicenseError):
                    activate(url, "test-code", "tenant-a", "install-a")
            for code in ("", "x\r\nHeader: x", "contains space"):
                with self.subTest(code=code), self.assertRaises(LicenseError):
                    activate("https://authority.example/activate", code, "tenant-a", "install-a")
            opener.assert_not_called()


if __name__ == "__main__":
    unittest.main()
