import Foundation

/// Simple multipart/form-data builder for uploading files and fields.
public struct MultipartFormData {
    public struct Part {
        let name: String
        let filename: String?
        let mimeType: String?
        let data: Data
    }

    private(set) var boundary: String
    private var parts: [Part] = []

    public init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    /// Append a textual field to the form body.
    public mutating func addField(name: String, value: String) {
        let data = Data(value.utf8)
        let part = Part(name: name, filename: nil, mimeType: nil, data: data)
        parts.append(part)
    }

    /// Append a binary payload to the form body.
    public mutating func addData(
        name: String,
        filename: String,
        mimeType: String,
        data: Data
    ) {
        let part = Part(name: name, filename: filename, mimeType: mimeType, data: data)
        parts.append(part)
    }

    /// Build the final multipart body and corresponding `Content-Type` header value.
    public func build() -> (data: Data, contentType: String) {
        var body = Data()
        let lineBreak = "\r\n"
        for part in parts {
            body.append("--\(boundary)\(lineBreak)")
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename {
                disposition += "; filename=\"\(filename)\""
            }
            body.append("\(disposition)\(lineBreak)")

            if let mimeType = part.mimeType {
                body.append("Content-Type: \(mimeType)\(lineBreak)")
            }

            body.append(lineBreak)
            body.append(part.data)
            body.append(lineBreak)
        }
        body.append("--\(boundary)--\(lineBreak)")

        let contentType = "multipart/form-data; boundary=\(boundary)"
        return (body, contentType)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}


