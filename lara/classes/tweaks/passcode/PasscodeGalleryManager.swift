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
    let url: String?
    let preview: String
    let sha256: String?
    let byteCount: Int?
    let demoURL: String?
    let demoSha256: String?
    let demoByteCount: Int?
    let authors: String?
    let version: String?

    var canInstall: Bool { url != nil && sha256 != nil && byteCount != nil }
    var hasAnimatedPreview: Bool {
        demoURL != nil && demoSha256 != nil && demoByteCount != nil
    }

    var authorLine: String {
        if let authors, !authors.isEmpty { return authors }
        return "Eagle"
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, url, preview, sha256, byteCount
        case demoURL, demoSha256, demoByteCount, authors, version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url)
        preview = try container.decode(String.self, forKey: .preview)
        sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
        byteCount = try container.decodeIfPresent(Int.self, forKey: .byteCount)
        demoURL = try container.decodeIfPresent(String.self, forKey: .demoURL)
        demoSha256 = try container.decodeIfPresent(String.self, forKey: .demoSha256)
        demoByteCount = try container.decodeIfPresent(Int.self, forKey: .demoByteCount)
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
        guard let package = theme.url else { return nil }
        guard let repoData = repos.first(where: { $0.data?.themes.contains(where: { $0.id == theme.id }) == true })?.data else { return nil }
        return URL(string: package, relativeTo: repoData.baseURL)?.absoluteURL
    }

    func animatedPreviewHTML(for theme: PasscodeGalleryTheme) async throws -> String {
        guard let rawURL = theme.demoURL,
              let expectedBytes = theme.demoByteCount,
              let expectedSHA = theme.demoSha256,
              let url = URL(string: rawURL), url.scheme == "https",
              url.host == "raw.githubusercontent.com",
              url.path.hasPrefix("/leonardob8777-bit/Eagle-Gallery/main/passcode/live/") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count == expectedBytes, data.count <= 512 * 1024,
              Data(SHA256.hash(data: data)).map({ String(format: "%02x", $0) }).joined() == expectedSHA.lowercased(),
              let html = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return html
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
        guard let fileURL = downloadURL(for: theme),
              let expectedBytes = theme.byteCount,
              let expectedSHA = theme.sha256 else { throw URLError(.badURL) }
        downloading.insert(theme.id)
        defer { downloading.remove(theme.id) }
        let (data, response) = try await URLSession.shared.data(from: fileURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard data.count == expectedBytes,
              data.count <= 50 * 1024 * 1024,
              Data(SHA256.hash(data: data)).map({ String(format: "%02x", $0) }).joined() == expectedSHA.lowercased() else {
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
                  let idValid = !theme.id.isEmpty &&
                      theme.id.unicodeScalars.allSatisfy({
                          CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-").contains($0)
                      })
                  let previewValid = URL(string: theme.preview, relativeTo: baseURL)?.absoluteURL.scheme == "https"
                  let packageValid: Bool
                  if let package = theme.url,
                     let digest = theme.sha256,
                     let size = theme.byteCount {
                      packageValid = size > 0 && size <= 50 * 1024 * 1024 &&
                          digest.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil &&
                          URL(string: package, relativeTo: baseURL)?.absoluteURL.scheme == "https"
                  } else {
                      packageValid = theme.url == nil && theme.sha256 == nil && theme.byteCount == nil
                  }
                  let demoValid: Bool
                  if let demo = theme.demoURL,
                     let digest = theme.demoSha256,
                     let size = theme.demoByteCount,
                     let demoURL = URL(string: demo) {
                      demoValid = size > 0 && size <= 512 * 1024 &&
                          digest.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil &&
                          demoURL.scheme == "https" &&
                          demoURL.host == "raw.githubusercontent.com" &&
                          demoURL.path.hasPrefix("/leonardob8777-bit/Eagle-Gallery/main/passcode/live/")
                  } else {
                      demoValid = theme.demoURL == nil && theme.demoSha256 == nil && theme.demoByteCount == nil
                  }
                  return idValid && previewValid && packageValid && demoValid &&
                      (theme.canInstall || theme.hasAnimatedPreview)
              }) else { throw CocoaError(.fileReadCorruptFile) }
        return PasscodeRepoData(name: parsed.repo_name, author: parsed.repo_author, icon: parsed.repo_icon, themes: parsed.themes, baseURL: baseURL)
    }
}
