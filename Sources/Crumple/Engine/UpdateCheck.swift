import Foundation

/// Looks for a newer release on GitHub. Dormant until `CrumpleUpdateRepository` ("owner/repo")
/// is filled in in Info.plist; until then nothing is ever sent over the network.
enum UpdateCheck {
    struct Release: Equatable {
        let version: String
        let page: URL
        let notes: String
    }

    enum Outcome: Equatable {
        case notConfigured
        case upToDate
        case available(Release)
        case failed(String)
    }

    static var repository: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "CrumpleUpdateRepository") as? String,
              value.split(separator: "/").count == 2 else { return nil }
        return value
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static func check() async -> Outcome {
        guard let repository, let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            return .notConfigured
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        struct Payload: Decodable {
            let tag_name: String
            let html_url: URL
            let body: String?
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .failed(String(localized: "暂时查不到发布信息")) }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
            guard isNewer(version, than: currentVersion) else { return .upToDate }
            return .available(Release(version: version, page: payload.html_url, notes: payload.body ?? ""))
        } catch {
            return .failed(String(localized: "连不上网络，稍后再试"))
        }
    }

    /// "1.10" is newer than "1.9"; missing parts count as 0, so "1.0" equals "1".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
