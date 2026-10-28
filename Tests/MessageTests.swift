import XCTest
@testable import PactSwiftMockServer

final class MessageTests: XCTestCase {

	private var pactDirectory: URL!

	@MainActor
	class override func setUp() {
		super.setUp()
		try! Logging.initialize()
	}

	override func setUpWithError() throws {
		try super.setUpWithError()
		pactDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	}

	override func tearDownWithError() throws {
		try? FileManager.default.removeItem(at: pactDirectory)
		try super.tearDownWithError()
	}

	func testAsynchronousMessage() throws {
		let (pact, builder) = try makeBuilder(.v4)
		let message = try builder
			.expectsToReceive("an order created event")
			.given("An order exists")
			.body(#"{"id": {"value": 100, "pact:matcher:type": "integer", "pact:generator:type": "RandomInt", "min": 1, "max": 9}, "status": "created"}"#, contentType: "application/json")
			.metadata("queue", value: "orders")
			.metadata("partition", json: #"{"value": 2, "pact:matcher:type": "integer"}"#)

		var received: MessageContents?
		try builder.verify(message) { received = $0 }

		let contents = try XCTUnwrap(received)
		XCTAssertEqual(contents.contentType, "application/json")
		XCTAssertEqual(contents.metadata["queue"], "orders")
		XCTAssertEqual(contents.metadata["partition"], "2")
		let body = try XCTUnwrap(JSONSerialization.jsonObject(with: contents.contents) as? [String: Any])
		XCTAssertEqual(body["status"] as? String, "created")
		XCTAssertTrue((1...9).contains(try XCTUnwrap(body["id"] as? Int)))

		let interaction = try XCTUnwrap(try interactions(of: pact).first)
		XCTAssertEqual(interaction["type"] as? String, "Asynchronous/Messages")
		XCTAssertEqual(interaction["description"] as? String, "an order created event")
		let rules = try XCTUnwrap(interaction["matchingRules"] as? [String: Any])
		XCTAssertNotNil((rules["body"] as? [String: Any])?["$.id"])
		XCTAssertNotNil((rules["metadata"] as? [String: Any])?["partition"])
	}

	func testAsynchronousBinaryMessage() throws {
		let (_, builder) = try makeBuilder(.v4)
		let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF])
		let message = try builder
			.expectsToReceive("a binary event")
			.body(bytes, contentType: "application/octet-stream")

		var received: MessageContents?
		try builder.verify(message) { received = $0 }

		XCTAssertEqual(received?.contents, bytes)
		XCTAssertEqual(received?.contentType, "application/octet-stream")
	}

	func testAsynchronousMessageV3() throws {
		let (pact, builder) = try makeBuilder(.v3)
		let message = try builder
			.expectsToReceive("a text event")
			.body("hello", contentType: "text/plain")

		var received: MessageContents?
		try builder.verify(message) { received = $0 }

		XCTAssertEqual(received?.contents, Data("hello".utf8))
		XCTAssertEqual(received?.contentType, "text/plain")
		XCTAssertEqual(try pactJSON(of: pact)["messages"].map { ($0 as? [Any])?.count }, 1)
	}

	func testAsynchronousMessageAsync() async throws {
		let (_, builder) = try makeBuilder(.v4)
		let message = try builder
			.expectsToReceive("an async handled event")
			.body("hello", contentType: "text/plain")

		try await builder.verify(message) { contents in
			XCTAssertEqual(contents.contents, Data("hello".utf8))
		}
	}

	func testHandlerFailureDoesNotWritePact() throws {
		struct HandlerError: Swift.Error {}
		let (pact, builder) = try makeBuilder(.v4)
		let message = try builder
			.expectsToReceive("an event the consumer rejects")
			.body("hello", contentType: "text/plain")

		XCTAssertThrowsError(try builder.verify(message) { _ in throw HandlerError() })
		XCTAssertFalse(FileManager.default.fileExists(atPath: pactDirectory.appendingPathComponent(pact.filename).path))
	}

	func testSynchronousMessage() throws {
		let (pact, builder) = try makeBuilder(.v4)
		let message = try builder
			.synchronousMessage("a request for the order status")
			.given("An order exists")
			.withRequest { request in
				try request
					.body(#"{"orderId": 1}"#, contentType: "application/json")
					.metadata("channel", value: "orders")
			}
			.willRespond { response in
				try response.body(#"{"status": {"value": "created", "pact:matcher:type": "type"}}"#, contentType: "application/json")
			}
			.willRespond { response in
				try response.body("pending", contentType: "text/plain")
			}

		var received: SynchronousMessageContents?
		try builder.verify(message) { received = $0 }

		let contents = try XCTUnwrap(received)
		XCTAssertEqual(contents.request.metadata["channel"], "orders")
		XCTAssertEqual(try JSONSerialization.jsonObject(with: contents.request.contents) as? [String: Int], ["orderId": 1])
		XCTAssertEqual(contents.responses.count, 2)
		XCTAssertEqual(try JSONSerialization.jsonObject(with: contents.responses[0].contents) as? [String: String], ["status": "created"])
		XCTAssertEqual(contents.responses[1].contents, Data("pending".utf8))

		let interaction = try XCTUnwrap(try interactions(of: pact).first)
		XCTAssertEqual(interaction["type"] as? String, "Synchronous/Messages")
		XCTAssertEqual((interaction["response"] as? [Any])?.count, 2)
	}

}

private extension MessageTests {

	func makeBuilder(_ specification: Pact.Specification) throws -> (Pact, PactBuilder) {
		let pact = try Pact(consumer: "message-consumer-\(UUID().uuidString)", provider: "message-provider")
			.withSpecification(specification)
		return (pact, PactBuilder(pact: pact, config: .init(pactDirectory: pactDirectory.path)))
	}

	func pactJSON(of pact: Pact) throws -> [String: Any] {
		let data = try Data(contentsOf: pactDirectory.appendingPathComponent(pact.filename))
		return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
	}

	func interactions(of pact: Pact) throws -> [[String: Any]] {
		try XCTUnwrap(try pactJSON(of: pact)["interactions"] as? [[String: Any]])
	}

}
