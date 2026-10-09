import Foundation

/// Generates exactly one image using Replicate's FLUX Schnell model.
public struct ImageGenerationRequest: Sendable {
    public var prompt: String
    public var aspectRatio: ImageAspectRatio
    public var outputFormat: ImageOutputFormat

    public init(
        prompt: String, aspectRatio: ImageAspectRatio = .square,
        outputFormat: ImageOutputFormat = .png
    ) {
        self.prompt = prompt
        self.aspectRatio = aspectRatio
        self.outputFormat = outputFormat
    }
}

public enum ImageAspectRatio: String, Codable, CaseIterable, Sendable {
    case square = "1:1"
    case landscape = "16:9"
    case portrait = "9:16"
    case landscapeThreeTwo = "3:2"
    case portraitTwoThree = "2:3"
    case landscapeFourThree = "4:3"
    case portraitThreeFour = "3:4"
    case landscapeFiveFour = "5:4"
    case portraitFourFive = "4:5"
    case ultrawide = "21:9"
}

public enum ImageOutputFormat: String, Codable, CaseIterable, Sendable {
    case png, jpg, webp
}

/// The URL is temporary provider storage; persist imageData for lasting access.
public struct ImageGenerationResponse: Equatable, Sendable {
    public let id: String
    public let imageURL: URL
    public let imageData: Data
    public let outputFormat: ImageOutputFormat

    public init(id: String, imageURL: URL, imageData: Data, outputFormat: ImageOutputFormat) {
        self.id = id
        self.imageURL = imageURL
        self.imageData = imageData
        self.outputFormat = outputFormat
    }
}
