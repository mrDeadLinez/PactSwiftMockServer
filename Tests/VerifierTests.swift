//
//  Created by Marko Justinek on 21/8/21.
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

import XCTest

@testable import PactSwiftMockServer

class VerifierTests: XCTestCase {

	// MARK: - Properties

	private var testSubject: Verifier!

	// MARK: - Lifecycle

	override func setUpWithError() throws {
		try super.setUpWithError()

		testSubject = Verifier()
	}

	override func tearDownWithError() throws {
		testSubject = nil

		try super.tearDownWithError()
	}

	// MARK: - Tests

	func testVerificationSucceedsAgainstARunningProvider() throws {
		let providerPact = Pact(consumer: "test-consumer", provider: "provider")
		try providerPact.uponReceiving("a request").withRequest(path: "/").willRespond(with: 200)
		let provider = try MockServer(pact: providerPact)

		let pactFile = try writeValidPact()
		defer { try? FileManager.default.removeItem(at: pactFile) }

		let options = ProviderVerificationOptions(
			provider: .init(url: URL(string: "http://127.0.0.1"), port: Int(provider.port)),
			sources: [.file(pactFile.path)]
		)

		withExtendedLifetime(provider) {
			XCTAssertEqual(testSubject.verifyProvider(options: options), .success(true))
		}
	}

	func testVerificationFailsWhenThereAreNoPacts() {
		let options = ProviderVerificationOptions(provider: .init(port: 1234), sources: [.directory("../NonExistingDir")])

		XCTAssertEqual(testSubject.verifyProvider(options: options), .failure(.verificationFailed))
	}

	func testVerificationFailsWhenProviderIsNotRunning() throws {
		let pactFile = try writeValidPact()
		defer { try? FileManager.default.removeItem(at: pactFile) }

		let options = ProviderVerificationOptions(provider: .init(port: 1), sources: [.file(pactFile.path)])

		XCTAssertEqual(testSubject.verifyProvider(options: options), .failure(.verificationFailed))
	}

	func testInvalidConsumerVersionSelector() {
		let options = ProviderVerificationOptions(
			provider: .init(port: 1234),
			sources: [.broker(.init(url: "http://localhost:1", consumerVersionSelectors: ["not json"]))]
		)

		XCTAssertEqual(testSubject.verifyProvider(options: options), .failure(.invalidArguments))
	}

}

private extension VerifierTests {

	func writeValidPact() throws -> URL {
		let pactFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
		try validPact.write(to: pactFile, atomically: true, encoding: .utf8)
		return pactFile
	}

	var validPact: String {
		"""
		{
		  "consumer": { "name": "test-consumer" },
		  "provider": { "name": "provider" },
		  "interactions": [
		    { "description": "a request", "request": { "method": "GET", "path": "/" }, "response": { "status": 200 } }
		  ],
		  "metadata": { "pactSpecification": { "version": "3.0.0" } }
		}
		"""
	}

}
