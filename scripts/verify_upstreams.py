"""Check vendored files and Git submodule pins without fetching or running them."""
import argparse
import configparser
import hashlib
import json
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vendored-only', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    config = configparser.ConfigParser()
    config.read(root / '.gitmodules')
    lock = json.loads((root / 'deploy/upstreams.lock.json').read_text())
    for item in lock['upstreams']:
        section = config['submodule "' + item['name'] + '"']
        assert section['path'] == item['path'], 'submodule path mismatch'
        assert section['url'] == 'https://github.com/' + item['repository'] + '.git', 'upstream URL mismatch'
        if not args.vendored_only:
            entry = subprocess.check_output(['git', 'ls-tree', 'HEAD', '--', item['path']], cwd=root, text=True)
            assert entry.split()[:3] == ['160000', 'commit', item['commit']], 'gitlink pin mismatch'
    vendor = root / 'deploy/frappe/upstream'
    manifest = json.loads((root / 'deploy/frappe/vendor.sha256.json').read_text())
    for name, expected in manifest.items():
        assert hashlib.sha256((vendor / name).read_bytes()).hexdigest() == expected, 'vendor checksum mismatch: ' + name
    print('Upstream metadata and vendored checksums verified; no installer executed')


if __name__ == '__main__':
    main()
