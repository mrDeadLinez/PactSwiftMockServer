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

}

public extension PactInteraction {

	struct ProviderState: Hashable {
		var description: String
		var name: String?
		var value: String?

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
			if let name = state.name, let value = state.value {
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
}
