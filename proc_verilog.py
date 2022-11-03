from pathlib import Path
from argparse import ArgumentParser
import re

patterns = {
    r'^(\s*)case(z?) \(([^\)]+)\)\s*//\s*synopsys parallel_case\s*$': r'\g<1>unique case\g<2> (\g<3>)\n',
    r'^(\s*)always\@\((\s*posedge[^\)]*)\s*\)': r'\g<1>always_ff@(\g<2>)',
    r'^(\s*)always\@\(([^\)]*)\)': r'\g<1>always@(*)',
    r'^\s*// synopsys translate_off': r'`ifndef SYNTHESIS',
    r'^\s*// synopsys translate_on': r'`endif',
    r'^(\s*)always_ff\@\(\s*(posedge[^\)]*)\s*\)': r'\g<1>always@(\g<2>)',
    # r'^(\s*)case \(([^\)]+)\)\s*//\s*synopsys full_case\s*$': r'\g<1>priority case (\g<2>)\n',
    r'\t': ' '*8,
}
parser = ArgumentParser(description='Process Verilog files')
parser.add_argument('-i', '--input', type=Path, required=True, help='Input file')
parser.add_argument('-o', '--output', type=Path, required=True, help='Output file')

args = parser.parse_args()

with open(args.input) as f, open(args.output, 'w') as g:
    content = f.read()
    for p, s in patterns.items():
        content = re.sub(p, s, content, flags=re.MULTILINE|re.DOTALL)
    g.write(content)
    # print(l, end='')