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

public final class Interaction: PactInteraction {

	public typealias RequestBuilder = (Request) throws -> Void
	public typealias ResponseBuilder = (Response) throws -> Void

	public struct Request: HeaderBuilder, BodyBuilder, QueryBuilder {
		private let handle: InteractionHandle

		init(handle: InteractionHandle) {
			self.handle = handle
		}

		@discardableResult
		public func queryParam(name: String, values: [String]) throws -> Self {
			for (index, value) in values.enumerated() {
				guard pactffi_with_query_parameter_v2(handle, name.cString(using: .utf8), index, value.cString(using: .utf8)) else {
					throw Error.canNotBeModified
				}
			}

			return self
		}

		@discardableResult
		public func header(_ name: String, values: [String]) throws -> Self {
			for (index, value) in values.enumerated() {
				guard pactffi_with_header_v2(handle, .request, name.cString(using: .utf8), index, value.cString(using: .utf8)) else {
					throw Error.canNotBeModified
				}
			}

			return self
		}

		@discardableResult
		public func body(_ body: String? = nil, contentType: String? = nil) throws -> Self {
			guard pactffi_with_body(handle, .request, (contentType ?? "text/plain").cString(using: .utf8), body?.cString(using: .utf8)) else {
				throw Error.canNotBeModified
			}

			return self
		}

		@discardableResult
		public func body(_ body: Data, contentType: String) throws -> Self {
			try withBinaryBody(handle, .request, body, contentType: contentType)
			return self
		}
	}

	public struct Response: HeaderBuilder, BodyBuilder {
		private let handle: InteractionHandle

		init(handle: InteractionHandle) {
			self.handle = handle
		}

		/// Configures the response for the Interaction.
		///
		/// Throws if the interaction or Pact can't be modified (i.e. the mock server for it has already started).
		///
		/// - Parameters:
		///   - status - the response status. Defaults to 200.
		///
		@discardableResult
		public func status(_ status: Int) throws -> Self {
			guard pactffi_response_status(handle, UInt16(status)) else {
				throw Error.canNotBeModified
			}

			return self
		}

		/// Configures the response status for the Interaction, optionally with a matching rule and generator.
		///
		/// To include a matching rule, pass the matching rule JSON format with the example status as `value`. I.e.
		///
		/// ```
		/// let status = #"{"value":404, "pact:matcher:type":"statusCode", "status":"clientError"}"#
		/// response.status(status)
		/// ```
		/// See [IntegrationJson.md](https://github.com/pact-foundation/pact-reference/blob/master/rust/pact_ffi/IntegrationJson.md)
		///
		/// - Throws: ``Interaction/Error/canNotBeModified`` if the interaction or Pact can't be modified (i.e. the mock server for it has already started).
		@discardableResult
		public func status(_ status: String) throws -> Self {
			guard pactffi_response_status_v2(handle, status.cString(using: .utf8)) else {
				throw Error.canNotBeModified
			}

			return self
		}

		@discardableResult
		public func header(_ name: String, values: [String]) throws -> Self {
			for (index, value) in values.enumerated() {
				guard pactffi_with_header_v2(handle, .response, name.cString(using: .utf8), index, value.cString(using: .utf8)) else {
					throw Error.canNotBeModified
				}
			}

			return self
		}

		/// Adds the body for the ``Interaction``.
		///
		/// For JSON payloads, matching rules can be embedded in the `body`. See
		/// [IntegrationJson.md](https://github.com/pact-foundation/pact-reference/blob/master/rust/pact_ffi/IntegrationJson.md).
		///
		/// - Throws: ``Interaction/Error/canNotBeModified`` if the interaction or Pact can't be modified (i.e. the mock server for it has already started).
		/// - Parameters:
		///   - contentType:
		///       The content type of the body. Defaults to `text/plain`. Ignored if a content-type header is already set.
		///       If `nil`, or can't be parsed, it will set the content type as TEXT.
		///   - body: The body contents. If the `body` is `nil` it will set the body contents as null.
		///
		@discardableResult
		public func body(_ body: String? = nil, contentType: String? = nil) throws -> Self {
			guard pactffi_with_body(handle, .response, (contentType ?? "text/plain").cString(using: .utf8), body?.cString(using: .utf8)) else {
				throw Error.canNotBeModified
			}

			return self
		}

		/// Adds a binary body for the ``Interaction``, matched byte for byte.
		///
		/// - Throws: ``Interaction/Error/canNotBeModified`` if the interaction or Pact can't be modified (i.e. the mock server for it has already started).
		/// - Parameters:
		///   - body: The raw body bytes.
		///   - contentType: The content type of the body. Ignored if a content-type header is already set.
		///
		@discardableResult
		public func body(_ body: Data, contentType: String) throws -> Self {
			try withBinaryBody(handle, .response, body, contentType: contentType)
			return self
		}
	}

	/// HTTP Method for an ``Interaction``.
	public enum HTTPMethod: String {
		case GET, HEAD, POST, PUT, PATCH, DELETE, TRACE, CONNECT, OPTIONS
	}

	internal init(pactHandle: PactHandle, description: String) {
		super.init(handle: pactffi_new_interaction(pactHandle, description.cString(using: .utf8)))
	}

	/// Configures the request for the ``Interaction``.
	///
	/// - Throws: ``Error`` if the interaction or Pact can't be modified (i.e. the mock server for it has already started)
	/// - Parameters:
	///   - method: The request method. Defaults to ``HTTPMethod/GET``.
	///   - path: The request path. Defaults to `"/"`.
	///   - builder: A ``RequestBuilder`` closure.
	///
	@discardableResult
	public func withRequest(method: HTTPMethod = .GET, path: String = "/", builder: RequestBuilder = { _ in }) throws -> Self {
		guard pactffi_with_request(handle, method.rawValue.cString(using: .utf8), path.cString(using: .utf8)) else {
			throw Error.canNotBeModified
		}

		let request = Request(handle: handle)
		try builder(request)

		return self
	}

	@discardableResult
	public func willRespond(with status: Int, builder: ResponseBuilder = { _ in }) throws -> Self {
		let response = Response(handle: handle)
		try response.status(status)

		try builder(response)

		return self
	}

}
