"""Assembler for Ballistic Synth programs.

    py scripts/asm.py programs/demo.asm -o build/program.hex [--list]

Instruction word (24 bits): [23:20] opcode  [19:17] voice  [16:0] operand

  op   mnemonic  operand
  0x0  nop
  0x1  on        [6:0] MIDI note                  note-on (restarts the envelope attack)
  0x2  off                                        note-off (starts the envelope release)
  0x3  wave      [10:8] waveform, [7:0] volume
  0x4  env       [15:12] attack, [11:8] decay, [7:4] sustain level, [3:0] release  (time codes)
  0x5  fx        [3:0] effect
  0x6  wait      [15:0] milliseconds
  0x7  jump      [9:0] address
  0xF  halt

Source syntax (';' starts a comment; case-insensitive):
  name:                                  label
  tempo <bpm>                            lets wait take beats: "wait 1b", "wait 1/2b", "wait 1.5b"
  on    <voices> <note>                  note = MIDI number or name (C4 = 60, F#3, Bb2)
  off   <voices>
  wave  <voices> <sine|square|saw|triangle|noise> <volume 0-255>
  env   <voices> <attack ms> <decay ms> <sustain 0-15> <release ms>   times snap to the nearest supported
  fx    <voices> <none|boost|cut|drive|crush|comp>
  chord <root> <maj|min|dim|aug|sus2|sus4|maj7|min7|dom7> [first voice]   note-ons on consecutive voices
  wait  <ms | beats>
  jump  <label>
  halt
  <voices> = v3 | v0-3 | all
"""
import argparse
import re
import sys
from fractions import Fraction
from pathlib import Path

from synthdefs import EFFECTS, ENV_TIMES_MS, NUM_VOICES, OPCODES, ROM_DEPTH, WAVES

NOTE_OFFSETS = {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}
CHORDS = {
    "maj": [0, 4, 7], "min": [0, 3, 7], "dim": [0, 3, 6], "aug": [0, 4, 8],
    "sus2": [0, 2, 7], "sus4": [0, 5, 7],
    "maj7": [0, 4, 7, 11], "min7": [0, 3, 7, 10], "dom7": [0, 4, 7, 10],
}


class AsmError(Exception):
    pass


def word(op: str, voice: int = 0, operand: int = 0) -> int:
    return (OPCODES[op] << 20) | (voice << 17) | operand


def parse_note(tok: str) -> int:
    if re.fullmatch(r"\d+", tok):
        n = int(tok)
    else:
        m = re.fullmatch(r"([a-g])([#b]?)(-?\d)", tok)
        if not m:
            raise AsmError(f"bad note '{tok}' (use a MIDI number or a name like C4, F#3, Bb2)")
        n = (int(m.group(3)) + 1) * 12 + NOTE_OFFSETS[m.group(1)] + {"": 0, "#": 1, "b": -1}[m.group(2)]
    if not 0 <= n <= 127:
        raise AsmError(f"note '{tok}' is outside MIDI range 0-127")
    return n


def parse_voices(tok: str) -> list[int]:
    if tok == "all":
        return list(range(NUM_VOICES))
    m = re.fullmatch(r"v(\d)(?:-(\d))?", tok)
    if not m:
        raise AsmError(f"bad voice '{tok}' (use v3, v0-3 or all)")
    lo = int(m.group(1))
    hi = int(m.group(2)) if m.group(2) else lo
    if not 0 <= lo <= hi < NUM_VOICES:
        raise AsmError(f"voice range '{tok}' outside v0-v{NUM_VOICES - 1}")
    return list(range(lo, hi + 1))


def parse_int(tok: str, lo: int, hi: int, what: str) -> int:
    try:
        v = int(tok, 0)
    except ValueError:
        raise AsmError(f"{what} must be an integer, got '{tok}'") from None
    if not lo <= v <= hi:
        raise AsmError(f"{what} must be {lo}-{hi}, got {v}")
    return v


def env_code(tok: str) -> int:
    ms = parse_int(tok, 0, 100_000, "envelope time")
    return min(range(len(ENV_TIMES_MS)), key=lambda i: abs(ENV_TIMES_MS[i] - ms))


def lookup(table: dict, tok: str, what: str) -> int:
    if tok not in table:
        raise AsmError(f"unknown {what} '{tok}' (one of: {', '.join(table)})")
    return table[tok]


def expect_args(args: list[str], n: int, usage: str):
    if len(args) != n:
        raise AsmError(f"usage: {usage}")


def assemble(text: str) -> list[int]:
    """Assemble source text into a list of 24-bit instruction words."""
    items = []          # (line_no, word) or (line_no, ("jump", label))
    labels = {}
    tempo = None
    exact_ms = Fraction(0)   # song time requested so far; waits round against this so beats never drift
    emitted_ms = 0

    for line_no, raw in enumerate(text.splitlines(), 1):
        line = raw.split(";", 1)[0].strip().lower()
        if not line:
            continue
        try:
            if line.endswith(":"):
                name = line[:-1].strip()
                if not re.fullmatch(r"[a-z_]\w*", name):
                    raise AsmError(f"bad label '{name}'")
                if name in labels:
                    raise AsmError(f"label '{name}' defined twice")
                labels[name] = len(items)
                continue

            mnem, *args = line.split()
            if mnem == "tempo":
                expect_args(args, 1, "tempo <bpm>")
                tempo = parse_int(args[0], 1, 1000, "tempo")
            elif mnem == "on":
                expect_args(args, 2, "on <voices> <note>")
                note = parse_note(args[1])
                items += [(line_no, word("on", v, note)) for v in parse_voices(args[0])]
            elif mnem == "off":
                expect_args(args, 1, "off <voices>")
                items += [(line_no, word("off", v)) for v in parse_voices(args[0])]
            elif mnem == "wave":
                expect_args(args, 3, "wave <voices> <waveform> <volume>")
                operand = (lookup(WAVES, args[1], "waveform") << 8) | parse_int(args[2], 0, 255, "volume")
                items += [(line_no, word("wave", v, operand)) for v in parse_voices(args[0])]
            elif mnem == "env":
                expect_args(args, 5, "env <voices> <attack ms> <decay ms> <sustain 0-15> <release ms>")
                operand = (env_code(args[1]) << 12) | (env_code(args[2]) << 8) | \
                          (parse_int(args[3], 0, 15, "sustain") << 4) | env_code(args[4])
                items += [(line_no, word("env", v, operand)) for v in parse_voices(args[0])]
            elif mnem == "fx":
                expect_args(args, 2, "fx <voices> <effect>")
                operand = lookup(EFFECTS, args[1], "effect")
                items += [(line_no, word("fx", v, operand)) for v in parse_voices(args[0])]
            elif mnem == "chord":
                if len(args) not in (2, 3):
                    raise AsmError("usage: chord <root> <quality> [first voice]")
                root = parse_note(args[0])
                intervals = lookup(CHORDS, args[1], "chord quality")
                first = parse_voices(args[2])[0] if len(args) == 3 else 0
                if first + len(intervals) > NUM_VOICES:
                    raise AsmError(f"chord needs voices v{first}-v{first + len(intervals) - 1}")
                for i, iv in enumerate(intervals):
                    if root + iv > 127:
                        raise AsmError("chord tone above MIDI 127")
                    items.append((line_no, word("on", first + i, root + iv)))
            elif mnem == "wait":
                expect_args(args, 1, "wait <ms | beats>")
                if args[0].endswith("b"):
                    if tempo is None:
                        raise AsmError("wait in beats needs a tempo first")
                    try:
                        beats = Fraction(args[0][:-1])
                    except (ValueError, ZeroDivisionError):
                        raise AsmError(f"bad beat count '{args[0]}'") from None
                    exact_ms += beats * 60_000 / tempo
                else:
                    exact_ms += parse_int(args[0], 0, 10_000_000, "wait")
                ms = round(exact_ms) - emitted_ms
                emitted_ms += ms
                while ms > 0:
                    chunk = min(ms, 0xFFFF)
                    items.append((line_no, word("wait", 0, chunk)))
                    ms -= chunk
            elif mnem == "jump":
                expect_args(args, 1, "jump <label>")
                items.append((line_no, ("jump", args[0])))
            elif mnem in ("halt", "nop"):
                expect_args(args, 0, mnem)
                items.append((line_no, word(mnem)))
            else:
                raise AsmError(f"unknown instruction '{mnem}'")
        except AsmError as e:
            raise AsmError(f"line {line_no}: {e}  -> {raw.strip()}") from None

    words = []
    for line_no, item in items:
        if isinstance(item, tuple):
            if item[1] not in labels:
                raise AsmError(f"line {line_no}: undefined label '{item[1]}'")
            item = word("jump", 0, labels[item[1]])
        words.append(item)
    if len(words) > ROM_DEPTH:
        raise AsmError(f"program is {len(words)} instructions; ROM holds {ROM_DEPTH}")
    return words


def to_hex(words: list[int]) -> str:
    """ROM image for $readmemh; unused entries are HALT so a program can't run off the end."""
    padded = words + [word("halt")] * (ROM_DEPTH - len(words))
    return "\n".join(f"{w:06x}" for w in padded) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source")
    ap.add_argument("-o", "--output", default="build/program.hex")
    ap.add_argument("--list", action="store_true", help="print an address/word listing")
    args = ap.parse_args()
    try:
        words = assemble(Path(args.source).read_text())
    except AsmError as e:
        sys.exit(f"{args.source}: {e}")
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(to_hex(words), newline="\n")
    if args.list:
        for addr, w in enumerate(words):
            print(f"{addr:4d}  {w:06x}")
    print(f"{args.source}: {len(words)} instructions -> {out}")


if __name__ == "__main__":
    main()
