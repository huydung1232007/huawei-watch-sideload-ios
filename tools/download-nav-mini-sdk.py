#!/usr/bin/env python3
"""Download the pinned public SDK in four verified byte ranges."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request

url = 'https://repo.huaweicloud.com/openharmony/os/3.2-Release/L2-SDK-MAC-M1-PUBLIC.tar.gz'
target = Path(sys.argv[1])
request = urllib.request.Request(url,headers={'Range':'bytes=0-0'})
with urllib.request.urlopen(request,timeout=30) as response:
    assert response.status == 206,'SDK mirror must support range requests'
    content_range = response.headers['Content-Range']
    assert content_range.startswith('bytes 0-0/'),content_range
    size = int(content_range.split('/')[-1])
    assert len(response.read()) == 1
assert size > 600*1024*1024,'Unexpected SDK archive size'
def download(index):
    begin, end = size*index//4, size*(index+1)//4-1
    part = target.with_name(target.name+'.part'+str(index))
    subprocess.run(['curl','--fail','--silent','--show-error','--location','--retry','1',
        '--connect-timeout','20','--max-time','300','--range',f'{begin}-{end}',url,'-o',str(part)],check=True)
    assert part.stat().st_size == end-begin+1,'Incorrect SDK range size'
    print(f'SDK part {index+1}/4 downloaded',flush=True)
    return part
with ThreadPoolExecutor(max_workers=4) as executor: parts = list(executor.map(download,range(4)))
with target.open('wb') as output:
    for part in parts:
        with part.open('rb') as source: shutil.copyfileobj(source,output)
        part.unlink()
print('SDK ranges assembled; prepare-nav-mini-sdk.py will verify the pinned SHA-256.')
