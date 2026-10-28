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

	func testV4Fields() throws {
		let pact = try Pact(consumer: "v4-fields-consumer", provider: "v4-fields-provider")
			.withSpecification(.v4)

		try Interaction(pactHandle: pact.handle, description: "An interaction")
			.pending()
			.key("get-test")
			.comment("First comment")
			.comment("Second comment")
			.comment("ticket", json: #"{"id": 42}"#)
			.reference(group: "openapi", name: "operationId", value: "123")
			.withRequest(method: .GET, path: "/test")
			.willRespond(with: 200)

		try AsynchronousMessage(pactHandle: pact.handle, description: "A message")
			.pending()
			.comment("Message comment")
			.body("hello", contentType: "text/plain")

		let interactions = try writtenInteractions(of: pact)
		let http = try XCTUnwrap(interactions.first { $0["type"] as? String == "Synchronous/HTTP" })
		XCTAssertEqual(http["pending"] as? Bool, true)
		XCTAssertEqual(http["key"] as? String, "get-test")
		let comments = try XCTUnwrap(http["comments"] as? [String: Any])
		XCTAssertEqual(comments["text"] as? [String], ["First comment", "Second comment"])
		XCTAssertEqual(comments["ticket"] as? [String: Int], ["id": 42])
		XCTAssertEqual((comments["references"] as? [String: [String: String]])?["openapi"]?["operationId"], "123")

		let message = try XCTUnwrap(interactions.first { $0["type"] as? String == "Asynchronous/Messages" })
		XCTAssertEqual(message["pending"] as? Bool, true)
		XCTAssertEqual((message["comments"] as? [String: Any])?["text"] as? [String], ["Message comment"])
	}

	func testProviderStateParams() throws {
		let pact = try Pact(consumer: "params-consumer", provider: "params-provider")
			.withSpecification(.v4)

		try Interaction(pactHandle: pact.handle, description: "An interaction")
			.given(
				try .init(description: "A user exists", params: ["id": 1, "name": "John", "active": true, "tags": ["a", "b"], "score": 1.5]),
				.init(description: "An order exists", name: "orderId", value: "\"42\"")
			)
			.withRequest(method: .GET, path: "/test")
			.willRespond(with: 200)

		let interaction = try XCTUnwrap(try writtenInteractions(of: pact).first)
		let states = try XCTUnwrap(interaction["providerStates"] as? [[String: Any]])
		let user = try XCTUnwrap(states.first { $0["name"] as? String == "A user exists" }?["params"] as? [String: Any])
		XCTAssertEqual(user["id"] as? Int, 1)
		XCTAssertEqual(user["name"] as? String, "John")
		XCTAssertEqual(user["active"] as? Bool, true)
		XCTAssertEqual(user["tags"] as? [String], ["a", "b"])
		XCTAssertEqual(user["score"] as? Double, 1.5)
		let order = try XCTUnwrap(states.first { $0["name"] as? String == "An order exists" }?["params"] as? [String: Any])
		XCTAssertEqual(order["orderId"] as? String, "42")
	}

	func testResponseStatusWithMatcher() throws {
		let pact = try Pact(consumer: "status-consumer", provider: "status-provider")
			.withSpecification(.v4)

		try Interaction(pactHandle: pact.handle, description: "An interaction")
			.withRequest(method: .GET, path: "/test")
			.willRespond(with: 200) { response in
				try response.status(#"{"value":404,"pact:matcher:type":"statusCode","status":"clientError"}"#)
			}

		let interaction = try XCTUnwrap(try writtenInteractions(of: pact).first)
		let response = try XCTUnwrap(interaction["response"] as? [String: Any])
		XCTAssertEqual(response["status"] as? Int, 404)

		let statusRules = try XCTUnwrap((response["matchingRules"] as? [String: Any])?["status"] as? [String: Any])
		let matchers = try XCTUnwrap((statusRules["$"] as? [String: Any])?["matchers"] as? [[String: Any]])
		XCTAssertEqual(matchers.first?["match"] as? String, "statusCode")
		XCTAssertEqual(matchers.first?["status"] as? String, "clientError")
	}

}

private extension InteractionTests {

	func writtenInteractions(of pact: Pact) throws -> [[String: Any]] {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		defer { try? FileManager.default.removeItem(at: directory) }
		try pact.writePactFile(directory: directory.path, overwrite: true)

		let data = try Data(contentsOf: directory.appendingPathComponent(pact.filename))
		let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
		return try XCTUnwrap(json["interactions"] as? [[String: Any]])
	}

}
