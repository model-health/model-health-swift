# ModelHealth Swift SDK

Swift/iOS SDK for biomechanical analysis from smartphone videos.

## Requirements

- iOS 15.0+ / macOS 12.0+
- Xcode 15.0+
- Swift 5.9+

## Installation

### Swift Package Manager

In Xcode: **File → Add Package Dependencies**, enter:

```
https://github.com/model-health/model-health-swift
```

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/model-health/model-health-swift", from: "0.1.24")
]
```

## Quick Start

```swift
import ModelHealth

let service = try ModelHealthService(apiKey: "your-api-key")
let sessions = try await service.getSessions()
```

## Documentation

**Full API Documentation**: [docs.modelhealth.io](https://docs.modelhealth.io)

## Other SDKs

- **TypeScript/Web**: [`@modelhealth/modelhealth`](https://www.npmjs.com/package/@modelhealth/modelhealth)
- **All SDKs**: [github.com/model-health/model-health](https://github.com/model-health/model-health)
