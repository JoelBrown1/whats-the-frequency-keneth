# What's the Frequency, Kenneth

A guitar pickup resonance frequency analyser for macOS. Measure and visualise the resonant frequency of guitar pickups to better understand their tonal characteristics.

## Requirements

- [Flutter](https://flutter.dev) 3.19.0 or later
- Dart 3.3.0 or later
- macOS with Xcode installed

> **Apple Silicon Macs:** Flutter must be invoked as a native arm64 process. Either install Flutter natively for arm64, or prefix commands with `arch -arm64` as shown below.

## Installation

```sh
git clone https://github.com/your-org/whats-the-frequency-keneth.git
cd whats-the-frequency-keneth
flutter pub get
```

## Running

```sh
arch -arm64 flutter run -d macos
```

## Testing

```sh
arch -arm64 flutter test
```
