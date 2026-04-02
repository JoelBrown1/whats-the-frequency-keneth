# Activation Coil Construction

> Engineering analysis derived from the app's DSP pipeline, chain calibration architecture, and hardware specifications documented in `resources/Pickup-Wizard-Sum.md` and `resources/Setup-Guide.md`.

---

## Key Architectural Constraints

The system's architecture fundamentally shapes what the coil needs to do (and not do).

1. **H_chain calibration corrects the coil's response** (`lib/calibration/models/chain_calibration.dart`) — via Tikhonov-regularized deconvolution. Flatness is not critical. Stability and repeatability are.
2. **Driven by Focusrite Scarlett 2i2 headphone output** — optimal load range 32–300 Ω; the coil's DCR is the primary load impedance. No series resistor required.
3. **Sweep spans 20 Hz–20 kHz** — inductive reactance rolls off high-frequency current delivery; chain calibration corrects this, but extreme rolloff reduces SNR.
4. **Must not load the pickup's resonant LC circuit** — pickups are typically 1–10 H. Coil inductance must be orders of magnitude lower to avoid disturbing the resonant circuit under test.

---

## Inductive Rolloff Analysis

**At 200 turns / 1.4 mH / 177 Ω DCR:**
```
XL @ 20 kHz = 2π × 20,000 × 0.0014 ≈ 176 Ω
|Z| @ 20 kHz = √(177² + 176²) ≈ 250 Ω  →  ~71% of DC current
```

**At 100 turns / 0.6 mH / 118 Ω DCR:**
```
XL @ 20 kHz = 2π × 20,000 × 0.0006 ≈ 75 Ω
|Z| @ 20 kHz = √(118² + 75²) ≈ 140 Ω  →  ~84% of DC current
```

Fewer turns = flatter frequency delivery, but less total flux = lower SNR. Chain calibration recovers amplitude but cannot recover SNR lost to a noise-limited signal.

---

## Optimal Specification

| Parameter | Value | Rationale |
|---|---|---|
| **Wire gauge** | 42 AWG | Best balance of compact winding vs. fragility; 44 AWG breaks too easily, 41 AWG adds bulk |
| **Turn count** | 150–175 | More signal than 100 turns; lower inductance than 200 turns — sweet spot for SNR vs. HF rolloff |
| **DCR target** | 130–150 Ω | Sits comfortably in Scarlett headphone's optimal drive range; no series resistor needed |
| **Inductance target** | 0.8–1.0 mH | 3+ orders of magnitude below pickup inductance; no resonant circuit loading |
| **Bobbin diameter** | 12–15 mm | Covers pickup pole pieces (8 mm humbucker row spacing + margin); enables close coupling |
| **Core** | Air (no ferrite) | Ferrite introduces saturation non-linearity that corrupts H_chain at different drive levels |
| **Shielding** | None | A Faraday shield reduces inductive coupling — the opposite of what is needed |
| **Winding** | Single-layer preferred | Reduces self-capacitance and raises SRF; multi-layer acceptable given DSP corrects HF roll |

---

## Self-Resonant Frequency Check

At 1 mH and typical inter-winding capacitance of 10–50 pF:

```
SRF = 1 / (2π√(LC)) ≈ 700 kHz – 2 MHz
```

This is well above the 20 kHz sweep ceiling — the coil operates cleanly within its inductive region across the entire measurement band.

---

## Why Chain Calibration Is the Decisive Factor

The app's 10-stage DSP pipeline (`lib/dsp/dsp_isolate.dart`) applies chain correction at Stage 4 using a 4,096-bin H_chain inverse filter. Any coil non-ideality — HF rolloff, resonance, driver non-linearity — is fully corrected provided:

1. The coil **does not move** between calibration and measurement (enforced by the onboarding flow in `lib/ui/screens/onboarding_screen.dart`)
2. The **drive level is consistent** (the −12 dBFS level check screens this in `lib/ui/screens/setup_screen.dart`)
3. The coil's **SRF remains above 20 kHz** (satisfied by the specification above)

A non-ideal coil is fully acceptable as long as its response is stable and repeatable. The calibration architecture does the heavy lifting.

---

## Recommended Construction

**150 turns of 42 AWG magnet wire on a 12–14 mm air-core former**, wound tightly in 1–2 layers, no shield, no series resistor.

- Target DCR: ~140 Ω
- Target inductance: ~0.9 mH
- Bobbin: 12–14 mm diameter, 5–8 mm winding length

This delivers adequate SNR across the pickup resonance band (1–5 kHz), does not load the pickup's LC circuit, and sits in the Scarlett 2i2 headphone amplifier's optimal drive range — with the chain calibration correcting for all remaining non-idealities.

---

## Reference Specifications (from Pickup-Wizard-Sum.md — Axeteck)

| Parameter | Published Range |
|---|---|
| Wire gauge | 41–44 AWG |
| Wind count | 100–200 turns |
| DCR | 118–177 Ω |
| Inductance | 0.6–1.4 mH |
| Series resistor | None |
