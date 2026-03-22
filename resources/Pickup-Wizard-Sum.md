# Pickup Wizard V1.0 — Summary

**Author:** Helmut Keller (GITEC, 2022)

**What it is:** A free, GUI-driven MATLAB/GNU Octave script for measuring and analyzing the electrical characteristics of electromagnetic guitar pickups using a standard computer sound card.

---

## Core Capabilities

1. **Impedance Measurement** — Measures pickup impedance (20 Hz–20 kHz) using a DIY passive measurement adapter and a sound card's stereo inputs/output. The pickup can remain mounted on the guitar if reduced accuracy is acceptable.

2. **Equivalent Circuit Model Fitting** — Automatically estimates pickup parameters (DC resistance R₀, capacitance C₀, inductance L₀, and sub-coil loss parameters) by fitting a parametric model to the measured impedance using `fminsearch` optimization.

3. **Frequency Response Calculation** — Calculates and plots the pickup's frequency response under user-defined load scenarios (resistive + capacitive load representing amp input and cable capacitance).

---

## How It Works

- **Test signal:** Logarithmic sine sweep (16 Hz–22 kHz, 3s duration, 48 kHz sample rate)
- **Three calibration steps** before measurement:
  - Transfer function calibration (switch position A)
  - Crosstalk calibration (switch position B)
  - Impedance calibration (switch position C, open port)
- **Signal averaging** over multiple sweeps reduces hum and noise
- **Guitar-mounted measurement** accounts for volume pot (Rv), tone pot (Rt), and tone cap (Ct) as additional loads

## Pickup Physics Model

The pickup is modeled as:
- A series connection of inductance (L₀) and resistance (R₀)
- Parallel capacitance (C₀) for inter-winding coupling
- Optional sub-coils (up to 3) with parallel resistances to model **magnetic core losses** (frequency-dependent inductance behavior)

---

## Hardware Required

- A **DIY passive measurement adapter** built into an aluminum enclosure (Hammond 1550 BBK) containing:
  - 4× quarter-inch TS jacks
  - 1× 3-position rotary switch (Lorlin DS4)
  - 1× 1 MΩ, 0.1%-tolerance metal film resistor (Rs)
- A **sound card** supporting 48 kHz / 24-bit, with ≥1 MΩ input impedance

### Assumed Interface: Focusrite Scarlett 2i2 (4th Gen)

The Focusrite Scarlett 2i2 is the assumed audio interface for this setup. It meets all Pickup Wizard requirements with a clean, passive Hi-Z input design (no active impedance circuit).

| Spec | Value |
|------|-------|
| Inputs | 2 simultaneous (combo XLR/TS) |
| Bit depth | 24-bit |
| Sample rate | Up to 192 kHz (48 kHz used) |
| Instrument input impedance | ~1 MΩ Hi-Z (passive) |

**Channel assignment:**
- Input 1 (left) → U₁ reference channel
- Input 2 (right) → U₂ measurement channel
- Output (left/mono) → measurement adapter generator port (G)

**Required settings before use:**
- Air mode: **off** on both channels
- OS-level audio enhancements: **disabled**
- Direct monitoring: **disabled**

### Exciter Coil (Resonance Frequency Testing)

An exciter coil is used to magnetically drive a pickup to measure its resonance frequency response — a separate technique from the impedance measurement method used by the Pickup Wizard.

**Axeteck.com specifications** (via guitarnuts2.proboards.com):

| Parameter | Value |
|-----------|-------|
| Wire gauge | 41–44 AWG |
| Wind count | 100–200 turns |
| Series resistor | None |
| DCR | 118–177 Ω |
| Inductance | 0.6–1.4 mH |

**Notes:**
- Fine wire (41–44 AWG) keeps the coil compact enough to position close to or over the pickup without physical interference
- Low inductance (0.6–1.4 mH) relative to a pickup (typically 2–10 H) prevents the exciter from significantly loading the pickup's resonant circuit
- No series resistor — driver amp output impedance alone limits current; verify the amp can handle the low DCR load without distortion
- DCR range reflects the trade-off between wire gauge and wind count across the given ranges

**Important:** The exciter coil method is a separate technique from the Pickup Wizard's impedance measurement — different software (e.g. REW) is required.

**Recommended signal chain (with Scarlett 2i2):**

```
Scarlett 2i2 Line Out → Buffer/Power Amp → Exciter Coil → [over pickup] → Pickup Output → Scarlett 2i2 Input
```

- The Scarlett 2i2 **line output cannot directly drive the exciter coil** (118–177 Ω load vs. ≥10 kΩ expected) — a buffer or small power amp stage is required
- The Scarlett 2i2 **headphone output** (designed for 32–300 Ω loads) is a possible direct alternative, but output level must be carefully controlled to avoid overdriving the pickup
- Use the Scarlett 2i2 input to capture the pickup's response for analysis in measurement software

---

## Software Workflow (6 Menus)

| Menu | Function |
|------|----------|
| **Settings** | Audio I/O device selection, signal level, sweep count, hum suppression |
| **Calibration** | Transfer function, crosstalk, impedance calibration |
| **Tools** | FFT Analyzer, Calculate R₀ & Rv from guitar DC measurements |
| **Measurement** | Set guitar load params, measure impedance, approximate model |
| **Display** | View impedance, approximation, frequency response plots, data table |
| **Help** | About dialog |

---

## License

- Free for private use; commercial use requires written permission from the author
- Distributed via the GITEC homepage only
- Source code reuse permitted with attribution

---

*Source: Pickup-Wizard-V1.0-.pdf — GITEC Knowledge Base*
