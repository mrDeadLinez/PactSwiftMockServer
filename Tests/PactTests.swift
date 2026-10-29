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

class PactTests: XCTestCase {
	
	func testPactInitialization() throws {
		let pact = try Pact(consumer: "consumer", provider: "provider")
			.withSpecification(.v3)
			.withMetadata(namespace: "test", name: "name", value: "value")
		
		XCTAssertEqual(pact.consumer, "consumer")
		XCTAssertEqual(pact.provider, "provider")
		XCTAssertEqual(pact.filename, "consumer-provider.json")
	}

	func testUsingPluginThatIsNotInstalledThrows() throws {
		let pact = Pact(consumer: "plugin-consumer", provider: "plugin-provider")

		XCTAssertThrowsError(try pact.usingPlugin("not-installed-plugin", version: "0.0.1")) { error in
			guard case Pact.Error.canNotLoadPlugin(let name, _) = error else {
				return XCTFail("Unexpected error \(error)")
			}
			XCTAssertEqual(name, "not-installed-plugin")
		}
	}

	func testPluginContentsFallBackToCoreContentTypes() throws {
		let pact = try Pact(consumer: "plugin-consumer", provider: "plugin-provider").withSpecification(.v4)

		try Interaction(pactHandle: pact.handle, description: "a plugin request")
			.withRequest(method: .POST, path: "/") { request in
				try request.pluginContents(#"{"contents": {"id": 1}}"#, contentType: "application/json")
			}
			.willRespond(with: 200)

		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		defer { try? FileManager.default.removeItem(at: directory) }
		try pact.writePactFile(directory: directory.path, overwrite: true)

		let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent(pact.filename))) as? [String: Any])
		let request = try XCTUnwrap((json["interactions"] as? [[String: Any]])?.first?["request"] as? [String: Any])
		XCTAssertEqual(((request["body"] as? [String: Any])?["content"] as? [String: Int]), ["id": 1])
	}

	func testPluginContentsWithInvalidJSONThrows() throws {
		let pact = try Pact(consumer: "plugin-consumer", provider: "plugin-provider").withSpecification(.v4)

		XCTAssertThrowsError(
			try Interaction(pactHandle: pact.handle, description: "a plugin request")
				.withRequest(method: .POST, path: "/") { request in
					try request.pluginContents("not json", contentType: "application/protobuf")
				}
		) { error in
			guard case PactInteraction.Error.invalidBody = error else {
				return XCTFail("Unexpected error \(error)")
			}
		}
	}
}
