"""Signed license foundation; the issuer private key must never be on a client."""
import argparse
import base64
import datetime as dt
import getpass
import json
import os
import sys
import tempfile
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey

MAX_SIZE = 65536

class LicenseError(ValueError):
    pass

def canonical(payload):
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()

def timestamp(value):
    if not isinstance(value, str) or not value.endswith("Z"):
        raise LicenseError("timestamp must use UTC Z format")
    try:
        return dt.datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as exc:
        raise LicenseError("invalid timestamp") from exc

def validate(payload):
    required = {"schema", "license_id", "tenant_id", "installation_id", "issued_at", "expires_at", "max_users", "features"}
    if not isinstance(payload, dict) or set(payload) != required or type(payload["schema"]) is not int or payload["schema"] != 1:
        raise LicenseError("invalid license schema")
    for field in ("license_id", "tenant_id", "installation_id"):
        if not isinstance(payload[field], str) or not payload[field].strip() or len(payload[field]) > 128:
            raise LicenseError("invalid " + field)
    if type(payload["max_users"]) is not int or not 1 <= payload["max_users"] <= 1000000:
        raise LicenseError("invalid user limit")
    if not isinstance(payload["features"], list) or any(not isinstance(f, str) or not f or len(f) > 100 for f in payload["features"]):
        raise LicenseError("invalid features")
    if timestamp(payload["issued_at"]) >= timestamp(payload["expires_at"]):
        raise LicenseError("invalid time range")

def issue(private_key, payload):
    validate(payload)
    if not isinstance(private_key, Ed25519PrivateKey):
        raise LicenseError("issuer key must be Ed25519")
    return {"payload": payload, "signature": base64.b64encode(private_key.sign(canonical(payload))).decode()}

def verify(public_key, envelope, tenant, installation, active_users=None, now=None):
    if not isinstance(public_key, Ed25519PublicKey):
        raise LicenseError("verification key must be Ed25519")
    if not isinstance(envelope, dict) or set(envelope) != {"payload", "signature"}:
        raise LicenseError("invalid license envelope")
    payload = envelope["payload"]
    validate(payload)
    try:
        public_key.verify(base64.b64decode(envelope["signature"], validate=True), canonical(payload))
    except (ValueError, TypeError, InvalidSignature) as exc:
        raise LicenseError("invalid license signature") from exc
    if payload["tenant_id"] != tenant or payload["installation_id"] != installation:
        raise LicenseError("tenant or installation mismatch")
    now = now or dt.datetime.now(dt.timezone.utc)
    if now < timestamp(payload["issued_at"]) or now >= timestamp(payload["expires_at"]):
        raise LicenseError("license is not currently valid")
    if active_users is not None:
        if type(active_users) is not int or active_users < 0:
            raise LicenseError("invalid active user count")
        if active_users > payload["max_users"]:
            raise LicenseError("active user limit exceeded")
    return payload

def load_public(path):
    return serialization.load_pem_public_key(Path(path).read_bytes())

def load_json(path):
    data = Path(path).read_bytes()
    if len(data) > MAX_SIZE:
        raise LicenseError("file too large")
    return json.loads(data)

def atomic_write(path, content):
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(target.parent), prefix=".license-")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(content)
        os.replace(tmp, target)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

def keygen(private_path, public_path):
    key = Ed25519PrivateKey.generate()
    private = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
    public = key.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
    fd = os.open(private_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(private)
    with open(public_path, "xb") as f:
        f.write(public)

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise LicenseError("activation redirects are not allowed")

def activate(url, code, tenant, installation):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
        raise LicenseError("activation URL must be HTTPS without embedded credentials")
    body = json.dumps({"tenant_id": tenant, "installation_id": installation}).encode()
    request = urllib.request.Request(url, data=body, headers={"Authorization": "Bearer " + code, "Content-Type": "application/json"}, method="POST")
    with urllib.request.build_opener(NoRedirect()).open(request, timeout=10) as response:
        data = response.read(MAX_SIZE + 1)
    if len(data) > MAX_SIZE:
        raise LicenseError("activation response too large")
    return json.loads(data)

def serve(args):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/health":
                status, body = 200, {"status": "alive"}
            elif self.path == "/license":
                try:
                    value = verify(load_public(args.public_key), load_json(args.license), args.tenant, args.installation)
                    status, body = 200, {"status": "valid", "tenant_id": value["tenant_id"], "expires_at": value["expires_at"], "max_users": value["max_users"], "seat_enforcement": "not connected"}
                except (LicenseError, OSError, ValueError, TypeError):
                    status, body = 503, {"status": "invalid_or_missing"}
            else:
                status, body = 404, {"status": "not_found"}
            data = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        def log_message(self, format, *args):
            return
    ThreadingHTTPServer(("0.0.0.0", 9080), Handler).serve_forever()

def main():
    parser = argparse.ArgumentParser(description="OMISHA NETWORK OS licensing")
    sub = parser.add_subparsers(dest="command", required=True)
    key = sub.add_parser("keygen")
    key.add_argument("--private-key", required=True)
    key.add_argument("--public-key", required=True)
    issuer = sub.add_parser("issue")
    issuer.add_argument("--private-key", required=True)
    issuer.add_argument("--payload", required=True)
    issuer.add_argument("--output", required=True)
    for name in ("verify", "activate", "serve"):
        item = sub.add_parser(name)
        item.add_argument("--public-key", required=True)
        item.add_argument("--license", required=True)
        item.add_argument("--tenant", default=os.getenv("OMISHA_TENANT"))
        item.add_argument("--installation", default=os.getenv("OMISHA_INSTALLATION"))
        if name == "verify":
            item.add_argument("--active-users", type=int)
        if name == "activate":
            item.add_argument("--url", required=True)
    args = parser.parse_args()
    try:
        if args.command == "keygen":
            keygen(args.private_key, args.public_key)
        elif args.command == "issue":
            private = serialization.load_pem_private_key(Path(args.private_key).read_bytes(), password=None)
            atomic_write(args.output, json.dumps(issue(private, load_json(args.payload)), indent=2).encode() + b"\n")
        else:
            if not args.tenant or not args.installation:
                raise LicenseError("tenant and installation are required")
            if args.command == "serve":
                serve(args)
            elif args.command == "verify":
                result = verify(load_public(args.public_key), load_json(args.license), args.tenant, args.installation, args.active_users)
                print(json.dumps({"status": "valid", "license_id": result["license_id"], "max_users": result["max_users"]}))
            else:
                code = getpass.getpass("Activation code: ")
                if not code or "\r" in code or "\n" in code:
                    raise LicenseError("invalid activation code")
                envelope = activate(args.url, code, args.tenant, args.installation)
                verify(load_public(args.public_key), envelope, args.tenant, args.installation)
                atomic_write(args.license, json.dumps(envelope, indent=2).encode() + b"\n")
                print("License activated")
    except (LicenseError, OSError, ValueError, TypeError) as exc:
        print("License operation failed: " + str(exc), file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())

