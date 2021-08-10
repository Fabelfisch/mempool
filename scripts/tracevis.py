#!/usr/bin/env python3

# Copyright 2021 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# This script parses the traces generated by Snitch and creates a JSON file
# that can be visualized by
# [Trace-Viewer](https://github.com/catapult-project/catapult/tree/master/tracing)
# In Chrome, open `about:tracing` and load the JSON file to view it.
#
# This script is inspired by https://github.com/SalvatoreDiGirolamo/tracevis
# Author: Noah Huetter <huettern@student.ethz.ch>
#         Samuel Riedel <sriedel@iis.ee.ethz.ch>

import re
import os
import sys
import progressbar
import argparse

# line format:
# 101000 82      M         0x00001000 csrr    a0, mhartid     #; comment
# time   cycle   priv_lvl  pc         insn

# regex matches to groups
# 0 -> time
# 1 -> cycle
# 2 -> privilege level
# 3 -> pc (hex with 0x prefix)
# 4 -> instruction
# 5 -> args
LINE_REGEX = r' *(\d+) +(\d+) +([3M1S0U]?) *(0x[0-9a-f]+) ([.\w]+) +(.+)#'

# regex matches a line of instruction retired by the accelerator
# 2 -> privilege level
# 3 -> pc (hex with 0x prefix)
# 4 -> instruction
# 5 -> args
ACC_LINE_REGEX = r' +([3M1S0U]?) *(0x[0-9a-f]+) ([.\w]+) +(.+)#'

re_line = re.compile(LINE_REGEX)
re_acc_line = re.compile(ACC_LINE_REGEX)

buf = []


def flush(buf, hartid):
    global output_file, use_time
    # get function names
    pcs = [x[3] for x in buf]
    a2ls = os.popen(
        f'addr2line -e {elf} -f -a -i {pcs}').read().split('\n')[:-1]

    for i in range(len(buf)-1):
        (time, cyc, priv, pc, instr, args) = buf.pop(0)

        if use_time:
            next_time = int(buf[0][0])
            time = int(time)
        else:
            next_time = int(buf[0][1])
            time = int(cyc)

        # print(f'time "{time}", cyc "{cyc}", priv "{priv}", pc "{pc}"'
        #       f', instr "{instr}", args "{args}"', file=sys.stderr)

        [pc, func, file] = a2ls.pop(0), a2ls.pop(0), a2ls.pop(0)

        # check for more output of a2l
        inlined = ''
        while not a2ls[0].startswith('0x'):
            inlined += '(inlined by) ' + a2ls.pop(0)
        # print(f'pc "{pc}", func "{func}", file "{file}"')

        # assemble values for json
        label = instr
        cat = instr
        start_time = time
        duration = next_time - time
        # print(f'"{label}" time {time} next: {next_time}'
        #       f' duration: {duration}', file=sys.stderr)
        pid = elf+':hartid'+str(hartid)
        funcname = func

        # args
        arg_pc = pc
        arg_instr = instr
        arg_args = args
        arg_cycles = cyc
        arg_coords = file
        arg_inlined = inlined

        output_file.write((
            f'{{"name": "{label}", "cat": "{cat}", "ph": "X", '
            f'"ts": {start_time}, "dur": {duration}, "pid": "{pid}", '
            f'"tid": "{funcname}", "args": {{"pc": "{arg_pc}", '
            f'"instr": "{arg_instr} {arg_args}", "time": "{arg_cycles}", '
            f'"Origin": "{arg_coords}", "inline": "{arg_inlined}"'
            f'}}}},\n'))


def parse_line(line, hartid):
    global last_time, last_cyc
    # print(line)
    match = re_line.match(line)
    if match:
        (time, cyc, priv, pc, instr, args) = tuple(
            [match.group(i+1).strip() for i in range(re_line.groups)])
    # print(match)

    if not match:
        # match accelerator line with same timestamp as before
        match = re_acc_line.match(line)
        if match:
            (priv, pc, instr, args) = tuple(
                [match.group(i+1).strip() for i in range(re_acc_line.groups)])
            # use time,cyc from last line
            time, cyc = last_time, last_cyc
        else:
            return 1

    # print(line)
    buf.append((time, cyc, priv, pc, instr, args))
    last_time, last_cyc = time, cyc

    if len(buf) > 10:
        flush(buf, hartid)
    return 0


parser = argparse.ArgumentParser('tracevis', allow_abbrev=True)
parser.add_argument(
    'elf',
    metavar='<elf>',
    help='The binary executed to generate the traces',
)
parser.add_argument(
    'traces',
    metavar='<trace>',
    nargs='+',
    help='Snitch traces to visualize')
parser.add_argument(
    '-o',
    '--output',
    metavar='<trace>',
    nargs='?',
    default='chrome.json',
    help='Output JSON file')
parser.add_argument(
    '-t',
    '--time',
    action='store_true',
    help='Use the traces time instead of cycles')
parser.add_argument(
    '-s',
    '--start',
    metavar='<trace>',
    nargs='?',
    type=int,
    default=0,
    help='First line to parse')
parser.add_argument(
    '-e',
    '--end',
    metavar='<trace>',
    nargs='?',
    type=int,
    default=-1,
    help='Last line to parse')

args = parser.parse_args()

elf = args.elf
traces = args.traces
output = args.output
use_time = args.time

print('elf', elf, file=sys.stderr)
print('traces', traces, file=sys.stderr)
print('output', output, file=sys.stderr)

with open(output, 'w') as output_file:
    # JSON header
    output_file.write('{"traceEvents": [\n')

    for filename in traces:
        hartid = 0
        parsed_nums = re.findall(r'\d+', filename)
        hartid = int(parsed_nums[-1]) if len(parsed_nums) else hartid+1
        fails = lines = 0
        last_time = last_cyc = 0

        print(
            f'parsing hartid {hartid} with trace {filename}', file=sys.stderr)
        tot_lines = len(open(filename).readlines())
        with open(filename) as f:
            for lino, line in progressbar.progressbar(
                    enumerate(f.readlines()[args.start:args.end]),
                    max_value=tot_lines):
                fails += parse_line(line, hartid)
                lines += 1
            flush(buf, hartid)
            print(f' parsed {lines-fails} of {lines} lines', file=sys.stderr)

    # JSON footer
    output_file.write(r'{}]}''\n')
