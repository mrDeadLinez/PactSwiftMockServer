//
//  Created by Oliver Jones on 16/12/2022.
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

import XCTest
@testable import PactSwiftMockServer

@MainActor
class InteractionTests: XCTestCase {

	@MainActor
	class override func setUp() {
		super.setUp()
		try! Logging.initialize()
	}

	func testInteractionInitialization() throws {
		let pact = try Pact(consumer: "consumer", provider: "provider")
			.withSpecification(.v3)
		
		try Interaction(pactHandle: pact.handle, description: "An interaction")
			.given("Some provider state")
			.withRequest(method: .GET, path: "/test")
			.willRespond(with: 200)
		
		// Nothing to assert as long as it doesn't crash. There is no externally visible state.
	}

	func testResponseStatusWithMatcher() throws {
		let pact = try Pact(consumer: "status-consumer", provider: "status-provider")
			.withSpecification(.v4)

		try Interaction(pactHandle: pact.handle, description: "An interaction")
			.withRequest(method: .GET, path: "/test")
			.willRespond(with: 200) { response in
				try response.status(#"{"value":404,"pact:matcher:type":"statusCode","status":"clientError"}"#)
			}

		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		defer { try? FileManager.default.removeItem(at: directory) }
		try pact.writePactFile(directory: directory.path, overwrite: true)

		let data = try Data(contentsOf: directory.appendingPathComponent(pact.filename))
		let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
		let interaction = try XCTUnwrap((json["interactions"] as? [[String: Any]])?.first)
		let response = try XCTUnwrap(interaction["response"] as? [String: Any])
		XCTAssertEqual(response["status"] as? Int, 404)

		let statusRules = try XCTUnwrap((response["matchingRules"] as? [String: Any])?["status"] as? [String: Any])
		let matchers = try XCTUnwrap((statusRules["$"] as? [String: Any])?["matchers"] as? [[String: Any]])
		XCTAssertEqual(matchers.first?["match"] as? String, "statusCode")
		XCTAssertEqual(matchers.first?["status"] as? String, "clientError")
	}

}
