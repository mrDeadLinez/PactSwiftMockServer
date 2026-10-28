// swift-tools-version:5.7
import PackageDescription

let package = Package(

	name: "PactSwiftMockServer",

	platforms: [
		.macOS(.v13),
		.iOS(.v15),
		.tvOS(.v12)
	],

	products: [
		.library(
			name: "PactSwiftMockServer",
			targets: ["PactSwiftMockServer"]
		)
	],

	targets: [
		.binaryTarget(
			name: "PactSwiftMockServer",
			path: "PactSwiftMockServer.xcframework"
		)
	],

	swiftLanguageVersions: [.v5]
)
