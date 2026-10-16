import XCTest
@testable import FocusTubeCore

struct StubHTTP: HTTPFetching {
    var responses: [String: (Data, Int)] = [:]
    var fail = false
    func get(_ url: URL) async throws -> (data: Data, status: Int) {
        if fail { throw URLError(.notConnectedToInternet) }
        guard let r = responses[url.absoluteString] else { return (Data(), 404) }
        return (r.0, r.1)
    }
}

enum FeedFixtures {
    static let channel = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/" xmlns="http://www.w3.org/2005/Atom">
     <link rel="self" href="http://www.youtube.com/feeds/videos.xml?channel_id=UC_x5XG1OV2P6uZZ5FSM9Ttw"/>
     <id>yt:channel:_x5XG1OV2P6uZZ5FSM9Ttw</id>
     <yt:channelId>UC_x5XG1OV2P6uZZ5FSM9Ttw</yt:channelId>
     <title>Google for Developers</title>
     <author><name>Google for Developers</name><uri>https://www.youtube.com/channel/UC_x5XG1OV2P6uZZ5FSM9Ttw</uri></author>
     <published>2007-08-23T00:34:43+00:00</published>
     <entry>
      <id>yt:video:dQw4w9WgXcQ</id>
      <yt:videoId>dQw4w9WgXcQ</yt:videoId>
      <yt:channelId>UC_x5XG1OV2P6uZZ5FSM9Ttw</yt:channelId>
      <title>Long talk &amp; demo</title>
      <link rel="alternate" href="https://www.youtube.com/watch?v=dQw4w9WgXcQ"/>
      <author><name>Google for Developers</name><uri>https://www.youtube.com/channel/UC_x5XG1OV2P6uZZ5FSM9Ttw</uri></author>
      <published>2026-10-15T16:00:06+00:00</published>
      <updated>2026-10-16T01:02:03+00:00</updated>
      <media:group>
       <media:title>Long talk &amp; demo</media:title>
       <media:content url="https://www.youtube.com/v/dQw4w9WgXcQ?version=3" type="application/x-shockwave-flash" width="640" height="390"/>
       <media:thumbnail url="https://i2.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg" width="480" height="360"/>
       <media:description>Line one
    Line two</media:description>
       <media:community><media:starRating count="10" average="5.00" min="1" max="5"/><media:statistics views="123"/></media:community>
      </media:group>
     </entry>
     <entry>
      <id>yt:video:aqz-KE-bpKQ</id>
      <yt:videoId>aqz-KE-bpKQ</yt:videoId>
      <yt:channelId>UC_x5XG1OV2P6uZZ5FSM9Ttw</yt:channelId>
      <title>A short</title>
      <link rel="alternate" href="https://www.youtube.com/shorts/aqz-KE-bpKQ"/>
      <author><name>Google for Developers</name></author>
      <published>2026-10-14T10:00:00+00:00</published>
      <media:group><media:description></media:description></media:group>
     </entry>
     <entry>
      <title>Broken entry without id</title>
     </entry>
    </feed>
    """
    static let playlist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/" xmlns="http://www.w3.org/2005/Atom">
     <id>yt:playlist:PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf</id>
     <yt:playlistId>PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf</yt:playlistId>
     <yt:channelId>UC_x5XG1OV2P6uZZ5FSM9Ttw</yt:channelId>
     <title>My Playlist</title>
     <author><name>Someone</name></author>
     <entry>
      <yt:videoId>dQw4w9WgXcQ</yt:videoId>
      <yt:channelId>UCaaaaaaaaaaaaaaaaaaaaaa</yt:channelId>
      <title>Item</title>
      <link rel="alternate" href="https://www.youtube.com/watch?v=dQw4w9WgXcQ"/>
      <author><name>Other Channel</name></author>
      <published>2026-01-01T00:00:00.123+00:00</published>
     </entry>
    </feed>
    """
}

final class PublicFeedTests: XCTestCase {
    func testParsesChannelFeed() throws {
        let feed = try AtomFeedParser.parse(Data(FeedFixtures.channel.utf8))
        XCTAssertEqual(feed.title, "Google for Developers")
        XCTAssertEqual(feed.channelID, "UC_x5XG1OV2P6uZZ5FSM9Ttw")
        XCTAssertNil(feed.playlistID)
        XCTAssertEqual(feed.authorName, "Google for Developers")
        XCTAssertEqual(feed.entries.count, 2)
        XCTAssertEqual(feed.skippedEntries, 1)
        let e = feed.entries[0]
        XCTAssertEqual(e.videoID, "dQw4w9WgXcQ")
        XCTAssertEqual(e.title, "Long talk & demo")
        XCTAssertEqual(e.channelTitle, "Google for Developers")
        XCTAssertEqual(e.thumbnailURL?.absoluteString, "https://i2.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
        XCTAssertEqual(e.summary, "Line one\nLine two")
        XCTAssertEqual(e.published, ISO8601DateFormatter().date(from: "2026-10-15T16:00:06Z"))
        XCTAssertFalse(e.isShortsLink)
        XCTAssertTrue(feed.entries[1].isShortsLink)
        XCTAssertNil(feed.entries[1].summary)
        let v = e.videoSummary
        XCTAssertEqual(v.channelID, "UC_x5XG1OV2P6uZZ5FSM9Ttw")
        XCTAssertNil(v.durationSeconds)
    }

    func testParsesPlaylistFeedWithFractionalDates() throws {
        let feed = try AtomFeedParser.parse(Data(FeedFixtures.playlist.utf8))
        XCTAssertEqual(feed.playlistID, "PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf")
        XCTAssertEqual(feed.entries.first?.channelTitle, "Other Channel")
        XCTAssertNotNil(feed.entries.first?.published)
    }

    func testMalformedXMLThrows() {
        XCTAssertThrowsError(try AtomFeedParser.parse(Data("<feed><entry>".utf8)))
        XCTAssertThrowsError(try AtomFeedParser.parse(Data("{\"not\":\"xml\"}".utf8)))
        XCTAssertThrowsError(try AtomFeedParser.parse(Data("<html><body/></html>".utf8)))
    }

    func testEndpoints() {
        XCTAssertEqual(PublicEndpoints.channelFeed(YouTubeChannelID("UC_x5XG1OV2P6uZZ5FSM9Ttw")!).absoluteString,
                       "https://www.youtube.com/feeds/videos.xml?channel_id=UC_x5XG1OV2P6uZZ5FSM9Ttw")
        XCTAssertEqual(PublicEndpoints.oEmbed(YouTubeVideoID("dQw4w9WgXcQ")!).absoluteString,
                       "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v%3DdQw4w9WgXcQ&format=json")
    }

    func testFeedClientMapsStatuses() async {
        let ch = YouTubeChannelID("UC_x5XG1OV2P6uZZ5FSM9Ttw")!
        let url = PublicEndpoints.channelFeed(ch).absoluteString
        let okClient = PublicFeedClient(http: StubHTTP(responses: [url: (Data(FeedFixtures.channel.utf8), 200)]))
        let feed = try? await okClient.channel(ch)
        XCTAssertEqual(feed?.entries.count, 2)
        func err(_ http: StubHTTP) async -> PublicSourceError? {
            do { _ = try await PublicFeedClient(http: http).channel(ch); return nil } catch { return error }
        }
        let e1 = await err(StubHTTP())
        XCTAssertEqual(e1, .notFound)
        let e2 = await err(StubHTTP(responses: [url: (Data(), 500)]))
        XCTAssertEqual(e2, .server(500))
        let e3 = await err(StubHTTP(fail: true))
        XCTAssertEqual(e3, .transport)
        let e4 = await err(StubHTTP(responses: [url: (Data("garbage".utf8), 200)]))
        XCTAssertEqual(e4, .malformed)
    }

    func testOEmbed() async throws {
        let id = YouTubeVideoID("dQw4w9WgXcQ")!
        let url = PublicEndpoints.oEmbed(id).absoluteString
        let json = #"{"title":"Never","author_name":"Rick","author_url":"https://www.youtube.com/@RickAstley","type":"video","height":113,"width":200,"thumbnail_url":"https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg","html":"<iframe></iframe>"}"#
        let m = try await OEmbedClient(http: StubHTTP(responses: [url: (Data(json.utf8), 200)])).metadata(for: id)
        XCTAssertEqual(m.title, "Never")
        XCTAssertEqual(m.authorName, "Rick")
        XCTAssertFalse(m.isPortrait)
        let shortJSON = #"{"title":"S","author_name":"A","width":113,"height":200}"#
        let s = try await OEmbedClient(http: StubHTTP(responses: [url: (Data(shortJSON.utf8), 200)])).metadata(for: id)
        XCTAssertTrue(s.isPortrait)
        do {
            _ = try await OEmbedClient(http: StubHTTP(responses: [url: (Data(), 401)])).metadata(for: id)
            XCTFail()
        } catch { XCTAssertEqual(error, .unauthorized) }
        do {
            _ = try await OEmbedClient(http: StubHTTP(responses: [url: (Data("{}".utf8), 200)])).metadata(for: id)
            XCTFail()
        } catch { XCTAssertEqual(error, .malformed) }
    }
}
