#!/usr/bin/env python3

# Update LWC package files

from genericpath import getmtime
from munch import Munch
import toml
from pathlib import Path
from shutil import copyfile
from os.path import getmtime
import argparse

argparser = argparse.ArgumentParser()
argparser.add_argument('design_toml',
                       type=argparse.FileType('r'),
                       help="Design description TOML file")
argparser.add_argument('lwc_folder')
argparser.add_argument(
    '--local-lwc-root', default='./src_rtl/LWC', help="Set to . to copy anyways")
argparser.add_argument('--local-tb-root', default='./src_tb/',
                       help="Set to . to copy anyways")
argparser.add_argument('--only-newer',
                       default=True,
                       help="Update files only if the copy in lwc_folder is newer (mtime)")
args = argparser.parse_args()

src_lwc_folder = Path(args.lwc_folder)

design_lwc_rtl_root = Path(args.local_lwc_root)
design_lwc_tb_root = Path(args.local_tb_root)

LWC_RTL = 'hardware/LWC_rtl'
LWC_TB = 'hardware/LWC_tb'


def update_if_newer(lwc_copy: Path, local_copy: Path):
    if lwc_copy.exists():
        if not local_copy.exists() or not args.only_newer or (getmtime(lwc_copy) > getmtime(local_copy)):
            print(f"Updating {local_copy} from {lwc_copy}")
            copyfile(lwc_copy, local_copy)
        else:
            print(f"{local_copy} is up to date")


design = Munch.fromDict(toml.load(args.design_toml))
for s in design.rtl.sources:
    local_copy = Path(s)
    if local_copy.is_relative_to(design_lwc_rtl_root):
        lwc_copy = src_lwc_folder / LWC_RTL / local_copy.name
        update_if_newer(lwc_copy, local_copy)
    else:
        print(
            f"Skipping {local_copy} as its path is not relative to {design_lwc_rtl_root}"
        )
for s in design.tb.sources:
    local_copy = Path(s)
    if local_copy.is_relative_to(design_lwc_tb_root):
        lwc_copy = src_lwc_folder / LWC_TB / local_copy.name
        update_if_newer(lwc_copy, local_copy)
    else:
        print(
            f"Skipping {local_copy} as its path is not relative to {design_lwc_tb_root}"
        )
