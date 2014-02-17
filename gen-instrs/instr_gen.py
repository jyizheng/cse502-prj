#!/bin/env python3

import io
import sys

instr_count = 0
instr_max = 0

fp = open('instr_list.txt')
for line in fp:
    instr_len = len(line.strip())
    if instr_len > instr_max:
        instr_max = instr_len
    instr_count = instr_count + 1

fp.close()

print("Count={0}, Max={1}", instr_count, instr_max, file = sys.stderr)

print("logic[{0}:0][{1}:0][7:0] opcode;".format(instr_count-1, instr_max-1))
print("initial begin")
idx = 0
fp = open('instr_list.txt')
for line in fp:
    print("\tassign opcode[{0}] = \"{1:{width}}\";".format(idx, line.strip(), width=instr_max))
    idx = idx+1

print("end")

