# SwiftFetch

SwiftFetch is a lightweight networking helper built on top of `URLSession` and Swift Concurrency. It offers a small facade for configuring a base URL, composing requests, and decoding JSON with sensible error handling.

## Features
- Base URL configuration with default headers
- Typed HTTP method support and request/response wrappers
- Async/await networking using `URLSession`
- JSON decoding helper with consistent error mapping
- Multipart form-data builder for file uploads
- Test-friendly design via injectable `URLSession`

## Installation
Add SwiftFetch to your `Package.swift` dependencies:
```swift
dependencies: [
    .package(url: "https://github.com/neeteshraj/SwiftFetch.git", from: "1.0.0")
]
```
Then add `SwiftFetch` to your target:
```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "SwiftFetch", package: "SwiftFetch")
    ]
)
```

## Usage Example
```swift
import SwiftFetch

SwiftFetch.configure(baseURL: URL(string: "https://api.example.com")!)

struct User: Decodable {
    let id: Int
    let name: String
}

let users: [User] = try await SwiftFetch.getJSON("/users")

// Multipart upload example
var form = MultipartFormData()
form.addField(name: "description", value: "Profile picture")
form.addData(
    name: "file",
    filename: "avatar.jpg",
    mimeType: "image/jpeg",
    data: Data(/* file bytes */)
)

let (body, contentType) = form.build()
let uploadRequest = FetchRequest(
    url: URL(string: "/upload")!,
    method: .post,
    headers: ["Content-Type": contentType],
    body: body
)
let response = try await SwiftFetch.client.perform(uploadRequest)
print("Upload status:", response.statusCode)
```

## License
MIT License

