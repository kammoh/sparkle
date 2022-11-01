#!/usr/bin/env python3
from dataclasses import dataclass
from typing import List, Literal, Optional, Union
import os
from pathlib import Path
import re
import sys
from nucanvas import DrawStyle, NuCanvas
from nucanvas.cairo_backend import CairoSurface
from nucanvas.svg_backend import SvgSurface
from nucanvas.shapes import PathShape, OvalShape
import hdlparse.vhdl_parser as vhdl
import hdlparse.verilog_parser as vlog
from symbolator import make_symbol
from xeda import Design

from hdlparse.vhdl_parser import VhdlComponent


def reformat_array_params(vo):
    '''Convert array ranges to Verilog style'''
    for p in vo.ports:
        # Replace VHDL downto and to
        data_type = p.data_type.replace(
            ' downto ', ':').replace(' to ', '\u2799')
        # Convert to Verilog style array syntax
        data_type = re.sub(r'([^(]+)\((.*)\)$', r'\1[\2]', data_type)

        # Split any array segment
        pieces = data_type.split('[')
        if len(pieces) > 1:
            # Strip all white space from array portion
            data_type = '['.join([pieces[0], pieces[1].replace(' ', '')])

        p.data_type = data_type


@dataclass
class Options:
    save_lib: bool = False
    title: bool = False
    libname: Optional[str] = None
    no_type: bool = True
    scale: float = 1.
    transparent: bool = True
    out_dir: Path = Path.cwd()
    format: Literal['png', 'svg', 'pdf', 'ps', 'eps'] = 'svg'


def block_diagram(source_files: List[str], options: Options = Options()):
    style = DrawStyle()
    style.line_color = (0, 0, 0)

    vhdl_ex = vhdl.VhdlExtractor()
    vlog_ex = vlog.VerilogExtractor()

    # vhdl_ex.load_array_types(xxx)

    # Find all of the array types
    vhdl_ex.register_array_types_from_sources(source_files)

    # print('## ARRAYS:', vhdl_ex.array_types)

    if options.save_lib:
        print('Saving type defs to "{}".'.format(options.save_lib))
        vhdl_ex.save_array_types(options.save_lib)

        # Separate file by extension
    vhdl_files = [f for f in source_files if vhdl.is_vhdl(f)]
    vlog_files = [f for f in source_files if vlog.is_verilog(f)]

    all_components = {f: [(c, vhdl_ex) for c in vhdl_ex.extract_objects(
        f, VhdlComponent)] for f in vhdl_files}

    vlog_components = {
        f: [(c, vlog_ex) for c in vlog_ex.extract_objects(f)] for f in vlog_files}
    all_components.update(vlog_components)
    # Output is a directory

    options.out_dir.mkdir(exist_ok=True, parents=True)

    nc = NuCanvas(None)

    # Set markers for all shapes
    nc.add_marker('arrow_fwd',
                  PathShape(((0, -4), (2, -1, 2, 1, 0, 4), (8, 0),
                            'z'), fill=(0, 0, 0), weight=0),
                  (3.2, 0), 'auto', None)

    nc.add_marker('arrow_back',
                  PathShape(((0, -4), (-2, -1, -2, 1, 0, 4),
                            (-8, 0), 'z'), fill=(0, 0, 0), weight=0),
                  (-3.2, 0), 'auto', None)

    nc.add_marker('bubble',
                  OvalShape(-3, -3, 3, 3, fill=(255, 255, 255), weight=1),
                  (0, 0), 'auto', None)

    nc.add_marker('clock',
                  PathShape(((0, -7), (0, 7), (7, 0), 'z'),
                            fill=(255, 255, 255), weight=1),
                  (0, 0), 'auto', None)

    # Render every component from every file into an image
    for source, components in all_components.items():
        for comp, extractor in components:
            comp.name = comp.name.strip('_')
            reformat_array_params(comp)
            fname = f'{options.libname + "__" if options.libname else ""}{comp.name}.{options.format}'
            print('Creating symbol for {} "{}"\n\t-> {}'.format(source, comp.name, fname))
            if options.format == 'svg':
                surf = SvgSurface(fname, style, padding=5, scale=options.scale)
            else:
                surf = CairoSurface(fname, style, padding=5,
                                    scale=options.scale)

            nc.set_surface(surf)
            nc.clear_shapes()

            sym = make_symbol(comp, extractor, options.title,
                              options.libname, options.no_type)
            sym.draw(0, 0, nc)

            nc.render(options.transparent)


# design = Design.from_toml("./sparkle_vhdl.toml")

# block_diagram([str(src) for src in design.rtl.sources])
block_diagram(['sparkle.vhdl',  'util_pkg.vhdl'])
