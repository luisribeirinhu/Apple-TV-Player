import Foundation
import Testing
@testable import Bro_Player

struct XMLTVTimingAndMappingTests {
    @Test(arguments: [
        ("20260101120000 +0130", "20260101103000 +0000"),
        ("20260101120000 -0500", "20260101170000 +0000"),
        ("20260101001500 +0100", "20251231231500 +0000"),
        ("20260101120000", "20260101120000 +0000")
    ])
    func honorsXMLTVTimeZoneOffsets(input: String, utc: String) throws {
        let value = try #require(ProgramGuideParser.xmlTVDate(from: input))
        #expect(value == ProgramGuideParser.xmlTVDate(from: utc))
    }

    @Test(arguments: ["", "2026", "20260101120000 +2500", "20260101120000 +0060", "20260101120000 nonsense"])
    func rejectsMalformedXMLTVOffsets(_ input: String) {
        #expect(ProgramGuideParser.xmlTVDate(from: input) == nil)
    }

    @Test func prefersXMLTVIDOverConflictingDisplayName() {
        let wrong = ProgramGuide(channel: .init(id: "wrong", displayName: "Canal", iconURL: nil), programs: [])
        let right = ProgramGuide(channel: .init(id: "right", displayName: "Outro nome", iconURL: nil), programs: [])
        let stream = PlaylistParser.Stream(title: "Canal", url: "https://example.invalid/live", tvgLogo: nil, tvgID: "right", tvgName: "Canal", groupTitle: nil)
        #expect(PlaylistService.matchingGuide(for: stream, in: [wrong, right]) == right)
    }

    @Test func retainsNameFallbackWhenIDIsAbsent() {
        let guide = ProgramGuide(channel: .init(id: "xml-id", displayName: "Canal", iconURL: nil), programs: [])
        let stream = PlaylistParser.Stream(title: "Canal HD", url: "https://example.invalid/live", tvgLogo: nil, tvgID: nil, tvgName: nil, groupTitle: nil)
        #expect(PlaylistService.matchingGuide(for: stream, in: [guide]) == guide)
    }

#if os(tvOS)
    @Test func changesOnlyEPGHeaderPreservingChannelsAndOrdering() async throws {
        let data = Data("""
        #EXTM3U url-tvg="https://example.invalid/old.xml" x-tvg-url="https://example.invalid/backup.xml" tvg-logo="logo"
        #EXTINF:-1 tvg-id="one" group-title="A",One
        https://example.invalid/one
        #EXTINF:-1 tvg-id="two" group-title="B",Two
        https://example.invalid/two
        """.utf8)
        let original = try await PlaylistParser(data: data).parse()
        let updated = try await PlaylistParser(data: data).replacingProgramGuideSource("https://example.invalid/new.xml")
        let parsed = try await PlaylistParser(data: updated).parse()
        #expect(parsed.first?.tvgURL == "https://example.invalid/new.xml")
        #expect(parsed.first?.xTvgURL == nil)
        #expect(parsed.first?.tvgLogo == "logo")
        #expect(parsed.first?.streams == original.first?.streams)
        let removed = try await PlaylistParser(data: updated).replacingProgramGuideSource("")
        let withoutGuide = try await PlaylistParser(data: removed).parse()
        #expect(withoutGuide.first?.tvgURL == nil)
    }
#endif
}
