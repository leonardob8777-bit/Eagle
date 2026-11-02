import Combine
import Foundation
import SwiftUI

/// Public like counts for Eagle's galleries, and how many people have Eagle open, from the
/// eagle-likes Worker on Cloudflare.
///
/// The heart in each gallery stays a local favourite exactly as before; it also tells the server,
/// which keeps one like per item and per iPhone. The iPhone is known only by a random ID created
/// here, with no personal data. Without a connection the favourite still works and the count is
/// simply not shown.
@MainActor
final class EagleLikes: ObservableObject {
    static let shared = EagleLikes()

    enum Kind: String, CaseIterable {
        case wallpaper, passcode, dock, island
    }

    private static let baseURL = URL(string: "https://eagle-likes.eagle-likes.workers.dev")!
    private static let deviceKey = "eagle.likes.deviceID"
    private static let backfillKey = "eagle.likes.backfilled."
    /// Counts are fetched again only after this long; the server caches them for 30 s anyway.
    private static let refreshInterval: TimeInterval = 60
    /// Favourites saved before likes existed are sent once, at most this many per gallery.
    private static let backfillLimit = 20

    /// People with Eagle open right now (this iPhone included); nil until the server answers.
    @Published private(set) var online: Int?
    private var heartbeat: Task<Void, Never>?
    /// The server counts a device as online for three minutes after its last heartbeat.
    private static let heartbeatInterval: UInt64 = 60

    @Published private(set) var counts: [Kind: [String: Int]] = [:]
    /// The counts as the server last sent them, for ordering galleries. Unlike `counts` it does not
    /// move when this iPhone taps a heart, so the grid does not rearrange under the finger.
    @Published private(set) var ranking: [Kind: [String: Int]] = [:]
    private var lastRefresh: [Kind: Date] = [:]

    /// This iPhone's anonymous ID, created once.
    static var deviceID: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: deviceKey), UUID(uuidString: existing) != nil {
            return existing
        }
        let created = UUID().uuidString.lowercased()
        defaults.set(created, forKey: deviceKey)
        return created
    }

    /// The server accepts lowercase letters, digits and hyphens; any other ID is mapped onto that.
    static func itemKey(_ id: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        let mapped = String(id.lowercased().map { allowed.contains($0) ? $0 : "-" })
        return String(mapped.prefix(80))
    }

    func count(_ kind: Kind, _ id: String) -> Int {
        counts[kind]?[Self.itemKey(id)] ?? 0
    }

    /// Loads a gallery's counts, and sends that gallery's older favourites the first time.
    func refresh(_ kind: Kind, favorites: Set<String> = []) async {
        await backfillIfNeeded(kind, favorites: favorites)
        if let last = lastRefresh[kind], Date().timeIntervalSince(last) < Self.refreshInterval { return }
        lastRefresh[kind] = Date()

        var components = URLComponents(url: Self.baseURL.appendingPathComponent("v1/counts"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "kind", value: kind.rawValue)]
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        struct Response: Decodable { let counts: [String: Int] }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 512 * 1024 else { return }
            let received = try JSONDecoder().decode(Response.self, from: data).counts
            counts[kind] = received
            ranking[kind] = received
        } catch {
            lastRefresh[kind] = nil
        }
    }

    /// Records a like (or removes it). The count moves at once and is then corrected by the server.
    func setLiked(_ kind: Kind, _ id: String, liked: Bool) {
        let key = Self.itemKey(id)
        let previous = counts[kind]?[key] ?? 0
        counts[kind, default: [:]][key] = max(0, previous + (liked ? 1 : -1))

        Task {
            if let confirmed = await send(kind, key, liked: liked) {
                counts[kind, default: [:]][key] = confirmed
            } else {
                counts[kind, default: [:]][key] = previous
            }
        }
    }

    private func send(_ kind: Kind, _ key: String, liked: Bool) async -> Int? {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("v1/like"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["kind": kind.rawValue, "item": key, "device": Self.deviceID, "liked": liked]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        struct Response: Decodable { let count: Int }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(Response.self, from: data).count
        } catch {
            return nil
        }
    }

    /// Starts the once-a-minute "Eagle is open" heartbeat; called when the app comes to the front.
    func startPresence() {
        guard heartbeat == nil else { return }
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                await self?.beat()
                try? await Task.sleep(nanoseconds: Self.heartbeatInterval * 1_000_000_000)
            }
        }
    }

    /// Stops the heartbeat when the app goes to the background.
    func stopPresence() {
        heartbeat?.cancel()
        heartbeat = nil
    }

    private func beat() async {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("v1/presence"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["device": Self.deviceID])

        struct Response: Decodable { let online: Int }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            online = try JSONDecoder().decode(Response.self, from: data).online
        } catch {
            // Keeps the last number; the next heartbeat tries again.
        }
    }

    private var backfilling: Set<Kind> = []

    /// Marked done only when every favourite arrived; otherwise it runs again next time. Sending a
    /// like twice never counts twice on the server, so a retry is harmless.
    private func backfillIfNeeded(_ kind: Kind, favorites: Set<String>) async {
        let flag = Self.backfillKey + kind.rawValue
        guard !favorites.isEmpty, !UserDefaults.standard.bool(forKey: flag),
              backfilling.insert(kind).inserted else { return }
        defer { backfilling.remove(kind) }

        var allSent = true
        for id in favorites.sorted().prefix(Self.backfillLimit) {
            if await send(kind, Self.itemKey(id), liked: true) == nil {
                allSent = false
                break
            }
        }
        if allSent { UserDefaults.standard.set(true, forKey: flag) }
        lastRefresh[kind] = nil
    }
}

extension EagleLikes {
    /// `items` from most to least liked, by the last counts from the server; items with the same
    /// count keep their catalogue order.
    func sortedByLikes<Item>(_ items: [Item], _ kind: Kind, id: (Item) -> String) -> [Item] {
        let table = ranking[kind] ?? [:]
        guard !table.isEmpty else { return items }
        return items.enumerated()
            .sorted { lhs, rhs in
                let left = table[Self.itemKey(id(lhs.element))] ?? 0
                let right = table[Self.itemKey(id(rhs.element))] ?? 0
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// The item for the HOT tag: the first of `ids` once sorted by likes (so it is always the first
    /// in the gallery), if it has at least one like.
    func hottest(_ kind: Kind, among ids: [String]) -> String? {
        guard let first = sortedByLikes(ids, kind, id: { $0 }).first,
              (ranking[kind]?[Self.itemKey(first)] ?? 0) > 0 else { return nil }
        return first
    }
}

/// The like control: a heart and the public count in a capsule, tapped to like or unlike. On artwork
/// it is glass with white text; elsewhere it sits on the card colour like Eagle's other buttons.
struct EagleLikeButton: View {
    let kind: EagleLikes.Kind
    let id: String
    let isLiked: Bool
    var onArtwork = true
    let action: () -> Void
    @ObservedObject private var likes = EagleLikes.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let count = likes.count(kind, id)
        let ink: Color = onArtwork ? .white : .primary
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: onArtwork ? 13 : 16, weight: .bold))
                    .foregroundStyle(isLiked ? Color.pink : ink)
                    .eagleSymbolPop(isLiked)
                if count > 0 {
                    Text(count, format: .number.notation(.compactName))
                        .font((onArtwork ? Font.caption : Font.subheadline).weight(.bold).monospacedDigit())
                        .foregroundStyle(ink)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, onArtwork ? 10 : 16)
            .frame(height: onArtwork ? 30 : 44)
            .background {
                if onArtwork {
                    Capsule().fill(.ultraThinMaterial)
                } else {
                    Capsule().fill(Color(uiColor: .secondarySystemGroupedBackground))
                }
            }
            .overlay { Capsule().strokeBorder(ink.opacity(onArtwork ? 0.18 : 0.07), lineWidth: 1) }
            // Glass reads as dark glass over any artwork.
            .environment(\.colorScheme, onArtwork ? .dark : colorScheme)
            .animation(.easeOut(duration: 0.2), value: count)
            // A comfortable touch area around the small capsule on artwork.
            .padding(onArtwork ? 6 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(EaglePressableStyle(kind: .swatch))
        .accessibilityLabel(isLiked
            ? LaraL10n.text(en: "Remove like", es: "Quitar me gusta")
            : LaraL10n.text(en: "Like", es: "Me gusta"))
        .accessibilityValue(LaraL10n.text(en: "\(count) likes", es: "\(count) me gusta"))
    }
}

/// The tag on the most liked item.
struct EagleHotBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.orange)
            Text("HOT")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(.black)
        }
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Color.white, in: Capsule())
        .accessibilityLabel(LaraL10n.text(en: "Most liked", es: "El más gustado"))
    }
}

/// How many people have Eagle open: a head-and-shoulders symbol and the number, glowing and slowly
/// breathing, red under five people and green from five. Shown on Customize and Access, under Settings.
struct EagleOnlineBadge: View {
    /// A fixed number to show instead of the live one (the in-app guide's example).
    var sample: Int? = nil
    @ObservedObject private var likes = EagleLikes.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    private static let glowRed = Color(red: 1.0, green: 0.16, blue: 0.2)
    private static let glowGreen = Color(red: 0.2, green: 0.95, blue: 0.4)

    var body: some View {
        if let online = sample ?? likes.online {
            let glow = online < 5 ? Self.glowRed : Self.glowGreen
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                Text(online, format: .number.notation(.compactName))
                    .font(.caption.weight(.heavy).monospacedDigit())
                    .foregroundStyle(glow)
                    .shadow(color: glow.opacity(breathing ? 0.9 : 0.25), radius: breathing ? 6 : 2)
                    .opacity(reduceMotion ? 1 : (breathing ? 1 : 0.55))
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 11)
            .frame(minHeight: 34)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            .overlay { Capsule().strokeBorder(.primary.opacity(0.06), lineWidth: 1) }
            .animation(.easeOut(duration: 0.3), value: online)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LaraL10n.text(
                en: "\(online) people using Eagle now",
                es: "\(online) personas usando Eagle ahora"
            ))
        }
    }
}
