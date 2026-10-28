//
//  Created by Marko Justinek on 18/8/21.
//  Copyright © 2021 Marko Justinek. All rights reserved.
//
//  Permission to use, copy, modify, and/or distribute this software for any
//  purpose with or without fee is hereby granted, provided that the above
//  copyright notice and this permission notice appear in all copies.
//
//  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
//  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
//  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
//  SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
//  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
//  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR
//  IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
//

import Foundation

#if SWIFT_PACKAGE
import PactMockServer
#endif

public protocol ProviderVerifying {

	/// Triggers the provider verification task
	func verifyProvider(options: ProviderVerificationOptions) -> Result<Bool, ProviderVerificationError>

}

/// Used to verify the provider side of a pact contract
public final class Verifier: ProviderVerifying {

	public init() {
		// Intentionally left blank
	}

	/// Triggers the provider verification task by replaying the requests from provided contracts
	///
	/// The verification output is printed to standard output.
	///
	public func verifyProvider(options: ProviderVerificationOptions) -> Result<Bool, ProviderVerificationError> {
		guard let handle = pactffi_verifier_new_for_application("pact_swift".cString(using: .utf8), nil) else {
			return .failure(.nullPointer)
		}
		defer { pactffi_verifier_shutdown(handle) }

		let provider = options.provider
		pactffi_verifier_set_provider_info(
			handle,
			provider.name?.cString(using: .utf8),
			provider.url?.scheme?.cString(using: .utf8),
			provider.url?.host?.cString(using: .utf8),
			UInt16(provider.port),
			provider.url.flatMap { $0.path.isEmpty ? nil : $0.path }?.cString(using: .utf8)
		)

		for source in options.sources {
			guard add(source, to: handle) else {
				return .failure(.invalidArguments)
			}
		}

		if let filter = options.filter {
			pactffi_verifier_set_filter_info(handle, filter.description?.cString(using: .utf8), filter.state?.cString(using: .utf8), filter.noState ? 1 : 0)
		}

		if options.consumers.isEmpty == false {
			withCStrings(options.consumers) { pactffi_verifier_set_consumer_filters(handle, $0, $1) }
		}

		if let stateChangeURL = options.stateChangeURL {
			// State change data is sent in the request body, matching the pact_verifier_cli default
			pactffi_verifier_set_provider_state(handle, stateChangeURL.absoluteString.cString(using: .utf8), 0, 1)
		}

		if let publish = options.publish {
			let result = withCStrings(publish.providerTags) {
				pactffi_verifier_set_publish_options(handle, publish.providerVersion.cString(using: .utf8), nil, $0, $1, nil)
			}
			guard result == 0 else {
				return .failure(.invalidArguments)
			}
		}

		let verificationResult = pactffi_verifier_execute(handle)

		if let output = pactffi_verifier_output(handle, 0) {
			print(String(cString: output))
			pactffi_string_delete(UnsafeMutablePointer(mutating: output))
		}

		// Errors are returned as non-zero numeric values
		guard verificationResult == 0 else {
			return .failure(ProviderVerificationError(code: verificationResult))
		}

		// Verification completed successfully
		return .success(true)
	}

}

// MARK: - Options

/// The options used when verifying a provider
public struct ProviderVerificationOptions: Equatable {

	/// The provider being verified
	public struct Provider: Equatable {
		/// Name of the provider. Pacts loaded from directories are only verified when they name this provider.
		public var name: String?

		/// Scheme, host and path of the provider. Defaults to `http://localhost/`.
		public var url: URL?

		public var port: Int

		public init(name: String? = nil, url: URL? = nil, port: Int) {
			self.name = name
			self.url = url
			self.port = port
		}
	}

	/// Authentication used when fetching pacts
	public enum Authentication: Equatable {
		case basic(username: String, password: String)
		case token(String)
	}

	/// A Pact Broker to fetch the pacts for the provider from
	public struct Broker: Equatable {
		public var url: String
		public var authentication: Authentication?

		/// Verifies pending pacts without failing the verification
		public var enablePending: Bool

		/// Includes WIP pacts since this date, formatted as `YYYY-MM-DD`
		public var includeWIPPactsSince: String?

		/// Provider tags, used by the broker to work out pending and WIP pacts
		public var providerTags: [String]

		/// Consumer version selectors, each one a JSON document
		public var consumerVersionSelectors: [String]

		public init(
			url: String,
			authentication: Authentication? = nil,
			enablePending: Bool = false,
			includeWIPPactsSince: String? = nil,
			providerTags: [String] = [],
			consumerVersionSelectors: [String] = []
		) {
			self.url = url
			self.authentication = authentication
			self.enablePending = enablePending
			self.includeWIPPactsSince = includeWIPPactsSince
			self.providerTags = providerTags
			self.consumerVersionSelectors = consumerVersionSelectors
		}
	}

	/// The source of pacts to verify
	public enum Source: Equatable {
		case directory(String)
		case file(String)
		case url(URL)
		case broker(Broker)
	}

	/// Limits the interactions being verified
	public struct Filter: Equatable {
		/// Regular expression the interaction description has to match
		public var description: String?

		/// Regular expression one of the interaction provider states has to match
		public var state: String?

		/// Only verifies interactions without a provider state
		public var noState: Bool

		public init(description: String? = nil, state: String? = nil, noState: Bool = false) {
			self.description = description
			self.state = state
			self.noState = noState
		}
	}

	/// Publishes the verification results to the Pact Broker
	public struct Publish: Equatable {
		public var providerVersion: String
		public var providerTags: [String]

		public init(providerVersion: String, providerTags: [String] = []) {
			self.providerVersion = providerVersion
			self.providerTags = providerTags
		}
	}

	public var provider: Provider
	public var sources: [Source]
	public var filter: Filter?

	/// Only verifies the pacts of these consumers. All consumers are verified when empty.
	public var consumers: [String]

	/// URL to post state change requests to
	public var stateChangeURL: URL?

	/// Verification results are only published when set
	public var publish: Publish?

	public init(
		provider: Provider,
		sources: [Source],
		filter: Filter? = nil,
		consumers: [String] = [],
		stateChangeURL: URL? = nil,
		publish: Publish? = nil
	) {
		self.provider = provider
		self.sources = sources
		self.filter = filter
		self.consumers = consumers
		self.stateChangeURL = stateChangeURL
		self.publish = publish
	}

}

// MARK: - Private

private extension Verifier {

	/// Adds a pact source to the verifier, returning `false` when the source is invalid
	func add(_ source: ProviderVerificationOptions.Source, to handle: OpaquePointer) -> Bool {
		switch source {
		case .directory(let directory):
			pactffi_verifier_add_directory_source(handle, directory.cString(using: .utf8))

		case .file(let file):
			pactffi_verifier_add_file_source(handle, file.cString(using: .utf8))

		case .url(let url):
			pactffi_verifier_url_source(handle, url.absoluteString.cString(using: .utf8), nil, nil, nil)

		case .broker(let broker):
			let credentials = broker.authentication?.credentials
			let result = withCStrings(broker.providerTags) { providerTags, providerTagsCount in
				withCStrings(broker.consumerVersionSelectors) { selectors, selectorsCount in
					pactffi_verifier_broker_source_with_selectors(
						handle,
						broker.url.cString(using: .utf8),
						credentials?.username?.cString(using: .utf8),
						credentials?.password?.cString(using: .utf8),
						credentials?.token?.cString(using: .utf8),
						broker.enablePending ? 1 : 0,
						broker.includeWIPPactsSince?.cString(using: .utf8),
						providerTags,
						providerTagsCount,
						nil,
						selectors,
						selectorsCount,
						nil,
						0
					)
				}
			}
			return result == 0
		}

		return true
	}

}

private extension ProviderVerificationOptions.Authentication {

	var credentials: (username: String?, password: String?, token: String?) {
		switch self {
		case let .basic(username, password): return (username, password, nil)
		case .token(let token): return (nil, nil, token)
		}
	}

}

/// Calls `body` with `strings` as a C array of C strings and its length
private func withCStrings<Result>(_ strings: [String], _ body: (UnsafePointer<UnsafePointer<CChar>?>?, UInt16) -> Result) -> Result {
	let cStrings = strings.map { strdup($0) }
	defer { cStrings.forEach { free($0) } }

	return cStrings.map { $0.map { UnsafePointer($0) } }.withUnsafeBufferPointer { body($0.baseAddress, UInt16(strings.count)) }
}
