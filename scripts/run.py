"""Build, simulate and measure Ballistic Synth.

    py scripts/run.py test                  self-checking regression        -> build/test_report.json
    py scripts/run.py demo [song.asm]       render a program to a WAV file   -> build/<name>.wav
    py scripts/run.py synth                 Yosys + nextpnr, Lattice ECP5    -> build/synth_report.json
    py scripts/run.py metrics               all of the above + comparisons   -> build/metrics.md

Needs Icarus Verilog (iverilog/vvp on PATH or in C:\\iverilog\\bin) and numpy.
synth needs yowasp-yosys and yowasp-nextpnr-ecp5 from pip (or pass --yosys / --nextpnr).
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time
import wave
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asm import assemble, to_hex  # noqa: E402
from synthdefs import FS, midi_hz  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
SIM_CLK_HZ = 1_680_000                      # 35 clocks per sample: the engine's minimum, so every run proves it
FULL = 32767
UNITY = (65535 / 65536) * (255 / 256)       # gain of a voice at full envelope and volume 255


# ----------------------------------------------------------------------------- tools

def tool(name: str, override: str | None = None) -> str:
    if override:
        return override
    found = shutil.which(name)
    if found:
        return found
    local = Path(r"C:\iverilog\bin") / f"{name}.exe"
    if local.exists():
        return str(local)
    sys.exit(f"cannot find '{name}'; put it on PATH or pass its path")


@dataclass
class SimResult:
    audio: np.ndarray
    stats: dict
    passed: bool
    seconds: float
    log: str


def simulate(name: str, source: str, clk_hz: int = SIM_CLK_HZ, mix_shift: int = 2,
             tail_ms: int = 0, max_ms: int = 120_000) -> SimResult:
    BUILD.mkdir(exist_ok=True)
    hex_path, samples_path, vvp_path = f"build/{name}.hex", f"build/{name}_samples.txt", f"build/{name}.vvp"
    (ROOT / hex_path).write_text(to_hex(assemble(source)), newline="\n")
    params = dict(CLK_HZ=clk_hz, MIX_SHIFT=mix_shift, TAIL_MS=tail_ms, MAX_MS=max_ms,
                  PROGRAM_FILE=f'"{hex_path}"', SAMPLE_FILE=f'"{samples_path}"')
    rtl = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "rtl").glob("*.sv"))
    cmd = [tool("iverilog"), "-g2012", "-s", "synth_tb", "-o", vvp_path,
           *[f"-Psynth_tb.{k}={v}" for k, v in params.items()], "sim/synth_tb.sv", *rtl]
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"iverilog failed:\n{r.stdout}{r.stderr}")
    t0 = time.perf_counter()
    r = subprocess.run([tool("vvp"), "-n", vvp_path], cwd=ROOT, capture_output=True, text=True)
    seconds = time.perf_counter() - t0
    log = r.stdout + r.stderr
    (BUILD / f"{name}.log").write_text(log)
    m = re.search(r"STATS (.*)", log)
    if not m:
        sys.exit(f"simulation of {name} did not finish:\n{log}")
    stats = {k: float(v) for k, v in (kv.split("=") for kv in m.group(1).split())}
    audio = np.array((ROOT / samples_path).read_text().split(), dtype=np.int32)
    return SimResult(audio, stats, "TB PASS" in log, seconds, log)


def write_wav(path: Path, audio: np.ndarray):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(FS)
        w.writeframes(audio.astype("<i2").tobytes())


# ----------------------------------------------------------------------------- signal analysis

def idx(ms: float) -> int:
    return int(round(ms * FS / 1000))


def window(audio: np.ndarray, t0_ms: float, t1_ms: float) -> np.ndarray:
    return audio[idx(t0_ms):idx(t1_ms)].astype(float)


def zero_crossing_freq(x: np.ndarray) -> float:
    """Frequency from a least-squares fit of interpolated upward zero-crossing times."""
    k = np.nonzero((x[:-1] < 0) & (x[1:] >= 0))[0]
    t = k + (-x[k] / (x[k + 1] - x[k]))
    slope = np.polyfit(np.arange(len(t)), t, 1)[0]
    return FS / slope


def cents(f: float, ref: float) -> float:
    return 1200 * math.log2(f / ref)


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x * x)))


def spectrum_metrics(x: np.ndarray, f0: float, fs: float = FS) -> dict:
    """SFDR / THD / SINAD / ENOB of a single tone (4-term Blackman-Harris window)."""
    x = x - x.mean()
    n = len(x)
    k = np.arange(n)
    w = 0.35875 - 0.48829 * np.cos(2 * np.pi * k / n) + 0.14128 * np.cos(4 * np.pi * k / n) \
        - 0.01168 * np.cos(6 * np.pi * k / n)
    p = np.abs(np.fft.rfft(x * w)) ** 2
    bin_hz = fs / n
    half = 6                                                  # main-lobe half width in bins

    def band(f):
        c = int(round(f / bin_hz))
        return slice(max(c - half, 0), c + half + 1)

    fund = band(f0)
    p_fund = p[fund].sum()
    harmonics = 0.0
    for h in range(2, 11):
        fa = (h * f0) % fs
        fa = fs - fa if fa > fs / 2 else fa                   # alias into [0, fs/2]
        harmonics += p[band(fa)].sum()
    rest = p.copy()
    rest[fund] = 0
    rest[:half + 1] = 0                                       # DC
    sinad = 10 * math.log10(p_fund / rest.sum())
    return {
        "sfdr_db": 10 * math.log10(p[fund].max() / rest.max()),
        "thd_db": 10 * math.log10(harmonics / p_fund),
        "sinad_db": sinad,
        "enob_bits": (sinad - 1.76) / 6.02,
    }


def tone_amplitudes(x: np.ndarray, freqs: list[float]) -> tuple[list[float], float]:
    """Least-squares amplitudes of known tones; also returns residual RMS."""
    t = np.arange(len(x)) / FS
    cols = []
    for f in freqs:
        cols += [np.sin(2 * np.pi * f * t), np.cos(2 * np.pi * f * t)]
    cols.append(np.ones_like(t))
    a = np.stack(cols, axis=1)
    coef, *_ = np.linalg.lstsq(a, x, rcond=None)
    amps = [float(math.hypot(coef[2 * i], coef[2 * i + 1])) for i in range(len(freqs))]
    return amps, rms(x - a @ coef)


# ----------------------------------------------------------------------------- test programs

CheckFn = Callable[[SimResult], tuple[bool, str, dict]]


class TestProgram:
    """Builds an assembly program while tracking song time, and the checks tied to that time."""

    def __init__(self):
        self.lines: list[str] = []
        self.t = 0
        self.checks: list[tuple[str, CheckFn]] = []

    def emit(self, *lines: str):
        self.lines.extend(lines)

    def wait(self, ms: int):
        self.emit(f"wait {ms}")
        self.t += ms

    def check(self, name: str, fn: CheckFn):
        self.checks.append((name, fn))

    def source(self) -> str:
        return "\n".join(self.lines) + "\n"


def within(value: float, expected: float, rel_tol: float) -> bool:
    return abs(value - expected) <= rel_tol * abs(expected)


def check_pitch(t0, t1, hz, max_cents) -> CheckFn:
    def fn(sim):
        f = zero_crossing_freq(window(sim.audio, t0, t1))
        c = cents(f, hz)
        return abs(c) <= max_cents, f"{f:.4f} Hz ({c:+.4f} cents)", {"hz": f, "cents": c}
    return fn


def check_spectrum(t0, t1, hz, min_sfdr) -> CheckFn:
    def fn(sim):
        m = spectrum_metrics(window(sim.audio, t0, t1), hz)
        return (m["sfdr_db"] >= min_sfdr,
                f"SFDR {m['sfdr_db']:.1f} dB, THD {m['thd_db']:.1f} dB, SINAD {m['sinad_db']:.1f} dB, "
                f"ENOB {m['enob_bits']:.2f} bits", m)
    return fn


def check_wave(t0, t1, expected_rms, tol, hz) -> CheckFn:
    def fn(sim):
        x = window(sim.audio, t0, t1)
        r = rms(x)
        ok = within(r, expected_rms, tol)
        detail = f"RMS {r:.0f} (expected {expected_rms:.0f} +/-{tol:.0%})"
        metrics = {"rms": r}
        if hz is not None:
            c = cents(zero_crossing_freq(x), hz)
            ok = ok and abs(c) <= 1.0
            detail += f", pitch {c:+.3f} cents"
            metrics["cents"] = c
        return ok, detail, metrics
    return fn


def check_envelope(t_on, t_off, sustain_amp, attack_half_ms, release_half_ms, tol_ms) -> CheckFn:
    def fn(sim):
        a = sim.audio
        env = sliding_window_view(np.abs(a.astype(float)), 120).max(axis=1)   # peak over ~2 periods
        attack = np.argmax(env[idx(t_on):] >= 0.5 * FULL * UNITY) * 1000 / FS
        sus = float(np.median(env[idx(t_on + 700):idx(t_on + 950)]))
        release = np.argmax(env[idx(t_off):] < 0.5 * sus) * 1000 / FS
        tail_silent = bool(np.all(a[idx(t_off + 200):idx(t_off + 600)] == 0))
        ok = (abs(attack - attack_half_ms) <= tol_ms and within(sus, sustain_amp, 0.01)
              and abs(release - release_half_ms) <= tol_ms and tail_silent)
        return ok, (f"attack to 50% {attack:.1f} ms (exp {attack_half_ms}), sustain {sus:.0f} (exp {sustain_amp:.0f}), "
                    f"release to 50% {release:.1f} ms (exp {release_half_ms}), silent after release: {tail_silent}"), \
            {"attack_err_ms": attack - attack_half_ms, "release_err_ms": release - release_half_ms,
             "sustain_err": sus / sustain_amp - 1}
    return fn


def check_poly(t0, t1, freqs, amp, tol) -> CheckFn:
    def fn(sim):
        x = window(sim.audio, t0, t1)
        amps, resid = tone_amplitudes(x, freqs)
        worst = max(abs(a / amp - 1) for a in amps)
        ok = worst <= tol and resid <= 0.01 * rms(x)
        return ok, f"{len(freqs)} tones, worst amplitude error {worst:.2%}, residual {resid / rms(x):.2%} of RMS", \
            {"worst_amp_err": worst, "residual_ratio": resid / rms(x)}
    return fn


def check_fn(t0, t1, predicate, describe) -> CheckFn:
    def fn(sim):
        x = sim.audio[idx(t0):idx(t1)]
        return bool(predicate(x)), describe(x), {}
    return fn


def new_program() -> TestProgram:
    """Program with every voice silent except v0: full-volume sine, instant envelope, no effect."""
    p = TestProgram()
    p.emit("wave all sine 0", "env all 0 0 15 0", "fx all none", "wave v0 sine 255")
    return p


def suite_tuning() -> TestProgram:
    p = new_program()
    for n in (36, 45, 57, 60, 69, 76, 88, 100, 112):
        t0 = p.t
        p.emit(f"on v0 {n}")
        p.wait(250)
        p.check(f"tuning, MIDI {n} ({midi_hz(n):.1f} Hz)", check_pitch(t0 + 30, t0 + 230, midi_hz(n), 0.1))
    return p


def suite_waveforms() -> TestProgram:
    p = new_program()
    t0 = p.t
    p.emit("on v0 81")
    p.wait(1100)
    p.check("sine spectral purity, 880 Hz", check_spectrum(t0 + 50, t0 + 1050, midi_hz(81), 60))
    for name, expected, tol, pitched in (("square", FULL, 0.01, True), ("saw", FULL / math.sqrt(3), 0.02, True),
                                         ("triangle", FULL / math.sqrt(3), 0.02, True),
                                         ("noise", FULL / math.sqrt(3), 0.05, False)):
        t0 = p.t
        p.emit(f"wave v0 {name} 255", "on v0 69")
        p.wait(250)
        p.check(f"{name} wave", check_wave(t0 + 30, t0 + 230, expected * UNITY, tol, midi_hz(69) if pitched else None))
    return p


def suite_envelope() -> TestProgram:
    # 500 ms attack, instant decay to sustain 8/15, 300 ms release
    p = new_program()
    t_on = p.t
    p.emit("env v0 500 0 8 300", "on v0 69")
    p.wait(1000)
    t_off = p.t
    p.emit("off v0")
    p.wait(600)
    sustain_amp = FULL * (0x8888 / 65536) * (255 / 256)
    p.check("ADSR envelope timing", check_envelope(t_on, t_off, sustain_amp, 250, 80, 5))
    return p


def suite_polyphony() -> TestProgram:
    p = new_program()
    notes = [48, 52, 55, 60, 64, 67, 72, 76]
    t0 = p.t
    p.emit("wave all sine 30", *[f"on v{i} {n}" for i, n in enumerate(notes)])
    p.wait(500)
    p.check("8-voice polyphony", check_poly(t0 + 50, t0 + 450, [midi_hz(n) for n in notes],
                                            FULL * (65535 / 65536) * (30 / 256), 0.01))
    return p


def suite_effects() -> TestProgram:
    p = new_program()

    def fx(effect, volume, name, make_check):
        t0 = p.t
        p.emit(f"wave v0 sine {volume}", f"fx v0 {effect}", "on v0 69")
        p.wait(200)
        p.check(name, make_check(t0 + 20, t0 + 180))

    sine_rms = FULL * UNITY / math.sqrt(2)
    fx("cut", 255, "effect: cut (x0.5)", lambda a, b: check_wave(a, b, sine_rms / 2, 0.01, None))
    fx("boost", 100, "effect: boost (x2)",
       lambda a, b: check_wave(a, b, FULL * (65535 / 65536) * (100 / 256) * 2 / math.sqrt(2), 0.01, None))
    fx("drive", 255, "effect: drive (x4, hard clip)",
       lambda a, b: check_fn(a, b, lambda x: x.max() == 32767 and x.min() == -32768 and rms(x.astype(float)) > 0.85 * FULL,
                             lambda x: f"min {x.min()}, max {x.max()}, RMS {rms(x.astype(float)):.0f}"))
    fx("crush", 255, "effect: 4-bit crush",
       lambda a, b: check_fn(a, b, lambda x: np.all(x % 4096 == 0) and 8 <= len(np.unique(x)) <= 16,
                             lambda x: f"{len(np.unique(x))} distinct levels"))
    fx("comp", 255, "effect: 4:1 compression above half scale",
       lambda a, b: check_fn(a, b, lambda x: within(x.max(), 16384 + (FULL * UNITY - 16384) / 4, 0.005),
                             lambda x: f"peak {x.max()} (expected {16384 + (FULL * UNITY - 16384) / 4:.0f})"))
    return p


def suite_control() -> TestProgram:
    # JUMP must skip a loud square wave; a chain of odd-length WAITs must add up exactly at HALT
    p = new_program()
    p.emit("on v0 69")
    p.wait(100)
    p.emit("jump skip", "wave v0 square 255", "on v0 60", "wait 100", "skip:", "off all")
    t0 = p.t
    p.wait(200)
    p.check("jump skips instructions", check_fn(t0 + 10, t0 + 200, lambda x: np.all(x == 0),
                                                lambda x: f"{np.count_nonzero(x)} non-zero samples"))
    for ms in (1, 7, 33, 250, 509):
        p.wait(ms)
    end_ms = p.t

    def halt_check(sim):
        err = sim.stats["halt_sample"] / FS * 1000 - end_ms
        return abs(err) <= 1.0, f"halted at {end_ms + err:.2f} ms (program time {end_ms} ms)", {"halt_err_ms": err}
    p.check("WAIT timing and HALT", halt_check)
    return p


def suite_realclock() -> TestProgram:
    p = new_program()
    p.emit("on v0 81")
    p.wait(60)
    p.check("tuning with a real 50 MHz clock", check_pitch(10, 55, midi_hz(81), 0.1))
    return p


# name -> (program builder, simulate() overrides). MIX_SHIFT 0 so a single voice reaches full scale.
SUITES = {
    "tuning":    (suite_tuning,    dict(mix_shift=0)),
    "waveforms": (suite_waveforms, dict(mix_shift=0)),
    "envelope":  (suite_envelope,  dict(mix_shift=0)),
    "polyphony": (suite_polyphony, dict(mix_shift=0)),
    "effects":   (suite_effects,   dict(mix_shift=0)),
    "control":   (suite_control,   dict(mix_shift=0)),
    "realclock": (suite_realclock, dict(mix_shift=0, clk_hz=50_000_000)),
}


# ----------------------------------------------------------------------------- commands

def run_parallel(jobs: dict[str, Callable]) -> dict:
    """Run independent simulations concurrently (each is a separate vvp process)."""
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
        futures = {name: pool.submit(job) for name, job in jobs.items()}
        return {name: f.result() for name, f in futures.items()}


def run_tests(extra_jobs: dict[str, Callable] | None = None) -> tuple[dict, dict]:
    """Simulate every suite (plus any extra jobs) in parallel, then evaluate the checks."""
    programs = {name: builder() for name, (builder, _) in SUITES.items()}
    jobs = {name: (lambda n=name: simulate(n, programs[n].source(), **SUITES[n][1])) for name in SUITES}
    t0 = time.perf_counter()
    sims = run_parallel({**jobs, **(extra_jobs or {})})
    report = {"suites": [], "passed": 0, "failed": 0, "wall_seconds": time.perf_counter() - t0}
    for name in SUITES:
        prog, sim = programs[name], sims[name]
        audio_s = len(sim.audio) / FS
        print(f"\n== {name}: {audio_s:.2f} s of audio, {sim.stats['clocks']:.0f} clocks, {sim.seconds:.1f} s wall")
        results = []
        tb_detail = "; ".join(l for l in sim.log.splitlines() if l.startswith("ERROR")) or \
            f"{sim.stats['clocks_per_sample']:.3f} clocks/sample, DAC density error {sim.stats['dac_density_error']:.1e}"
        results.append(("testbench invariants (sample clock, X, overrun, DAC)", sim.passed, tb_detail, {}))
        for check_name, fn in prog.checks:
            try:
                ok, detail, metrics = fn(sim)
            except Exception as e:                      # a crashed check is a failed check
                ok, detail, metrics = False, f"check raised {e!r}", {}
            results.append((check_name, ok, detail, metrics))
        for check_name, ok, detail, _ in results:
            print(f"  {'PASS' if ok else 'FAIL'}  {check_name}: {detail}")
            report["passed" if ok else "failed"] += 1
        report["suites"].append({
            "name": name, "audio_seconds": audio_s, "clocks": sim.stats["clocks"], "wall_seconds": sim.seconds,
            "checks": [{"name": n, "passed": bool(ok), "detail": d, "metrics": m} for n, ok, d, m in results]})
    print(f"\n{report['passed']} passed, {report['failed']} failed ({report['wall_seconds']:.0f} s wall, parallel)")
    (BUILD / "test_report.json").write_text(json.dumps(report, indent=2))
    return report, {k: v for k, v in sims.items() if k not in SUITES}


def cmd_test(args) -> dict:
    return run_tests()[0]


def song_path(args) -> Path:
    return Path(args.song) if args.song else ROOT / "programs" / "demo.asm"


def cmd_demo(args) -> dict:
    src = song_path(args)
    return finish_demo(src, simulate(src.stem, src.read_text()))


def finish_demo(src: Path, sim: SimResult) -> dict:
    wav = BUILD / f"{src.stem}.wav"
    write_wav(wav, sim.audio)
    audio_s = len(sim.audio) / FS
    peak = int(np.abs(sim.audio).max())
    info = {"song": src.name, "instructions": len(assemble(src.read_text())), "audio_seconds": audio_s,
            "peak": peak, "clipped_samples": int(np.count_nonzero(np.abs(sim.audio) >= 32767)),
            "clocks": sim.stats["clocks"], "wall_seconds": sim.seconds, "tb_passed": sim.passed}
    print(f"{src.name}: {info['instructions']} instructions, {audio_s:.2f} s audio, peak {peak} "
          f"({20 * math.log10(max(peak, 1) / 32768):.1f} dBFS), {info['clipped_samples']} clipped samples, "
          f"testbench {'PASS' if sim.passed else 'FAIL'}, {sim.seconds:.1f} s wall -> {wav.relative_to(ROOT)}")
    return info


def run_yosys(yosys: str, files: list[str], top: str, tag: str, cwd: Path, defines: str = "") -> dict:
    stat_path = BUILD / f"{tag}_stat.json"
    json_path = BUILD / f"{tag}.json"
    rel = lambda p: Path(os.path.relpath(p, cwd)).as_posix()     # yosys scripts split on spaces
    script = (f"read_verilog -sv {defines} {' '.join(files)}; synth_ecp5 -top {top} -json {rel(json_path)}; "
              f"tee -q -o {rel(stat_path)} stat -json")
    r = subprocess.run([yosys, "-q", "-p", script], cwd=cwd, capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError(f"yosys failed for {tag}:\n{(r.stdout + r.stderr)[-3000:]}")
    text = stat_path.read_text()
    stat = json.loads(text[text.index("{"):])
    cells = stat["design"].get("num_cells_by_type", {})
    return {"cells": cells, "json": json_path}


def run_nextpnr(nextpnr: str, json_path: Path, tag: str) -> dict:
    report = BUILD / f"{tag}_nextpnr.json"
    rel = lambda p: Path(os.path.relpath(p, ROOT)).as_posix()    # WASM tools only see the working directory
    cmd = [nextpnr, "--25k", "--package", "CABGA256", "--json", rel(json_path), "--freq", "50",
           "--lpf-allow-unconstrained", "--timing-allow-fail", "--seed", "1", "--report", rel(report)]
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    (BUILD / f"{tag}_nextpnr.log").write_text(r.stdout + r.stderr)
    if r.returncode:
        raise RuntimeError(f"nextpnr failed for {tag}:\n{(r.stdout + r.stderr)[-3000:]}")
    data = json.loads(report.read_text())
    fmax = min(v["achieved"] for v in data["fmax"].values())
    util = {k: v for k, v in data["utilization"].items() if v["used"]}
    return {"fmax_mhz": fmax, "meets_50mhz": fmax >= 50.0, "utilization": util}


def summarize_cells(cells: dict) -> dict:
    return {"LUT4": cells.get("LUT4", 0), "FF": cells.get("TRELLIS_FF", 0), "CARRY": cells.get("CCU2C", 0),
            "MULT18X18": cells.get("MULT18X18D", 0), "EBR": cells.get("DP16KD", 0),
            "DPRAM": cells.get("TRELLIS_DPR16X4", 0)}


def cmd_synth(args) -> dict:
    yosys = tool("yowasp-yosys", args.yosys)
    nextpnr = tool("yowasp-nextpnr-ecp5", args.nextpnr)
    BUILD.mkdir(exist_ok=True)
    (BUILD / "program.hex").write_text(to_hex(assemble((ROOT / "programs" / "demo.asm").read_text())), newline="\n")
    rtl = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "rtl").glob("*.sv"))
    report = {}
    y = run_yosys(yosys, rtl, "synth_top", "v2", ROOT)
    report["v2"] = {"cells": summarize_cells(y["cells"]), **run_nextpnr(nextpnr, y["json"], "v2")}
    baseline = ROOT / "legacy" / "v1_bugfix"
    if baseline.exists():
        try:
            files = [p.name for p in sorted(baseline.glob("*.sv")) if p.name not in ("synth_tb.sv", "lab_10.sv")]
            y1 = run_yosys(yosys, files, "control", "v1", baseline)
            report["v1"] = {"cells": summarize_cells(y1["cells"]), **run_nextpnr(nextpnr, y1["json"], "v1")}
        except RuntimeError as e:
            report["v1_error"] = str(e)[-500:]
    for tag in ("v1", "v2"):
        if tag in report:
            c = report[tag]["cells"]
            print(f"{tag}: {c['LUT4']} LUT4, {c['FF']} FF, {c['CARRY']} CCU2C, {c['MULT18X18']} MULT18X18, "
                  f"{c['EBR']} EBR, Fmax {report[tag]['fmax_mhz']:.1f} MHz")
    if "v1_error" in report:
        print("v1 baseline synthesis failed:", report["v1_error"])
    (BUILD / "synth_report.json").write_text(json.dumps(report, indent=2))
    return report


# ---- models of the original design, for before/after comparisons

def original_note_table() -> list[int]:
    text = (ROOT / "legacy" / "original" / "note_rom.sv").read_text()
    return [int(v) for v in re.findall(r"freq = 16'd(\d+);", text)]


def original_sine_lut() -> np.ndarray:
    text = (ROOT / "legacy" / "original" / "sine_LUT.sv").read_text()
    lut = np.zeros(256)                                        # lut[0] was never initialised -> 0 in hardware
    for i, v in re.findall(r"lut\[(\d+)\]\s*=\s*16'h([0-9A-Fa-f]+)", text):
        lut[int(i)] = int(v, 16)
    return lut


def original_models() -> dict:
    fs_actual = 50e6 / 763                                     # sample tick at 50 MHz / CLK_DIV 763
    table = original_note_table()                              # indices 0..31 = MIDI 48..79
    errs = [cents(hz * fs_actual / 65536, midi_hz(48 + i)) for i, hz in enumerate(table)]
    lut = original_sine_lut()
    phase = (np.arange(65536) * 880) % 65536                   # 16-bit accumulator, 880 "Hz"
    tone = lut[phase >> 8]
    spec = spectrum_metrics(tone, 880 * 65536 / 65536, fs=65536)
    return {"tuning_max_abs_cents": max(abs(e) for e in errs), "notes": len(table), "voices": 4,
            "sine_880": spec}


def cmd_metrics(args):
    src = song_path(args)
    test, extra = run_tests({"demo": lambda: simulate(src.stem, src.read_text())})
    demo = finish_demo(src, extra["demo"])
    try:
        synth = cmd_synth(args)
    except (SystemExit, RuntimeError) as e:
        synth = {"error": str(e)[-500:]}
    orig = original_models()

    checks = {c["name"]: c for s in test["suites"] for c in s["checks"]}
    tuning = [abs(c["metrics"]["cents"]) for n, c in checks.items() if n.startswith("tuning")]
    spec = checks["sine spectral purity, 880 Hz"]["metrics"]
    env = checks["ADSR envelope timing"]["metrics"]
    total_audio = sum(s["audio_seconds"] for s in test["suites"]) + demo["audio_seconds"]
    total_clocks = sum(s["clocks"] for s in test["suites"]) + demo["clocks"]
    total_wall = sum(s["wall_seconds"] for s in test["suites"]) + demo["wall_seconds"]

    lines = ["# Ballistic Synth metrics", "",
             f"Regression: **{test['passed']} passed, {test['failed']} failed** "
             f"({total_audio:.1f} s of audio / {total_clocks / 1e6:.1f} M clock cycles simulated in {total_wall:.0f} s).", "",
             "| Metric | Original design | Ballistic Synth v2 |", "|---|---|---|",
             f"| Voices | {orig['voices']} (parallel datapaths) | 8 (time-multiplexed) |",
             f"| Playable notes | {orig['notes']} (C3-G5) | 128 (full MIDI range) |",
             f"| Worst tuning error | {orig['tuning_max_abs_cents']:.2f} cents (model) | "
             f"{max(tuning):.4f} cents (measured, {len(tuning)} notes) |",
             f"| Sine SFDR @ 880 Hz | {orig['sine_880']['sfdr_db']:.1f} dB (model) | {spec['sfdr_db']:.1f} dB (measured) |",
             f"| Sine THD @ 880 Hz | {orig['sine_880']['thd_db']:.1f} dB (model) | {spec['thd_db']:.1f} dB (measured) |",
             f"| Sine SINAD / ENOB | {orig['sine_880']['sinad_db']:.1f} dB / {orig['sine_880']['enob_bits']:.1f} bits (model) | "
             f"{spec['sinad_db']:.1f} dB / {spec['enob_bits']:.1f} bits (measured) |",
             f"| Envelope | none | ADSR, attack/release timing error {max(abs(env['attack_err_ms']), abs(env['release_err_ms'])):.1f} ms |",
             f"| Sample rate | 65,531 Hz | 48,000 Hz exact (fractional divider) |", ""]
    if "v2" in synth:
        v2 = synth["v2"]
        lines += ["## FPGA implementation (Lattice ECP5-25F, Yosys + nextpnr, seed 1)", "",
                  "| | LUT4 | FF | CCU2C carry | MULT18X18 | Block RAM | Fmax |", "|---|---|---|---|---|---|---|"]
        for tag, label in (("v1", "v1: 4 parallel voices (bug-fixed original)"), ("v2", "v2: 8 time-multiplexed voices")):
            if tag in synth:
                c = synth[tag]["cells"]
                lines.append(f"| {label} | {c['LUT4']} | {c['FF']} | {c['CARRY']} | {c['MULT18X18']} | {c['EBR']} | "
                             f"{synth[tag]['fmax_mhz']:.1f} MHz |")
        lines.append("")
    else:
        lines += [f"FPGA implementation: not run ({synth.get('error', 'no tools')})", ""]
    lines += [f"Demo: `{demo['song']}`, {demo['instructions']} instructions, {demo['audio_seconds']:.1f} s, "
              f"peak {20 * math.log10(demo['peak'] / 32768):.1f} dBFS, {demo['clipped_samples']} clipped samples.", ""]
    md = "\n".join(lines)
    (BUILD / "metrics.md").write_text(md)
    (BUILD / "metrics.json").write_text(json.dumps({"test": test, "demo": demo, "synth": synth, "original": orig},
                                                   indent=2, default=str))
    print("\n" + md)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["test", "demo", "synth", "metrics"])
    ap.add_argument("song", nargs="?", help="program for 'demo' (default programs/demo.asm)")
    ap.add_argument("--yosys")
    ap.add_argument("--nextpnr")
    args = ap.parse_args()
    BUILD.mkdir(exist_ok=True)
    result = {"test": cmd_test, "demo": cmd_demo, "synth": cmd_synth, "metrics": cmd_metrics}[args.command](args)
    if args.command == "test" and result["failed"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
