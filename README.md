# PactSwiftMockServer 

[![Build and Test](https://github.com/surpher/PactSwiftMockServer/actions/workflows/build_test.yml/badge.svg?branch=main)](https://github.com/surpher/PactSwiftMockServer/actions/workflows/build_test.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-green.svg?style=flat)](LICENSE.md)
[![codecov](https://codecov.io/gh/surpher/PactSwiftMockServer/branch/main/graph/badge.svg?token=0LYZVF36I9)](https://codecov.io/gh/surpher/PactSwiftMockServer)

A wrapper around [`libpact_ffi.a`](https://github.com/pact-foundation/pact-reference/tree/master/rust/pact_ffi) binary and exposed as XCFramework to be primarily used by [`PactSwift`](https://github.com/surpher/PactSwift).

But nothing is stopping you from creating your own interface using this package.

## What it wraps

`pact_ffi` 0.5.12 (`Pact.version`), from [pact-reference](https://github.com/pact-foundation/pact-reference):

- `Pact`: consumer and provider, specification v1 to v4, metadata, [plugins](https://docs.pact.io/plugins) (`usingPlugin(_:version:)`) and writing the pact file
- `Interaction`: HTTP requests and responses with matchers and generators embedded in the path, query, headers, body and status; text, binary, content type matched (`body(_:matchingContentType:)`), multipart and plugin (`pluginContents(_:contentType:)`) bodies
- `AsynchronousMessage` and `SynchronousMessage`: message interactions with metadata
- V4 interaction fields on every interaction: `pending`, `key`, `comment` and `reference`; provider states with JSON typed params
- `MockServer`: HTTP or HTTPS (with a certificate for `localhost` the server signs itself), CORS pre-flight, keep-alive and plugin transports
- `PactBuilder`: runs the mock server or passes messages to your handler, and writes the pact when they verify. `verify(_:respondingWith:)` matches the response produced for a synchronous message
- `Verifier`: verifies a provider against pacts from directories, files, URLs or a Pact Broker, with consumer version selectors, pending and WIP pacts, provider transports, custom headers, TLS and timeout options, state change set up and tear down, a JSON report and publishing of the results

Plugins run as separate processes, so they are not available on iOS devices.

## Building

The XCFramework is built from `PactSwiftMockServer.xcodeproj` and the prebuilt `Resources/*/libpact_ffi.a` with:

```sh
Support/build_xcframework
```

Rebuild and commit it whenever the Swift sources change, because Swift Package Manager uses the committed binary.
