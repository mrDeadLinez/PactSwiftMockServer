import Foundation

#if SWIFT_PACKAGE
import PactMockServer
#endif

public protocol MetadataBuilder {
	/// Configures a metadata entry for the message.
	///
	/// The `json` is parsed as a JSON value. To include matching rules, use the matching rule JSON format. I.e.
	///
	/// ```
	/// builder.metadata("partition", json: #"{"value":2, "pact:matcher:type":"integer"}"#)
	/// ```
	/// See [IntegrationJson.md](https://github.com/pact-foundation/pact-reference/blob/master/rust/pact_ffi/IntegrationJson.md)
	///
	/// - Throws: ``PactInteraction/Error/canNotBeModified`` if the interaction or Pact can't be modified.
	///
	@discardableResult
	func metadata(_ name: String, json: String) throws -> Self
}

public extension MetadataBuilder {
	/// Configures a metadata entry for the message with a string value.
	@discardableResult
	func metadata(_ name: String, value: String) throws -> Self {
		try metadata(name, json: String(data: JSONEncoder().encode(value), encoding: .utf8)!)
	}
}

/// The contents and metadata of a message, or of the request or a response of a synchronous message.
public struct MessagePart: BodyBuilder, MetadataBuilder {
	private let handle: InteractionHandle
	private let part: InteractionPart

	init(handle: InteractionHandle, part: InteractionPart) {
		self.handle = handle
		self.part = part
	}

	@discardableResult
	public func body(_ body: String?, contentType: String?) throws -> Self {
		guard pactffi_with_body(handle, part, (contentType ?? "text/plain").cString(using: .utf8), body?.cString(using: .utf8)) else {
			throw PactInteraction.Error.canNotBeModified
		}

		return self
	}

	@discardableResult
	public func body(_ body: Data, contentType: String) throws -> Self {
		try withBinaryBody(handle, part, body, contentType: contentType)
		return self
	}

	@discardableResult
	public func body(_ body: Data, matchingContentType contentType: String) throws -> Self {
		try withBinaryBody(handle, part, body, contentType: contentType, matchingContentType: true)
		return self
	}

	@discardableResult
	public func metadata(_ name: String, json: String) throws -> Self {
		guard pactffi_with_metadata(handle, name.cString(using: .utf8), json.cString(using: .utf8), part) else {
			throw PactInteraction.Error.canNotBeModified
		}

		return self
	}
}

/// A message the consumer expects to receive, eg: from a queue or a topic.
public final class AsynchronousMessage: PactInteraction, BodyBuilder, MetadataBuilder {

	private let pactHandle: PactHandle

	internal init(pactHandle: PactHandle, description: String) {
		self.pactHandle = pactHandle
		super.init(handle: pactffi_new_message_interaction(pactHandle, description.cString(using: .utf8)))
	}

	/// Sets the message contents. The content type is also recorded as the `contentType` metadata entry.
	@discardableResult
	public func body(_ body: String?, contentType: String?) throws -> Self {
		try MessagePart(handle: handle, part: .request).body(body, contentType: contentType)
		return self
	}

	/// Sets binary message contents. The content type is also recorded as the `contentType` metadata entry.
	@discardableResult
	public func body(_ body: Data, contentType: String) throws -> Self {
		try MessagePart(handle: handle, part: .request).body(body, contentType: contentType)
		return self
	}

	@discardableResult
	public func body(_ body: Data, matchingContentType contentType: String) throws -> Self {
		try MessagePart(handle: handle, part: .request).body(body, matchingContentType: contentType)
		return self
	}

	@discardableResult
	public func metadata(_ name: String, json: String) throws -> Self {
		try MessagePart(handle: handle, part: .request).metadata(name, json: json)
		return self
	}

	/// The message as the consumer receives it: matchers removed and generators applied.
	internal func reify() throws -> MessageContents {
		guard let cString = pactffi_message_reify(handle) else {
			throw Error.handleInvalid
		}
		defer { pactffi_string_delete(UnsafeMutablePointer(mutating: cString)) }

		guard let json = try JSONSerialization.jsonObject(with: Data(String(cString: cString).utf8), options: .fragmentsAllowed) as? [String: Any] else {
			return MessageContents(contents: Data(), contentType: nil, metadata: [:])
		}

		if json["type"] is String {
			return MessageContents(v4: json)
		}

		let specification = pactffi_handle_get_pact_spec_version(pactHandle)
		guard specification.rawValue <= PactSpecification_V3.rawValue else {
			throw Error.handleInvalid
		}
		return MessageContents(v3: json)
	}

}

/// A request/response message exchange, eg: over a websocket. Requires ``Pact/Specification/v4``.
public final class SynchronousMessage: PactInteraction {

	public typealias PartBuilder = (MessagePart) throws -> Void

	internal init(pactHandle: PactHandle, description: String) {
		super.init(handle: pactffi_new_sync_message_interaction(pactHandle, description.cString(using: .utf8)))
	}

	/// Configures the request message.
	@discardableResult
	public func withRequest(builder: PartBuilder) throws -> Self {
		try builder(MessagePart(handle: handle, part: .request))
		return self
	}

	/// Adds a response message. Call it once for every response the provider sends.
	///
	/// Set the body before the metadata: a body adds the response, and metadata applies to every response added so far.
	@discardableResult
	public func willRespond(builder: PartBuilder) throws -> Self {
		try builder(MessagePart(handle: handle, part: .response))
		return self
	}

	/// The request and responses as the consumer sees them: matchers removed and generators applied.
	internal func generateContents() throws -> SynchronousMessageContents {
		guard let cString = pactffi_sync_message_generate_contents(handle) else {
			throw Error.handleInvalid
		}
		defer { pactffi_string_delete(UnsafeMutablePointer(mutating: cString)) }

		guard let json = try JSONSerialization.jsonObject(with: Data(String(cString: cString).utf8), options: .fragmentsAllowed) as? [String: Any] else {
			throw Error.handleInvalid
		}

		return SynchronousMessageContents(
			request: MessageContents(v4: json["request"] as? [String: Any] ?? [:]),
			responses: (json["response"] as? [[String: Any]] ?? []).map(MessageContents.init(v4:))
		)
	}

}

/// A message as the consumer receives it.
public struct MessageContents: Sendable, Equatable {
	public let contents: Data
	public let contentType: String?
	/// Metadata values that are not strings are given as JSON.
	public let metadata: [String: String]

	public init(contents: Data, contentType: String?, metadata: [String: String]) {
		self.contents = contents
		self.contentType = contentType
		self.metadata = metadata
	}
}

/// A synchronous message as the consumer sees it.
public struct SynchronousMessageContents: Sendable, Equatable {
	public let request: MessageContents
	public let responses: [MessageContents]
}

private extension MessageContents {

	/// `{"contents": {"content": …, "contentType": …, "encoded": …}, "metadata": {…}}`
	init(v4 json: [String: Any]) {
		let body = json["contents"] as? [String: Any] ?? [:]
		let content = body["content"]
		let data: Data
		if body["encoded"] as? String == "base64", let string = content as? String {
			data = Data(base64Encoded: string) ?? Data()
		} else {
			data = Self.data(content)
		}
		self.init(contents: data, contentType: body["contentType"] as? String, metadata: Self.metadata(json["metadata"]))
	}

	/// `{"contents": …, "metadata": {"contentType": …}}`, where binary contents are base64 encoded.
	init(v3 json: [String: Any]) {
		let metadata = Self.metadata(json["metadata"])
		let contentType = metadata["contentType"]
		let content = json["contents"]
		let data: Data
		if let string = content as? String, let contentType, Self.isText(contentType) == false {
			data = Data(base64Encoded: string) ?? Data(string.utf8)
		} else {
			data = Self.data(content)
		}
		self.init(contents: data, contentType: contentType, metadata: metadata)
	}

	static func data(_ content: Any?) -> Data {
		switch content {
		case nil, is NSNull:
			return Data()
		case let string as String:
			return Data(string.utf8)
		case let value?:
			return (try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)) ?? Data()
		}
	}

	static func metadata(_ json: Any?) -> [String: String] {
		(json as? [String: Any] ?? [:]).mapValues { value in
			if let string = value as? String {
				return string
			}
			return String(data: data(value), encoding: .utf8) ?? ""
		}
	}

	static func isText(_ contentType: String) -> Bool {
		let contentType = contentType.lowercased()
		return contentType.hasPrefix("text/") || contentType.contains("json") || contentType.contains("xml")
	}

}
