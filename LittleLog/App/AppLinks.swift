import Foundation

/// Public web pages, hosted with Firebase Hosting (firebase/public).
enum AppLinks {
    static let privacyPolicy = URL(string: "https://little-log-be12c.web.app/privacy")!
    static let support = URL(string: "https://little-log-be12c.web.app/support")!

    /// Subscribing in Apple Calendar: the iPhone asks to subscribe when it opens a webcal link.
    static func appleCalendarFeed(babyID: String, key: String) -> URL? {
        URL(string: "webcal://little-log-be12c.web.app/cal/\(babyID)/\(key).ics")
    }

    /// Subscribing in Google Calendar ("Add calendar from URL").
    static func googleCalendarFeed(babyID: String, key: String) -> URL? {
        var components = URLComponents(string: "https://calendar.google.com/calendar/render")
        components?.queryItems = [URLQueryItem(name: "cid", value: "webcal://little-log-be12c.web.app/cal/\(babyID)/\(key).ics")]
        return components?.url
    }

    /// Subscribing in Outlook ("Add calendar from the web"), for Outlook.com and Hotmail accounts.
    static func outlookCalendarFeed(babyID: String, key: String) -> URL? {
        var components = URLComponents(string: "https://outlook.live.com/calendar/0/addfromweb")
        components?.queryItems = [
            URLQueryItem(name: "url", value: "https://little-log-be12c.web.app/cal/\(babyID)/\(key).ics"),
            URLQueryItem(name: "name", value: "Little Log appointments"),
        ]
        return components?.url
    }
}
