//
//  Created by Oliver Jones on 14/12/2022.
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

final class PactBuilderTests: XCTestCase {

	private let consumer = "Test_Consumer"
	private let provider = "Test_Provider"

	var builder: PactBuilder!

	private var pactDirectory: String {
		NSTemporaryDirectory().appending("pacts/")
	}

	@MainActor
	class override func setUp() {
		super.setUp()
		try! Logging.initialize()
	}

	override func setUpWithError() throws {
		try super.setUpWithError()

		guard builder == nil else {
			return
		}

		let pact = try Pact(consumer: consumer, provider: provider)
			.withSpecification(.v4)
			.withMetadata(namespace: "namespace1", name: "name1", value: "value1")
			.withMetadata(namespace: "namespace2", name: "name2", value: "value2")

		let config = PactBuilder.Config(pactDirectory: pactDirectory)
		builder = PactBuilder(pact: pact, config: config)
	}

	func testPactVersion() throws {
		XCTAssertEqual(Pact.version, "0.5.12")
	}

	func testGetEvents() async throws {
		try builder
			.uponReceiving("a request to retrieve all events with no authorization")
			.given("There are events")
			.testName(name)
			.withRequest(path: "/events") { request in
				try request.queryParam(name: "something", values: ["orOther"])
			}
			.willRespond(with: 200) { response in
				try response.body("", contentType: "text/plain")
			}

		try await builder.verify { ctx in
			var components = try XCTUnwrap(URLComponents(url: ctx.mockServerURL, resolvingAgainstBaseURL: false))
			components.path = "/events"
			components.queryItems = [
				URLQueryItem(name: "something", value: "orOther"),
			]

			let session = URLSession(configuration: .ephemeral)
			let (data, response) = try await session.data(from: try XCTUnwrap(components.url))

			let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
			XCTAssertEqual(httpResponse.statusCode, 200)
			XCTAssertEqual(httpResponse.value(forHTTPHeaderField: "Content-Type"), "text/plain")
			XCTAssertTrue(data.isEmpty)
		}
	}

	func testCreateEvent() async throws {
		try builder
			.uponReceiving("a request to create an event with no authorization")
			.given("There are events")
			.testName(name)
			.withRequest(method: .POST, path: "/events") { request in
				try request.header("Accept", values: ["application/json"])
			}
			.willRespond(with: 201) { response in
				try response.body("OK", contentType: "text/plain")
			}

		try await builder.verify { ctx in
			var components = try XCTUnwrap(URLComponents(url: ctx.mockServerURL, resolvingAgainstBaseURL: false))
			components.path = "/events"

			var request = URLRequest(url: try XCTUnwrap(components.url))
			request.httpMethod = "POST"
			request.setValue("application/json", forHTTPHeaderField: "Accept")

			let session = URLSession(configuration: .ephemeral)
			let (data, response) = try await session.data(for: request)

			let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
			XCTAssertEqual(httpResponse.statusCode, 201)
			XCTAssertEqual(httpResponse.value(forHTTPHeaderField: "Content-Type"), "text/plain")
			XCTAssertEqual(data, "OK".data(using: .utf8))
		}
	}

	func testUploadAndDownloadBinaryBody() async throws {
		// Contains a NUL byte and invalid UTF-8, which a String body can't carry.
		let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF, 0xFE, 0x0D, 0x0A])

		try builder
			.uponReceiving("a request to upload a binary document")
			.given("There are events")
			.testName(name)
			.withRequest(method: .PUT, path: "/documents/1") { request in
				try request.body(bytes, contentType: "application/octet-stream")
			}
			.willRespond(with: 200) { response in
				try response.body(bytes, contentType: "application/octet-stream")
			}

		try await builder.verify { ctx in
			var components = try XCTUnwrap(URLComponents(url: ctx.mockServerURL, resolvingAgainstBaseURL: false))
			components.path = "/documents/1"

			var request = URLRequest(url: try XCTUnwrap(components.url))
			request.httpMethod = "PUT"
			request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
			request.httpBody = bytes

			let session = URLSession(configuration: .ephemeral)
			let (data, response) = try await session.data(for: request)

			let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
			XCTAssertEqual(httpResponse.statusCode, 200)
			XCTAssertEqual(data, bytes)
		}
	}

	func testSecureMockServer() async throws {
		let pact = try Pact(consumer: consumer, provider: provider).withSpecification(.v4)
		let builder = PactBuilder(pact: pact, config: .init(pactDirectory: pactDirectory, transferProtocol: .secure))

		try builder
			.uponReceiving("a secure request for events")
			.testName(name)
			.withRequest(path: "/secure-events")
			.willRespond(with: 200)

		try await builder.verify { ctx in
			XCTAssertEqual(ctx.mockServerURL.scheme, "https")
			let session = URLSession(configuration: .ephemeral, delegate: SelfSignedTrustingDelegate(), delegateQueue: nil)

			let (_, response) = try await session.data(from: ctx.mockServerURL.appendingPathComponent("secure-events"))
			XCTAssertEqual(try XCTUnwrap(response as? HTTPURLResponse).statusCode, 200)
		}
	}

	func testBinaryBodyMatchingContentType() async throws {
		let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

		try builder
			.uponReceiving("a request to upload a photo")
			.testName(name)
			.withRequest(method: .PUT, path: "/photos/1") { request in
				try request.body(pngHeader + Data([0x00, 0x01]), matchingContentType: "image/png")
			}
			.willRespond(with: 204)

		try await builder.verify { ctx in
			var request = URLRequest(url: ctx.mockServerURL.appendingPathComponent("photos/1"))
			request.httpMethod = "PUT"
			request.setValue("image/png", forHTTPHeaderField: "Content-Type")
			request.httpBody = pngHeader + Data([0x02, 0x03, 0x04])

			let (_, response) = try await URLSession(configuration: .ephemeral).data(for: request)
			XCTAssertEqual(try XCTUnwrap(response as? HTTPURLResponse).statusCode, 204)
		}
	}

	func testBinaryBodyMatchingContentTypeFailsForOtherContent() async throws {
		try builder
			.uponReceiving("a request to upload a photo as text")
			.testName(name)
			.withRequest(method: .PUT, path: "/photos/2") { request in
				try request.body(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), matchingContentType: "image/png")
			}
			.willRespond(with: 204)

		do {
			try await builder.verify { ctx in
				var request = URLRequest(url: ctx.mockServerURL.appendingPathComponent("photos/2"))
				request.httpMethod = "PUT"
				request.setValue("image/png", forHTTPHeaderField: "Content-Type")
				request.httpBody = Data("not a photo".utf8)
				_ = try await URLSession(configuration: .ephemeral).data(for: request)
			}
			XCTFail("Expected the body to not match")
		} catch PactBuilder.Error.pactFailure {
			// expected
		}
	}

	func testUploadAndDownloadMultipartBody() async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
		let imageFile = directory.appendingPathComponent("photo.png")
		try (pngHeader + Data([0x00, 0x01])).write(to: imageFile)
		let textFile = directory.appendingPathComponent("notes.txt")
		try Data("Some notes".utf8).write(to: textFile)

		try builder
			.uponReceiving("a multipart upload")
			.testName(name)
			.withRequest(method: .POST, path: "/uploads") { request in
				try request
					.multipartBody(contentsOf: imageFile, contentType: "image/png", partName: "photo")
					.multipartBody(contentsOf: textFile, contentType: "text/plain", partName: "notes")
			}
			.willRespond(with: 200) { response in
				try response.multipartBody(contentsOf: textFile, contentType: "text/plain", partName: "receipt", boundary: "receipt-boundary")
			}

		try await builder.verify { ctx in
			var components = try XCTUnwrap(URLComponents(url: ctx.mockServerURL, resolvingAgainstBaseURL: false))
			components.path = "/uploads"

			let boundary = "client-boundary"
			var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"other.png\"\r\nContent-Type: image/png\r\n\r\n".utf8)
			body += pngHeader + Data([0x02, 0x03])
			body += Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"notes\"; filename=\"notes.txt\"\r\nContent-Type: text/plain\r\n\r\nOther notes\r\n".utf8)
			body += Data("--\(boundary)--\r\n".utf8)

			var request = URLRequest(url: try XCTUnwrap(components.url))
			request.httpMethod = "POST"
			request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
			request.httpBody = body

			let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)

			let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
			XCTAssertEqual(httpResponse.statusCode, 200)
			XCTAssertEqual(httpResponse.value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=receipt-boundary")
			let text = try XCTUnwrap(String(data: data, encoding: .utf8))
			XCTAssertTrue(text.contains("name=\"receipt\""))
			XCTAssertTrue(text.contains("Some notes"))
		}
	}

	func testMultipartBodyWithMissingFileThrows() throws {
		let interaction = builder.uponReceiving("a multipart upload of a missing file")

		XCTAssertThrowsError(
			try interaction.withRequest(method: .POST, path: "/uploads") { request in
				try request.multipartBody(contentsOf: URL(fileURLWithPath: "/nonexistent/file.txt"), contentType: "text/plain", partName: "file")
			}
		) { error in
			guard case PactInteraction.Error.invalidBody(let message) = error else {
				return XCTFail("Unexpected error \(error)")
			}
			XCTAssertFalse(message.isEmpty)
		}
	}
}

/// Trusts the self-signed certificate of the mock server.
private final class SelfSignedTrustingDelegate: NSObject, URLSessionDelegate, Sendable {
	func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
		guard challenge.protectionSpace.host == "127.0.0.1", let trust = challenge.protectionSpace.serverTrust else {
			return (.performDefaultHandling, nil)
		}
		return (.useCredential, URLCredential(trust: trust))
	}
}
