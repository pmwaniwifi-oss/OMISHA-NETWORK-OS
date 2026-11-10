#!/usr/bin/env python3
"""Lossless archives of closed log segments. Never deletes source records.

The caller must rotate/close the source before archiving. This is a storage
primitive, not a certified IPDR collector, retention engine, or legal approval.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import tempfile
import uuid
import zstandard as zstd

CHUNK = 1024 * 1024
SAFE_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", re.ASCII)


class ArchiveError(ValueError):
    pass


def identity(value):
    if not isinstance(value, str) or not SAFE_ID.fullmatch(value):
        raise ArchiveError("invalid tenant/source/log-type identifier")
    return value


def fingerprint(info):
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def hash_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(CHUNK), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sync_dir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def verify_archive(directory, tenant=None):
    """Re-read every compressed byte and decompress to prove exact recovery.

    Hashes detect corruption, not a hostile rewrite of both data and manifest.
    Store manifests separately with signed/immutable custody before production.
    """
    directory = Path(directory)
    with (directory / "manifest.json").open("rb") as stream:
        raw = stream.read(65537)
    if len(raw) > 65536:
        raise ArchiveError("manifest too large")
    manifest = json.loads(raw)
    if not isinstance(manifest, dict) or manifest.get("schema") != 1 or manifest.get("codec") != "zstd":
        raise ArchiveError("unsupported manifest")
    identity(manifest.get("tenant_id"))
    if tenant is not None and manifest["tenant_id"] != identity(tenant):
        raise ArchiveError("tenant mismatch")
    for field in ("raw_bytes", "compressed_bytes"):
        if type(manifest.get(field)) is not int or manifest[field] < 0:
            raise ArchiveError("invalid manifest length")
    for field in ("raw_sha256", "compressed_sha256"):
        if not isinstance(manifest.get(field), str) or not re.fullmatch(r"[0-9a-f]{64}", manifest[field]):
            raise ArchiveError("invalid manifest checksum")
    compressed = directory / "records.zst"
    if compressed.stat().st_size != manifest["compressed_bytes"] or hash_file(compressed) != manifest["compressed_sha256"]:
        raise ArchiveError("compressed checksum/length mismatch")
    digest = hashlib.sha256()
    count = 0
    with compressed.open("rb") as source:
        with zstd.ZstdDecompressor(max_window_size=64 * 1024 * 1024).stream_reader(source) as reader:
            for chunk in iter(lambda: reader.read(CHUNK), b""):
                count += len(chunk)
                if count > manifest["raw_bytes"]:
                    raise ArchiveError("decompressed length exceeded manifest")
                digest.update(chunk)
    if count != manifest["raw_bytes"] or digest.hexdigest() != manifest["raw_sha256"]:
        raise ArchiveError("restored checksum/length mismatch")
    return manifest


def archive_segment(source_path, output_root, tenant, source_id, log_type, *, sealed=False, level=3):
    if not sealed:
        raise ArchiveError("only closed/rotated segments may be archived; confirm sealed=True")
    if type(level) is not int or not 1 <= level <= 9:
        raise ArchiveError("compression level must be between 1 and 9")
    tenant, source_id, log_type = map(identity, (tenant, source_id, log_type))
    source_path = Path(source_path)
    # Linux-only pilot: refuse symlinks and non-regular input files. Do not source scripts.
    fd = os.open(source_path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    temporary = None
    try:
        with os.fdopen(fd, "rb") as source:
            before = os.fstat(source.fileno())
            if not stat.S_ISREG(before.st_mode):
                raise ArchiveError("source must be a regular file")
            day = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d")
            parent = Path(output_root) / tenant / log_type / day
            parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            temporary = Path(tempfile.mkdtemp(prefix=".partial-", dir=parent))
            compressed = temporary / "records.zst"
            digest = hashlib.sha256()
            count = 0
            with compressed.open("xb") as target:
                with zstd.ZstdCompressor(level=level, write_checksum=True).stream_writer(target, closefd=False) as writer:
                    for chunk in iter(lambda: source.read(CHUNK), b""):
                        digest.update(chunk)
                        count += len(chunk)
                        writer.write(chunk)
                target.flush()
                os.fsync(target.fileno())
            if fingerprint(before) != fingerprint(os.fstat(source.fileno())) or fingerprint(before) != fingerprint(source_path.stat()):
                raise ArchiveError("source changed during archiving; rotate and retry")
            if count != before.st_size:
                raise ArchiveError("source length changed")
        compressed_size = compressed.stat().st_size
        manifest = {
            "schema": 1, "codec": "zstd", "codec_library": zstd.__version__, "level": level,
            "tenant_id": tenant, "source_id": source_id, "log_type": log_type,
            "created_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            "raw_bytes": count, "compressed_bytes": compressed_size,
            "raw_sha256": digest.hexdigest(), "compressed_sha256": hash_file(compressed),
            "retention_policy": "unassigned_no_auto_delete", "source_deleted": False,
            "compression_ratio": round(count / compressed_size, 3) if compressed_size else None,
        }
        with (temporary / "manifest.json").open("x") as stream:
            json.dump(manifest, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        verify_archive(temporary, tenant)
        sync_dir(temporary)
        final = parent / str(uuid.uuid4())
        temporary.rename(final)
        temporary = None
        sync_dir(parent)
        return final, manifest
    finally:
        if temporary is not None:
            shutil.rmtree(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    pack = sub.add_parser("pack")
    pack.add_argument("source", type=Path)
    pack.add_argument("--output", type=Path, required=True)
    pack.add_argument("--tenant", required=True)
    pack.add_argument("--source-id", required=True)
    pack.add_argument("--log-type", required=True)
    pack.add_argument("--sealed", action="store_true", help="Source has been closed by its writer")
    pack.add_argument("--level", type=int, default=3)
    check = sub.add_parser("verify")
    check.add_argument("directory", type=Path)
    check.add_argument("--tenant", required=True)
    args = parser.parse_args()
    try:
        if args.command == "pack":
            path, manifest = archive_segment(args.source, args.output, args.tenant, args.source_id,
                                             args.log_type, sealed=args.sealed, level=args.level)
            print(json.dumps({"archive": str(path), **manifest}, indent=2))
        else:
            print(json.dumps({"verified": True, **verify_archive(args.directory, args.tenant)}, indent=2))
    except (OSError, ValueError, zstd.ZstdError) as exc:
        parser.exit(1, f"Archive operation failed: {exc}\n")


if __name__ == "__main__":
    main()
