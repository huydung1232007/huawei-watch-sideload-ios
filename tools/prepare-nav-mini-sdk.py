#!/usr/bin/env python3
"""Extract only JS/toolchains from the verified official OpenHarmony SDK archive."""
import hashlib
import os
from pathlib import Path
import shutil
import sys
import tarfile
import zipfile

archive, destination = Path(sys.argv[1]), Path(sys.argv[2]).resolve()
expected = '42444ed280e6dcead7b5c9aa0e20c8df80cae75b6d9e20bc4eb9ced8a617906d'
with archive.open('rb') as stream:
    digest = hashlib.sha256()
    for block in iter(lambda: stream.read(1024*1024),b''): digest.update(block)
assert digest.hexdigest() == expected, 'Official SDK checksum mismatch'
destination.mkdir(parents=True,exist_ok=True)
selected = []
with tarfile.open(archive,'r:gz') as tar:
    for member in tar:
        name = Path(member.name).name
        if not member.isfile() or not name.endswith('.zip') or not name.startswith(('js-','toolchains-')): continue
        selected.append(name)
        target = destination/name
        with tar.extractfile(member) as source, target.open('wb') as output: shutil.copyfileobj(source,output)
        with zipfile.ZipFile(target) as zipped:
            for item in zipped.infolist():
                final = (destination/item.filename).resolve()
                assert final.is_relative_to(destination),'Unsafe SDK archive entry'
            zipped.extractall(destination)
        target.unlink()
assert selected,'SDK contained no JS/toolchains components'
configs = list(destination.rglob('webpack.lite.config.js'))
assert len(configs) == 1, f'Expected one lite compiler, got {len(configs)}'
sdk = configs[0].parents[3]
restool = sdk/'toolchains/restool'
assert restool.is_file(),f'Missing restool next to JS compiler: {sdk}'
restool.chmod(restool.stat().st_mode | 0o111)
for executable in sdk.rglob('*'):
    if executable.is_file() and executable.suffix in ('','.so','.dylib'):
        executable.chmod(executable.stat().st_mode | 0o111)
print('Verified SDK components:',', '.join(selected))
print('OHOS_SDK='+str(sdk))
with open(os.environ['GITHUB_ENV'],'a') as env: env.write('OHOS_SDK='+str(sdk)+'\n')
