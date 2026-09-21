# Ballistic Synth metrics

Regression: **31 passed, 0 failed** (25.6 s of audio / 45.8 M clock cycles simulated in 1183 s).

| Metric | Original design | Ballistic Synth v2 |
|---|---|---|
| Voices | 4 (parallel datapaths) | 8 (time-multiplexed) |
| Playable notes | 32 (C3-G5) | 128 (full MIDI range) |
| Worst tuning error | 10.93 cents (model) | 0.0007 cents (measured, 10 notes) |
| Sine SFDR @ 880 Hz | 42.1 dB (model) | 95.5 dB (measured) |
| Sine THD @ 880 Hz | -32.6 dB (model) | -100.4 dB (measured) |
| Sine SINAD / ENOB | 21.1 dB / 3.2 bits (model) | 87.4 dB / 14.2 bits (measured) |
| Envelope | none | ADSR, attack/release timing error 1.9 ms |
| Sample rate | 65,531 Hz | 48,000 Hz exact (fractional divider) |

## FPGA implementation (Lattice ECP5-25F, Yosys + nextpnr, seed 1)

| | LUT4 | FF | CCU2C carry | MULT18X18 | Block RAM | Fmax |
|---|---|---|---|---|---|---|
| v1: 4 parallel voices (bug-fixed original) | 2406 | 355 | 114 | 4 | 1 | 66.0 MHz |
| v2: 8 time-multiplexed voices | 3259 | 1214 | 199 | 4 | 4 | 52.2 MHz |

Demo: `demo.asm`, 282 instructions, 17.0 s, peak -6.3 dBFS, 0 clipped samples.
