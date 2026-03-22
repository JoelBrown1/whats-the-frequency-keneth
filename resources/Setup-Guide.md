# Setup Guide — What's the Frequency, Kenneth

A step-by-step guide to measuring your guitar pickup's resonance frequency.
No experience needed — just follow the steps in order.

---

## What You'll Need

Before you start, make sure you have all of this:

| Item | What It Is |
|---|---|
| **Focusrite Scarlett 2i2** | A small box that connects your guitar gear to your computer |
| **Exciter coil** | A small homemade coil that creates a magnetic field to "tickle" the pickup |
| **10 kΩ resistor** | A tiny component used during calibration (looks like a small cylinder with coloured stripes) |
| **3 cables** | Standard guitar/audio cables (TS/quarter-inch) |
| **A computer** | Mac or Windows PC running the app |
| **Tape or a marker** | To mark an important knob position — seriously, don't skip this |

---

## Part 1 — Connect Everything

Think of the Scarlett 2i2 as the brain of the setup. Everything plugs into it.

### Step 1 — Plug in the Scarlett 2i2

Connect the Scarlett 2i2 to your computer with the USB cable. Wait for the computer to recognise it (usually takes about 10 seconds).

### Step 2 — Connect the exciter coil

Plug the exciter coil into the **headphone socket** on the front of the Scarlett 2i2.

> The headphone socket is the one with the headphone symbol (🎧). You only need to use the **left channel** — so if your coil has a stereo plug, that's fine, only the left side will be used.

### Step 3 — Connect the pickup

Run a cable from your pickup (or guitar output) into **Input 1** on the front of the Scarlett 2i2.

Your signal chain should now look like this:

```
Scarlett 2i2 headphone out → Exciter coil → [held over pickup] → Pickup → Scarlett 2i2 Input 1
```

---

## Part 2 — Configure the Scarlett 2i2

These settings make sure the Scarlett 2i2 isn't doing anything sneaky to your signal that would mess up the measurement.

### Step 4 — Turn off Air mode

On the Scarlett 2i2 (or in the Focusrite Control app on your computer), find the **Air** button for both inputs and make sure it is **OFF**.

> Air mode makes guitars sound a bit brighter — great for recording music, but bad for measurements because it changes the signal.

### Step 5 — Turn off Direct Monitoring

In the Focusrite Control app, make sure **Direct Monitoring is OFF**.

> Direct monitoring lets you hear yourself in real time, but it can interfere with how the app records.

### Step 6 — Turn off computer sound effects

Your computer might be secretly adding effects to audio without you knowing. Turn these off:

**On Mac:**
- Go to **System Settings → Sound**
- Make sure no "Sound Effects" are routed through the Scarlett 2i2

**On Windows:**
- Right-click the speaker icon in the taskbar → **Sound Settings**
- Find the Scarlett 2i2 in your devices, click **Properties**
- Go to the **Enhancements** tab and tick **Disable all enhancements**

---

## Part 3 — Set the Volume Level

This is one of the most important steps. The headphone volume knob controls how strongly the exciter coil drives your pickup. Too loud = distorted results. Too quiet = noisy results.

### Step 7 — Open the app and run the Level Check

1. Open the **What's the Frequency** app
2. Go to **Setup → Level Check**
3. The app will play a tone through the headphone output and show you a number in dBFS (don't worry about what that means — just watch the number)

### Step 8 — Adjust the headphone knob

Slowly turn the **headphone volume knob** (the big knob on the front of the Scarlett 2i2) until the number in the app reads around **-12 dBFS**.

- If the number is above -6, turn the knob down
- If the number is below -20, turn the knob up
- Aim for somewhere around -12

### Step 9 — Mark the knob position ⚠️

This is really important. Once you've found the right level:

**Put a small piece of tape or a marker dot at the knob's current position.**

> If the knob moves even slightly between now and when you measure your pickup, your results will be wrong and you'll need to start the calibration over. Marking it prevents accidents.

---

## Part 4 — Calibrate the Setup

Calibration teaches the app what the signal chain sounds like on its own — so it can subtract that from the pickup measurement and give you a clean result.

Think of it like zeroing a kitchen scale before you weigh something.

### Step 10 — Plug in the calibration resistor

Take the **10 kΩ resistor** and connect it where the pickup normally goes — this gives the exciter coil something to drive without a real pickup in the way.

> If you're not sure how to connect it, just touch the resistor's two legs to the two terminals of your pickup cable connector (the tip and sleeve of the TS plug). You can hold it in place with a rubber band or tape.

### Step 11 — Position the exciter coil

Hold or mount the exciter coil in the same position it will be in during a real measurement — same height above the resistor, same orientation.

> Consistency matters here. If the coil moves between calibration and measurement, the calibration won't be accurate.

### Step 12 — Run the chain calibration

1. In the app go to **Setup → Calibrate**
2. Check that the on-screen checklist matches your setup, then tap **Start**
3. The app will play a sweep (you might hear a faint whine from the coil — that's normal)
4. Wait about 5 seconds for it to finish
5. The app will show **Calibration complete ✓**

> The app stores the result automatically. You won't need to redo this unless you move the knob, change a cable, or reposition the coil.

---

## Part 5 — Measure a Pickup

You're ready to measure. 🎉

### Step 13 — Remove the calibration resistor

Unplug the resistor and connect your pickup (or guitar) to Input 1 instead.

### Step 14 — Position the exciter coil over the pickup

Hold the exciter coil directly over the pickup, as close as possible without touching. Keep it parallel to the pickup's surface.

> The closer the coil, the stronger the signal. Experiment to find a consistent position and try to use the same position every time for reliable comparisons.

### Step 15 — Run the measurement

1. In the app go to **Measure → Start**
2. Check the on-screen setup checklist, then tap **Yes, start measuring**
3. The app runs a sweep (about 3–4 seconds)
4. Results appear automatically — you'll see a curve on a graph and the resonance frequency displayed in Hz

### Step 16 — Save your result

1. Give the pickup a name (e.g. "Strat neck 2024")
2. Tap **Save**
3. Your result is stored and you can compare it to future measurements in the **History** screen

---

## Things That Can Go Wrong

| Problem | What to do |
|---|---|
| App says "Dropout detected" | There was a glitch in the audio. Tap Retry — it usually fixes itself |
| The graph looks really noisy | Check the headphone knob hasn't moved. Redo the level check and calibration |
| App says "Device not found" | Unplug and replug the Scarlett 2i2, wait 10 seconds, then reopen the app |
| Calibration warning appears | Your calibration is more than 30 minutes old. Re-run Step 12 before measuring |
| The knob moved | Re-run Steps 7–12 from the level check onwards |

---

## Quick Reference Checklist

Before every measurement session, run through this:

- [ ] Scarlett 2i2 connected via USB
- [ ] Exciter coil plugged into headphone out
- [ ] Pickup connected to Input 1
- [ ] Air mode **OFF** on both channels
- [ ] Direct monitoring **OFF**
- [ ] OS audio enhancements **OFF**
- [ ] Headphone knob at marked position
- [ ] Calibration is recent (less than 30 minutes old)
- [ ] Exciter coil positioned over pickup

---

*For technical details about how the app works, see [Architecture.md](../Architecture.md)*
