//
//  Created by Oliver Jones on 12/12/2022.
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

#if SWIFT_PACKAGE
import PactMockServer
#endif

/// The behaviour shared by every kind of interaction in a ``Pact``.
public class PactInteraction {

	public enum Error {
		case panic(String?)
		case handleInvalid
		case canNotBeModified
		case unsupportedForSpecificationVersion
		case unknownResult(Int)
		case invalidBody(String)
	}

	internal let handle: InteractionHandle

	internal init(handle: InteractionHandle) {
		self.handle = handle
	}

	/// Adds a provider state to the Interaction.
	///
	/// Throws ``Error`` if the interaction or Pact can't be modified (i.e. the mock server for it has already started)
	///
	/// - Parameters:
	///   - description - The provider state description. It needs to be unique.
	///
	@discardableResult
	internal func given(_ description: String) throws -> Self {
		guard pactffi_given(handle, description.cString(using: .utf8)) else {
			throw Error.canNotBeModified
		}

		return self
	}

	/// Adds a provider state to the Interaction with a parameter key and value.
	///
	/// Throws ``Error`` if the interaction or Pact can't be modified (i.e. the mock server for it has already started)
	///
	/// - Parameters:
	///   - description - The provider state description. It needs to be unique.
	///   - name - Parameter name.
	///   - value - Parameter value.
	///
	@discardableResult
	internal func given(_ description: String, withName name: String, value: String) throws -> Self {
		guard pactffi_given_with_param(handle, description.cString(using: .utf8), name.cString(using: .utf8), value.cString(using: .utf8)) else {
			throw Error.canNotBeModified
		}

		return self
	}

	/// Adds a provider state to the Interaction with parameters given as a JSON object.
	@discardableResult
	internal func given(_ description: String, params: String) throws -> Self {
		let result = pactffi_given_with_params(handle, description.cString(using: .utf8), params.cString(using: .utf8))
		switch result {
		case 0:
			return self
		case 1:
			throw Error.canNotBeModified
		default:
			throw Error.unknownResult(Int(result))
		}
	}

	/// Sets the test name annotation for the interaction. This allows capturing the name of the test as metadata.
	/// - Warning: This can only be used with ``Pact/Specification/v4`` interactions.
	@discardableResult
	public func testName(_ name: String) throws -> Self {
		precondition(name.isEmpty == false, "The test name must not be empty!")

		let result = pactffi_interaction_test_name(handle, name.cString(using: .utf8))
		guard result == 0 else {
			switch result {
			case 1: // Function panicked. Error message will be available by calling `pactffi_get_error_message`.
				throw Error.panic(Logging.lastInternalErrorMessage)
			case 2: // Handle was not valid.
				throw Error.handleInvalid
			case 3: // Mock server was already started and the integration can not be modified.
				throw Error.canNotBeModified
			case 4: // Not a V4 interaction.
				throw Error.unsupportedForSpecificationVersion
			default:
				throw Error.unknownResult(Int(result))
			}
		}

		return self
	}

	/// Marks the interaction as pending, so a provider failing to verify it does not fail the provider build.
	/// - Note: Only written to ``Pact/Specification/v4`` pacts.
	@discardableResult
	public func pending(_ pending: Bool = true) throws -> Self {
		guard pactffi_set_pending(handle, pending) else {
			throw Error.handleInvalid
		}

		return self
	}

	/// Sets the key that identifies the interaction in the Pact.
	/// - Note: Only written to ``Pact/Specification/v4`` pacts.
	@discardableResult
	public func key(_ key: String) throws -> Self {
		guard pactffi_set_key(handle, key.cString(using: .utf8)) else {
			throw Error.handleInvalid
		}

		return self
	}

	/// Adds a text comment to the interaction.
	/// - Note: Only written to ``Pact/Specification/v4`` pacts.
	@discardableResult
	public func comment(_ text: String) throws -> Self {
		guard pactffi_add_text_comment(handle, text.cString(using: .utf8)) else {
			throw Error.handleInvalid
		}

		return self
	}

	/// Sets a comment entry on the interaction, where `json` is a JSON value. The `text` key holds the comments added by ``comment(_:)``.
	/// - Note: Only written to ``Pact/Specification/v4`` pacts.
	@discardableResult
	public func comment(_ key: String, json: String) throws -> Self {
		guard pactffi_set_comment(handle, key.cString(using: .utf8), json.cString(using: .utf8)) else {
			throw Error.handleInvalid
		}

		return self
	}

	/// Adds a reference to an external description of the interaction, eg: `reference(group: "openapi", name: "operationId", value: "getOrder")`.
	/// - Note: Only written to ``Pact/Specification/v4`` pacts.
	@discardableResult
	public func reference(group: String, name: String, value: String) throws -> Self {
		let json = String(data: try JSONEncoder().encode(value), encoding: .utf8)!
		guard pactffi_add_interaction_reference(handle, group.cString(using: .utf8), name.cString(using: .utf8), json.cString(using: .utf8)) else {
			throw Error.handleInvalid
		}

		return self
	}

}

public extension PactInteraction {

	struct ProviderState: Hashable {
		var description: String
		var name: String?
		var value: String?
		var params: String?

		/// - Parameters:
		///   - description -  The provider state description. It needs to be unique.
		public init(description: String) {
			self.description = description
		}

		/// - Parameters:
		///   - description -  The provider state description. It needs to be unique.
		///   - name - Parameter name.
		///   - value - Parameter value.
		public init(description: String, name: String, value: String) {
			self.description = description
			self.name = name
			self.value = value
		}

		/// - Parameters:
		///   - description -  The provider state description. It needs to be unique.
		///   - params - Parameters with their JSON types, eg: `["id": 1, "name": "John", "active": true]`.
		/// - Throws: An `EncodingError` if a parameter can not be encoded as JSON.
		public init(description: String, params: [String: any Encodable]) throws {
			let encoder = JSONEncoder()
			encoder.outputFormatting = .sortedKeys
			self.description = description
			self.params = String(data: try encoder.encode(params.mapValues(AnyEncodable.init)), encoding: .utf8)!
		}
	}

	/// Adds `providerStates` to the ``Interaction``.
	///
	/// - Throws: ``Error`` if the interaction or Pact can't be modified (i.e. the mock server for it has already started)
	///
	/// - Parameters:
	///   - description - The provider state description. It needs to be unique.
	///   - name - Parameter name.
	///   - value - Parameter value.
	///
	@discardableResult
	func given(_ providerStates: [ProviderState]) throws -> Self {
		precondition(Set(providerStates.map(\.description)).count == providerStates.count, "ProviderState descriptions must be unique!")

		for state in providerStates {
			if let params = state.params {
				try given(state.description, params: params)
			} else if let name = state.name, let value = state.value {
				try given(state.description, withName: name, value: value)
			} else {
				try given(state.description)
			}
		}

		return self
	}

	/// Adds `providerStates` to the ``Interaction``.
	///
	/// Throws ``Error`` if the interaction or Pact can't be modified (i.e. the mock server for it has already started)
	///
	/// - Parameters:
	///   - description - The provider state description. It needs to be unique.
	///   - name - Parameter name.
	///   - value - Parameter value.
	///
	@discardableResult
	func given(_ providerStates: ProviderState...) throws -> Self {
		try given(providerStates)
	}

}

extension PactInteraction.Error: LocalizedError {
	public var failureReason: String? {
		switch self {
		case .canNotBeModified:
			return NSLocalizedString("Can not be modified", comment: "Error message when the interaction can not be modified")
		case .handleInvalid:
			return NSLocalizedString("Invalid Interaction handle", comment: "Error message when the interaction handle is invalid")
		case .unsupportedForSpecificationVersion:
			return NSLocalizedString(
				"Unsupported for specification version",
				comment: "Error message when the action is not supported by the specification version in use"
			)
		case .unknownResult(let code):
			return String.localizedStringWithFormat(
				NSLocalizedString("Unknown result (error code: %d)", comment: "Error message when an unknown result is returned"),
				code
			)
		case .invalidBody(let errorMessage):
			return String.localizedStringWithFormat(
				NSLocalizedString("Invalid body (error: %@)", comment: "Error message when a body can not be set"),
				errorMessage
			)
		case .panic(let errorMessage):
			return String.localizedStringWithFormat(
				NSLocalizedString("Function paniced (error: %@)", comment: "Error message when a rust function panics"),
				errorMessage ?? ""
			)
		}
	}
}

extension PactInteraction.ProviderState: ExpressibleByStringLiteral {
	public init(stringLiteral value: StringLiteralType) {
		self.init(description: value)
	}
}

private struct AnyEncodable: Encodable {
	let value: any Encodable

	func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(value)
	}
}

internal func withBinaryBody(_ handle: InteractionHandle, _ part: InteractionPart, _ body: Data, contentType: String) throws {
	let added = body.withUnsafeBytes { bytes in
		pactffi_with_binary_body(handle, part, contentType.cString(using: .utf8), bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
	}
	guard added else {
		throw PactInteraction.Error.canNotBeModified
	}
}

internal extension InteractionPart {
	static var request: Self { InteractionPart(rawValue: 0) }
	static var response: Self { InteractionPart(rawValue: 1) }

	func addMultipartFile(_ handle: InteractionHandle, fileURL: URL, contentType: String, partName: String, boundary: String?) throws {
		let result = pactffi_with_multipart_file_v2(
			handle,
			self,
			contentType.cString(using: .utf8),
			fileURL.path.cString(using: .utf8),
			partName.cString(using: .utf8),
			boundary?.cString(using: .utf8)
		)
		guard result.tag == StringResult_Ok else {
			let message = result.failed.map { String(cString: $0) } ?? ""
			result.failed.map { pactffi_string_delete($0) }
			throw PactInteraction.Error.invalidBody(message)
		}
	}
}
