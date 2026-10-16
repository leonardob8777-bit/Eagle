//
//  lara.swift
//  lara
//
//  Created by ruter on 23.03.26.
//

import SwiftUI
import UniformTypeIdentifiers

let g_isunsupported: Bool = isunsupported()
var weonadebugbuild_pjbweouttahereexclamationmark: Bool = false

@main
struct LaraCustomApp: App {
    @StateObject private var mgr = laramgr.shared
    @Environment(\.scenePhase) var scenephase
    @AppStorage("keepAlive") private var keepalive: Bool = false
    @AppStorage(LaraLanguage.storageKey) private var language = LaraLanguage.english
    @AppStorage(EagleAppearanceMode.storageKey)
    private var appearanceModeRaw = EagleAppearanceMode.dark.rawValue
    // The welcome is shown once per installation of Eagle, including an IPA installed over an existing copy.
    @State private var showingStableUpdate = EagleWelcomeInstall.needsWelcome
    // Every other launch opens with the logo from the launch screen growing into the app.
    @State private var showingLaunchSplash = !EagleWelcomeInstall.needsWelcome

    private var preferredColorScheme: ColorScheme? {
        (EagleAppearanceMode(rawValue: appearanceModeRaw) ?? .dark).preferredColorScheme
    }
    
    init() {
        EaglePreferenceMigration.runIfNeeded()
        // Simplified Chinese interface text (the table lives outside the core module).
        EagleLocalization.chineseText = EagleChineseText.translate
        // The screens are in place from the first frame: the opening (or the welcome) reveals them.
        EagleArrival.shared.arrive()
        EagleSpectrumStyle.configureGlobalNavigationAppearance()

        #if DEBUG
        weonadebugbuild_pjbweouttahereexclamationmark = true
        #endif
        
        // fix file picker
        let fixMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.fix_init(forOpeningContentTypes:asCopy:)))!
        let origMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.init(forOpeningContentTypes:asCopy:)))!
        method_exchangeImplementations(origMethod, fixMethod)
        
        if keepalive {
            toggleka()
        }

        globallogger.capture()
    }
    
    var body: some Scene {
        WindowGroup {
            EagleAppShellView()
            .background(EagleNotificationInstaller().frame(width: 0, height: 0))
            .environmentObject(mgr)
            .environment(\.locale, language.locale)
            // Every switch in the app keeps its knob visible (see EagleSwitchToggleStyle).
            .toggleStyle(EagleSwitchToggleStyle())
            .preferredColorScheme(preferredColorScheme)
            // Choosing Light, Dark or System in Settings crossfades the window instead of flipping.
            .onChange(of: appearanceModeRaw) { _ in EagleThemeCrossfade.run() }
            // Switching the language crossfades the texts the same way.
            .onChange(of: language) { _ in EagleThemeCrossfade.run() }
            .overlay {
                if mgr.showrespring {
                    respringview()
                        .brightness(-1.0)
                        .ignoresSafeArea()
                }
            }
            .onAppear {
                if !isunsupported() {
                    init_offsets()
                    offsets_init()
                    mgr.hasOffsets = emergencyfixfunctiontobereplacedlateronquestionmark()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    if !showingStableUpdate {
                        EagleSceneManager.shared.applyPendingShortcutIfNeeded()
                    }
                }
            }
            .onChange(of: scenephase, perform: handleScenePhase)
            .allowsHitTesting(!showingStableUpdate && !showingLaunchSplash)
            .accessibilityHidden(showingStableUpdate || showingLaunchSplash)
            // No zoom while the welcome closes: the welcome clears onto the app's own backdrop, so only
            // the app's content appears. (A scaled app also lays its backdrop out below the top safe area
            // until it is back at full size, which showed as a band and a jump at the end.)
            .overlay {
                if showingStableUpdate {
                    EagleBeta10WelcomeView(onContinue: {
                        EagleWelcomeInstall.markSeen()
                        showingStableUpdate = false
                        EagleArrival.shared.arrive()
                        EagleSceneManager.shared.applyPendingShortcutIfNeeded()
                    }, onReveal: {
                        // The app's content lands on the backdrop as the welcome clears.
                        EagleArrival.shared.arrive()
                    })
                    .environment(\.locale, language.locale)
                    .ignoresSafeArea()
                    .zIndex(100)
                }
            }
            .overlay {
                if showingLaunchSplash {
                    EagleLaunchSplash { showingLaunchSplash = false }
                        .zIndex(101)
                }
            }
            // One owner: leaving either opening restores the bar on every app route.
            .statusBarHidden(showingStableUpdate || showingLaunchSplash)
            .onChange(of: showingStableUpdate) { _ in EagleStatusBar.refresh() }
            .onChange(of: showingLaunchSplash) { _ in EagleStatusBar.refresh() }
        }
    }
    
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .inactive:
            // Permission sheets and Control Center also make the app inactive.
            // They must not tear down a session while a user action is running.
            break

        case .background:
            mgr.remoteAppDidEnterBackground()
            // Preserve cleanup diagnostics without closing stdout underneath
            // a worker that is still finishing a native operation.
            globallogger.flushToDisk()

        case .active:
            globallogger.capture()
            mgr.remoteAppDidBecomeActive()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if !showingStableUpdate {
                    EagleSceneManager.shared.applyPendingShortcutIfNeeded()
                }
            }

        @unknown default:
            break
        }
    }

}

// file picker fixes
extension UIDocumentPickerViewController {
    @objc func fix_init(forOpeningContentTypes contentTypes: [UTType], asCopy: Bool) -> UIDocumentPickerViewController {
        return fix_init(forOpeningContentTypes: contentTypes, asCopy: true)
    }
}

// make strings compatiable with errors
extension String: @retroactive Error {}
