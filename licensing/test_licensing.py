import base64
import copy
import datetime as dt
import unittest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from omisha_license import LicenseError, issue, verify

class SignedLicenseTests(unittest.TestCase):
    def setUp(self):
        self.key = Ed25519PrivateKey.generate()
        self.payload = {"schema": 1, "license_id": "lic-1", "tenant_id": "client-a",
                        "installation_id": "install-a", "issued_at": "2026-01-01T00:00:00Z",
                        "expires_at": "2027-01-01T00:00:00Z", "max_users": 2, "features": ["crm"]}
        self.signed = issue(self.key, self.payload)
        self.now = dt.datetime(2026, 11, 10, tzinfo=dt.timezone.utc)

    def check(self, envelope=None, tenant="client-a", installation="install-a", users=2, now=None):
        return verify(self.key.public_key(), envelope or self.signed, tenant, installation, users, now or self.now)

    def test_valid_license_and_exact_seat_limit(self):
        self.assertEqual(self.check()["max_users"], 2)

    def test_tampered_payload(self):
        altered = copy.deepcopy(self.signed)
        altered["payload"]["max_users"] = 100
        with self.assertRaises(LicenseError):
            self.check(altered)

    def test_wrong_tenant_or_installation(self):
        for kwargs in ({"tenant": "client-b"}, {"installation": "install-b"}):
            with self.subTest(kwargs=kwargs), self.assertRaises(LicenseError):
                self.check(**kwargs)

    def test_expiry_and_not_yet_valid(self):
        for when in (dt.datetime(2025, 1, 1, tzinfo=dt.timezone.utc), dt.datetime(2027, 1, 1, tzinfo=dt.timezone.utc)):
            with self.subTest(when=when), self.assertRaises(LicenseError):
                self.check(now=when)

    def test_user_limit(self):
        with self.assertRaises(LicenseError):
            self.check(users=3)

    def test_bad_signature_and_key(self):
        altered = copy.deepcopy(self.signed)
        altered["signature"] = base64.b64encode(b"invalid").decode()
        with self.assertRaises(LicenseError):
            self.check(altered)
        with self.assertRaises(LicenseError):
            verify(Ed25519PrivateKey.generate().public_key(), self.signed, "client-a", "install-a", 2, self.now)

    def test_invalid_schema(self):
        altered = copy.deepcopy(self.payload)
        altered["schema"] = True
        with self.assertRaises(LicenseError):
            issue(self.key, altered)

if __name__ == "__main__":
    unittest.main()

