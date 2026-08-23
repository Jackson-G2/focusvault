import Foundation

public struct AllowedYouTubeChannel: Equatable {
    public let name: String
    public let handle: String
    public let channelID: String

    public init(name: String, handle: String, channelID: String) {
        self.name = name
        self.handle = handle
        self.channelID = channelID
    }

    public var displayHandle: String {
        handle.hasPrefix("@") ? handle : "@\(handle)"
    }
}

public enum YouTubeChannelDefaults {
    /// Official channel IDs verified from YouTube canonical channel metadata.
    public static let channels = [
        AllowedYouTubeChannel(
            name: "Alex Hormozi",
            handle: "AlexHormozi",
            channelID: "UCUyDOdBWhC1MCxEjC46d-zw"
        ),
        AllowedYouTubeChannel(
            name: "MoreMozi",
            handle: "MoreMozi",
            channelID: "UCrvchO1h6lWZAuGaa1LqX9Q"
        )
    ]
}
