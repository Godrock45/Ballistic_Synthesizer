"""Constants shared by the table generator, assembler and simulation scripts.

The RTL side of these lives in rtl/ (the generated *_table.sv files and the localparams in
sequencer.sv / voice_engine.sv). Change both together.
"""

FS = 48_000            # audio sample rate (Hz)
NUM_VOICES = 8
PHASE_BITS = 32        # oscillator phase accumulator width
ENV_BITS = 24          # envelope level width
ROM_DEPTH = 1024       # program ROM entries (10-bit PC)

# Envelope times selectable by the 4-bit attack/decay/release codes, in ms.
# Each is the time for a full-scale sweep (0 -> max for attack, max -> 0 for release).
ENV_TIMES_MS = [0, 2, 5, 10, 20, 50, 100, 200, 300, 500, 750, 1000, 1500, 2000, 3000, 5000]

OPCODES = {"nop": 0x0, "on": 0x1, "off": 0x2, "wave": 0x3, "env": 0x4,
           "fx": 0x5, "wait": 0x6, "jump": 0x7, "halt": 0xF}
WAVES = {"sine": 0, "square": 1, "saw": 2, "triangle": 3, "noise": 4}
EFFECTS = {"none": 0, "boost": 1, "cut": 2, "drive": 3, "crush": 4, "comp": 5}

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def midi_hz(note: int) -> float:
    return 440.0 * 2 ** ((note - 69) / 12)


def midi_name(note: int) -> str:
    return f"{NOTE_NAMES[note % 12]}{note // 12 - 1}"


def tuning_word(hz: float) -> int:
    return round(hz * 2**PHASE_BITS / FS)
