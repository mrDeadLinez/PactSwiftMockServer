//
//  Created by Oliver Jones on 15/12/2022.
//  Copyright © 2022 Oliver Jones. All rights reserved.
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

public final class PactBuilder {

	public enum Error {
		/// Thrown when the Pact fails to verify.
		case pactFailure([PactVerificationFailure])

		/// Thrown when the response produced for a ``SynchronousMessage`` does not match the expected response.
		case messageMismatch([String])
	}

	public struct ConsumerContext: Sendable {

		/// The base URL of the mock server.
		public let mockServerURL: URL

		public init(mockServerURL: URL) {
			self.mockServerURL = mockServerURL
		}
	}

	public struct Config: Sendable {
		/// The directory in to which Pacts are written.
		public let pactDirectory: String

		/// The protocol the mock server is called with.
		///
		/// A ``MockServer/TransferProtocol/secure`` mock server uses a certificate for `localhost` it signs itself when it starts,
		/// so the consumer has to trust it, eg: by accepting the server trust in a `URLSessionDelegate`.
		public let transferProtocol: MockServer.TransferProtocol

		/// The options of the mock server.
		public let mockServer: MockServer.Configuration

		public init(pactDirectory: String, transferProtocol: MockServer.TransferProtocol = .standard, mockServer: MockServer.Configuration = MockServer.Configuration()) {
			self.pactDirectory = pactDirectory
			self.transferProtocol = transferProtocol
			self.mockServer = mockServer
		}
	}

	private let pact: Pact
	private let config: Config

	public init(pact: Pact, config: Config) {
		self.pact = pact
		self.config = config
	}

	/// Create a new `Interaction`.
	///
	/// - parameter description - The interaction description. It needs to be unique for each interaction.
	public func uponReceiving(_ description: String) -> Interaction {
		pact.uponReceiving(description)
	}

	/// Create a new ``AsynchronousMessage``.
	///
	/// - parameter description - The message description. It needs to be unique for each interaction.
	public func expectsToReceive(_ description: String) -> AsynchronousMessage {
		pact.expectsToReceive(description)
	}

	/// Create a new ``SynchronousMessage``. Requires ``Pact/Specification/v4``.
	///
	/// - parameter description - The message description. It needs to be unique for each interaction.
	public func synchronousMessage(_ description: String) -> SynchronousMessage {
		pact.synchronousMessage(description)
	}

	/// Passes the message to the consumer's `handler` and writes the Pact when the handler does not throw.
	public func verify(_ message: AsynchronousMessage, handler: (MessageContents) throws -> Void) throws {
		try handler(message.reify())
		try pact.writePactFile(directory: config.pactDirectory, overwrite: false)
	}

	/// Passes the message to the consumer's `handler` and writes the Pact when the handler does not throw.
	public func verify(_ message: AsynchronousMessage, handler: @Sendable (MessageContents) async throws -> Void) async throws {
		try await handler(message.reify())
		try pact.writePactFile(directory: config.pactDirectory, overwrite: false)
	}

	/// Passes the request and responses to the consumer's `handler` and writes the Pact when the handler does not throw.
	public func verify(_ message: SynchronousMessage, handler: (SynchronousMessageContents) throws -> Void) throws {
		try handler(message.generateContents())
		try pact.writePactFile(directory: config.pactDirectory, overwrite: false)
	}

	/// Passes the request and responses to the consumer's `handler` and writes the Pact when the handler does not throw.
	public func verify(_ message: SynchronousMessage, handler: @Sendable (SynchronousMessageContents) async throws -> Void) async throws {
		try await handler(message.generateContents())
		try pact.writePactFile(directory: config.pactDirectory, overwrite: false)
	}

	/// Passes the request to the consumer's `handler`, matches the response it produces against the first expected response
	/// and writes the Pact when it matches.
	///
	/// - Throws: An ``Error/messageMismatch(_:)`` if the response does not match.
	public func verify(_ message: SynchronousMessage, respondingWith handler: (MessageContents) throws -> MessageContents) throws {
		let contents = try message.generateContents()
		try verifyResponse(try handler(contents.request), of: message)
	}

	/// Passes the request to the consumer's `handler`, matches the response it produces against the first expected response
	/// and writes the Pact when it matches.
	///
	/// - Throws: An ``Error/messageMismatch(_:)`` if the response does not match.
	public func verify(_ message: SynchronousMessage, respondingWith handler: @Sendable (MessageContents) async throws -> MessageContents) async throws {
		let contents = try message.generateContents()
		try verifyResponse(try await handler(contents.request), of: message)
	}

	private func verifyResponse(_ response: MessageContents, of message: SynchronousMessage) throws {
		let mismatches = try message.mismatches(of: response, index: 0)
		guard mismatches.isEmpty else {
			throw Error.messageMismatch(mismatches)
		}

		try pact.writePactFile(directory: config.pactDirectory, overwrite: false)
	}

	/// Verify the configured interactions.
	///
	/// - Throws: An ``Error/pactFailure(_:)`` if the pact fails to verify or a ``MockServer/Error`` if the mock server fails.
	public func verify(handler: (ConsumerContext) throws -> Void) throws {
		let mockServer = try MockServer(pact: pact, transferProtocol: config.transferProtocol, configuration: config.mockServer)

		try handler(ConsumerContext(mockServerURL: mockServer.baseUrl))

		try verifyInternal(mockServer: mockServer)
	}

	/// Verify the configured interactions.
	///
	/// - Throws: An ``Error/pactFailure(_:)`` if the pact fails to verify or a ``MockServer/Error`` if the mock server fails.
	public func verify(handler: @Sendable (ConsumerContext) async throws -> Void) async throws {
		let mockServer = try MockServer(pact: pact, transferProtocol: config.transferProtocol, configuration: config.mockServer)

		try await handler(ConsumerContext(mockServerURL: mockServer.baseUrl))

		try verifyInternal(mockServer: mockServer)
	}

	/// Verify the interactions after the consumer client has been invoked
	/// - Parameters:
	///   - mockServer: The ``MockServer`` instance.
	private func verifyInternal(mockServer: MockServer) throws {
		guard mockServer.requestsMatched else {
			let failures = try JSONDecoder().decode([PactVerificationFailure].self, from: mockServer.mismatchesJSON?.data(using: .utf8) ?? Data())
			throw Error.pactFailure(failures)
		}

		try pact.writePactFile(directory: config.pactDirectory, overwrite: false)
	}
}

extension PactBuilder.Error: LocalizedError {
	public var failureReason: String? {
		switch self {
		case .pactFailure(let mismatches):
			return String.localizedStringWithFormat(NSLocalizedString("Pact Failure (see below):\n%@", comment: ""), mismatches.map(\.description).joined(separator: "\n---\n"))
		case .messageMismatch(let mismatches):
			return String.localizedStringWithFormat(NSLocalizedString("Message Mismatch (see below):\n%@", comment: ""), mismatches.joined(separator: "\n"))
		}
	}
}
