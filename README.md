# FluxHaus

A home monitor application for my various smart home things. Talks to [FluxHaus Server](https://github.com/djensenius/FluxHaus-Server/).

Available on the [App Store](https://apps.apple.com/ca/app/fluxhaus/id6478994447).

## Building and Testing

This project includes a `Makefile` to simplify running tests on the correct simulators.

### Run iOS Tests
```bash
make test-ios
```

### Run VisionOS Tests
```bash
make test-visionos
```

### Run All Tests
```bash
make test
```
