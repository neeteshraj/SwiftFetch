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
        let segments = makeSegments()
        var body = Data()
        for segment in segments {
            body.append(segment)
        }
        return (body, contentTypeHeader)
    }

    /// Build a streaming multipart body to avoid buffering the entire payload at once.
    public func buildStream() -> (stream: InputStream, contentType: String, contentLength: Int64) {
        let segments = makeSegments()
        let length = segments.reduce(into: Int64(0)) { partial, data in
            partial += Int64(data.count)
        }
        let stream = MultipartBodyStream(segments: segments)
        return (stream, contentTypeHeader, length)
    }

    private var contentTypeHeader: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    private func makeSegments() -> [Data] {
        var segments: [Data] = []
        let lineBreak = "\r\n"
        for part in parts {
            var header = Data()
            header.append("--\(boundary)\(lineBreak)")
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename {
                disposition += "; filename=\"\(filename)\""
            }
            header.append("\(disposition)\(lineBreak)")
            if let mimeType = part.mimeType {
                header.append("Content-Type: \(mimeType)\(lineBreak)")
            }
            header.append(lineBreak)
            segments.append(header)
            segments.append(part.data)
            segments.append(Data(lineBreak.utf8))
        }
        let closing = "--\(boundary)--\(lineBreak)"
        segments.append(Data(closing.utf8))
        return segments
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

/// Simple `InputStream` that reads sequential `Data` segments.
private final class MultipartBodyStream: InputStream {
    private let segments: [Data]
    private var segmentIndex: Int = 0
    private var offset: Int = 0
    private var statusValue: Stream.Status = .notOpen

    init(segments: [Data]) {
        self.segments = segments
        super.init(data: Data())
    }

    override var hasBytesAvailable: Bool {
        switch statusValue {
        case .notOpen, .open, .reading:
            return segmentIndex < segments.count
        default:
            return false
        }
    }

    override var streamStatus: Stream.Status {
        statusValue
    }

    override func open() {
        guard statusValue == .notOpen else { return }
        statusValue = .open
    }

    override func close() {
        statusValue = .closed
    }

    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        if statusValue == .notOpen {
            open()
        }
        guard hasBytesAvailable else {
            statusValue = .atEnd
            return 0
        }
        statusValue = .reading

        var bytesCopied = 0
        while bytesCopied < len && segmentIndex < segments.count {
            let segment = segments[segmentIndex]
            let remaining = segment.count - offset
            let toCopy = min(len - bytesCopied, remaining)
            segment.copyBytes(to: buffer.advanced(by: bytesCopied), from: offset..<(offset + toCopy))
            bytesCopied += toCopy
            offset += toCopy

            if offset >= segment.count {
                segmentIndex += 1
                offset = 0
            }
        }

        if segmentIndex >= segments.count {
            statusValue = .atEnd
        } else {
            statusValue = .open
        }

        return bytesCopied
    }

    override func getBuffer(_ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, length len: UnsafeMutablePointer<Int>) -> Bool {
        false
    }
}


