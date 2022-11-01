#!/usr/bin/env python3

# Update LWC package files

import re
from munch import Munch
import toml
from pathlib import Path
from shutil import copyfile
from os.path import getmtime
import argparse
import requests
from xeda import Design

GITHUB_URL = "https://raw.githubusercontent.com/{user}/{repo}/{branch}/{path}"

argparser = argparse.ArgumentParser()
argparser.add_argument('--design_toml',
                       type=argparse.FileType('r'),
                       default=next(Path.cwd().glob("*.toml"), None),
                       help="Design description TOML file")
argparser.add_argument('--lwc_folder', required=False)
argparser.add_argument(
    '--local-lwc-root', default='./src_rtl/LWC', help="Set to . to copy anyways")
argparser.add_argument('--local-tb-root', default='./src_tb/',
                       help="Set to . to copy anyways")
argparser.add_argument('--only-newer',
                       default=True,
                       help="Update files only if the copy in lwc_folder is newer (mtime)")
args = argparser.parse_args()

# src_lwc_folder = Path(args.lwc_folder)

# design_lwc_rtl_root = Path(args.local_lwc_root)
# design_lwc_tb_root = Path(args.local_tb_root)

LWC_RTL = 'hardware/LWC_rtl'
LWC_TB = 'hardware/LWC_tb'


def update_if_newer(lwc_copy: Path, local_copy: Path):
    if lwc_copy.exists():
        if not local_copy.exists() or not args.only_newer or (getmtime(lwc_copy) > getmtime(local_copy)):
            print(f"Updating {local_copy} from {lwc_copy}")
            copyfile(lwc_copy, local_copy)
        else:
            print(f"{local_copy} is up to date")


def update_from_github(file: Path, tb: bool):
    github_path = (LWC_TB if tb else LWC_RTL) + "/" + file.name
    url = GITHUB_URL.format(user='GMUCERG',
                            repo='LWC',
                            branch='master',
                            path=github_path
                            )
    r = requests.get(url)
    if r.status_code == requests.codes.ok:
        d = {}
        for a in re.split(r';\s*', r.headers.get('Content-Type', '')):
            l = re.split(r'\s*=\s*', a)
            if len(l) == 2:
                d[l[0]] = l[1]
        with open(file, 'w') as f:
            f.write(r.content.decode(d.get('charset', 'utf-8')))
        print(f"updated {file}")
    else:
        print(f"{url} [{r.status_code}]")


print(f"using design toml: {args.design_toml}")
design = Design.from_toml(args.design_toml)
for sources, is_tb in [(design.rtl.sources, False), (design.tb.sources, True)]:
    for s in sources:
        local_copy = s.file
        update_from_github(local_copy, is_tb)
