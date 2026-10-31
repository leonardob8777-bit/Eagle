//
//  PasscodeGalleryManager.swift
//  lara
//
//  Created by neonmodder123 on 20/05/2026.
//

import Foundation
import SwiftUI
import Combine
import CryptoKit

let defaultPasscodeRepoURL = "https://raw.githubusercontent.com/leonardob8777-bit/Eagle-Gallery/main/catalogs/passcode-v1.json"

struct PasscodeGalleryTheme: Identifiable, Decodable, Equatable {
    let id: String
    let name: String
    let description: String
    let url: String
    let preview: String
    let sha256: String
    let byteCount: Int
    let authors: String?
    let version: String?

    var authorLine: String {
        if let authors, !authors.isEmpty { return authors }
        return "Eagle"
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, url, preview, sha256, byteCount, authors, version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        url = try container.decode(String.self, forKey: .url)
        preview = try container.decode(String.self, forKey: .preview)
        sha256 = try container.decode(String.self, forKey: .sha256)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        authors = try container.decodeIfPresent(String.self, forKey: .authors)
        version = try container.decodeIfPresent(String.self, forKey: .version)
    }
}

struct PasscodeRepoData: Identifiable {
    var id: String { name }
    let name: String
    let author: String?
    let icon: String?
    let themes: [PasscodeGalleryTheme]
    let baseURL: URL
}

struct PasscodeRepoState: Identifiable {
    var id: String { url }
    let url: String
    var isLoading: Bool
    var error: String?
    var data: PasscodeRepoData?
}

@MainActor
final class PasscodeGalleryManager: ObservableObject {
    static let shared = PasscodeGalleryManager()

    @Published var repos: [PasscodeRepoState] = []
    @Published var downloading: Set<String> = []

    private let repoURLs = [defaultPasscodeRepoURL]

    var allThemes: [PasscodeGalleryTheme] { repos.flatMap { $0.data?.themes ?? [] } }
    var themes: [PasscodeGalleryTheme] { allThemes }
    var isLoading: Bool { repos.contains { $0.isLoading } }
    var loadError: String? { repos.first { $0.error != nil }?.error }

    func previewURL(for theme: PasscodeGalleryTheme) -> URL? {
        guard let repoData = repos.first(where: { $0.data?.themes.contains(where: { $0.id == theme.id }) == true })?.data else { return nil }
        if theme.preview.hasPrefix("http") { return URL(string: theme.preview) }
        return repoData.baseURL.appendingPathComponent(theme.preview)
    }

    func downloadURL(for theme: PasscodeGalleryTheme) -> URL? {
        guard let repoData = repos.first(where: { $0.data?.themes.contains(where: { $0.id == theme.id }) == true })?.data else { return nil }
        if theme.url.hasPrefix("http") { return URL(string: theme.url) }
        return repoData.baseURL.appendingPathComponent(theme.url)
    }

    func isDownloading(_ theme: PasscodeGalleryTheme) -> Bool { downloading.contains(theme.id) }

    func loadThemes(forceRefresh: Bool = false) async {
        await refreshRepos(forceRefresh: forceRefresh)
    }

    func refreshRepos(forceRefresh: Bool = false) async {
        let previous = Dictionary(uniqueKeysWithValues: repos.map { ($0.url, $0.data) })
        repos = repoURLs.map {
            PasscodeRepoState(url: $0, isLoading: true, error: nil, data: previous[$0] ?? nil)
        }

        await withTaskGroup(of: (String, Result<PasscodeRepoData, Error>).self) { group in
            for url in repoURLs {
                group.addTask {
                    do {
                        return (url, .success(try await self.fetchRepo(url, forceRefresh: forceRefresh)))
                    } catch {
                        return (url, .failure(error))
                    }
                }
            }
            for await (url, result) in group {
                guard let idx = repos.firstIndex(where: { $0.url == url }) else { continue }
                repos[idx].isLoading = false
                switch result {
                case .success(let data): repos[idx].data = data
                case .failure(let error): repos[idx].error = error.localizedDescription
                }
            }
        }
    }

    func downloadAndImport(_ theme: PasscodeGalleryTheme) async throws -> URL {
        guard let fileURL = downloadURL(for: theme) else { throw URLError(.badURL) }
        downloading.insert(theme.id)
        defer { downloading.remove(theme.id) }
        let (data, response) = try await URLSession.shared.data(from: fileURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard data.count == theme.byteCount,
              data.count <= 50 * 1024 * 1024,
              Data(SHA256.hash(data: data)).map({ String(format: "%02x", $0) }).joined() == theme.sha256.lowercased() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let dest = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(theme.id + ".passthm")
        try data.write(to: dest, options: .atomic)
        return dest
    }

    private func fetchRepo(_ urlString: String, forceRefresh: Bool = false) async throws -> PasscodeRepoData {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        if forceRefresh { req.cachePolicy = .reloadIgnoringLocalCacheData }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 1024 * 1024 else { throw URLError(.badServerResponse) }
        let baseURL = url.deletingLastPathComponent()

        struct RepoJSON: Decodable {
            let schemaVersion: Int
            let repo_name: String
            let repo_author: String?
            let repo_icon: String?
            let themes: [PasscodeGalleryTheme]
        }
        let parsed = try JSONDecoder().decode(RepoJSON.self, from: data)
        guard parsed.schemaVersion == 1, parsed.themes.count <= 1000,
              Set(parsed.themes.map(\.id)).count == parsed.themes.count,
              parsed.themes.allSatisfy({ theme in
                  !theme.id.isEmpty &&
                  theme.id.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-").contains($0) }) &&
                  theme.byteCount > 0 && theme.byteCount <= 50 * 1024 * 1024 &&
                  theme.sha256.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil &&
                  URL(string: theme.url, relativeTo: baseURL)?.absoluteURL.scheme == "https" &&
                  URL(string: theme.preview, relativeTo: baseURL)?.absoluteURL.scheme == "https"
              }) else { throw CocoaError(.fileReadCorruptFile) }
        return PasscodeRepoData(name: parsed.repo_name, author: parsed.repo_author, icon: parsed.repo_icon, themes: parsed.themes, baseURL: baseURL)
    }
}
