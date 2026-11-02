//
//  isunsupported.swift
//  lara
//
//  Created by ruter on 30.03.26.
//

import Foundation
import Darwin

/// The product support levels shown to users. Keep every iOS range in
/// `eagleSupportAssessment(version:machine:systemBuild:)`; native callers must not invent a
/// second, broader range.
enum EagleSupportStatus: String, Equatable {
    /// The engine has a path for this release, but it is not considered stable.
    case possible
    /// Confirmed on at least one device, with more device coverage still needed.
    case testedNeedsMoreTesting
    case supported
    case unsupported

    var allowsPrepare: Bool {
        self != .unsupported
    }
}

/// Stable diagnostic identifiers. These are deliberately not localized so a
/// shared Prepare report can be searched and compared across languages.
enum EagleSupportReason: String, Equatable {
    case iphone16IOS185FieldRestart = "iphone17,3-ios18.5.field-restart"
    case iphone16IOS185KernelStageLab = "iphone17,3-ios18.5.kernel-stage-lab"
    case ios16Experimental = "ios16.experimental"
    case ios1672LimitedTesting = "ios16.7.2.tested-limited"
    case ios17Through1871 = "ios17.0-ios18.7.1.supported"
    case ios260Through2601 = "ios26.0-ios26.0.1.supported"
    case belowIOS16 = "ios.below-16.unsupported"
    case ios1872OrNewer = "ios18.7.2-or-newer.unsupported"
    case unrecognizedMajorGap = "ios19-ios25.unsupported"
    case ios26After2601 = "ios26.after-26.0.1.unsupported"
    case futureMajor = "ios.after-26.unsupported"
    case memoryIntegrityEnforcement = "device.mie.unsupported"
}

struct EagleSupportAssessment: Equatable {
    let status: EagleSupportStatus
    let reason: EagleSupportReason

    var allowsPrepare: Bool {
        // "Possible" is a discovery label, not evidence that a public kernel
        // attempt is safe. The exact A18 lab route is intentionally one-shot;
        // unverified iOS 16 tuples remain visible but fail closed.
        if reason == .iphone16IOS185KernelStageLab { return true }
        if reason == .ios16Experimental { return false }
        return status.allowsPrepare
    }

    /// A concise bilingual explanation suitable for a compatibility screen or
    /// diagnostic export. The app UI can continue selecting its own language.
    func message(spanish: Bool) -> String {
        switch reason {
        case .iphone16IOS185FieldRestart:
            return spanish
                ? "Preparar puede reiniciar el iPhone 16 con iOS 18.5. Eagle bloqueó esta combinación antes de ejecutar el motor de acceso."
                : "Prepare can restart iPhone 16 on iOS 18.5. Eagle blocked this combination before running the access engine."
        case .iphone16IOS185KernelStageLab:
            return spanish
                ? "Esta compilación privada prueba solamente la etapa del kernel en iPhone 16 con iOS 18.5; no abre el sandbox ni habilita el flujo completo."
                : "This private build probes only the kernel stage on iPhone 16 with iOS 18.5; it does not open the sandbox or enable the full flow."
        case .ios16Experimental:
            return spanish
                ? "Esta versión de iOS 16 todavía no tiene una combinación de dispositivo y compilación validada. Preparar está bloqueado para evitar reinicios."
                : "This iOS 16 release does not yet have a validated device/build combination. Prepare is blocked to prevent restarts."
        case .ios1672LimitedTesting:
            return spanish
                ? "iOS 16.7.2 fue probado, pero todavía necesita pruebas en más dispositivos."
                : "iOS 16.7.2 was tested, but still needs testing on more devices."
        case .ios17Through1871:
            return spanish
                ? "Esta versión está dentro del rango compatible de iOS 17.0 a iOS 18.7.1."
                : "This release is inside the supported iOS 17.0 through iOS 18.7.1 range."
        case .ios260Through2601:
            return spanish
                ? "Esta versión está dentro del rango compatible de iOS 26.0 a iOS 26.0.1."
                : "This release is inside the supported iOS 26.0 through iOS 26.0.1 range."
        case .belowIOS16:
            return spanish
                ? "Las versiones anteriores a iOS 16 no son compatibles."
                : "Releases earlier than iOS 16 are not supported."
        case .ios1872OrNewer:
            return spanish
                ? "iOS 18.7.2 y las versiones posteriores de iOS 18 no son compatibles."
                : "iOS 18.7.2 and later iOS 18 releases are not supported."
        case .unrecognizedMajorGap:
            return spanish
                ? "Este número principal de iOS no pertenece a un rango compatible conocido."
                : "This iOS major version is not part of a known supported range."
        case .ios26After2601:
            return spanish
                ? "Solo iOS 26.0 y iOS 26.0.1 son compatibles actualmente."
                : "Only iOS 26.0 and iOS 26.0.1 are currently supported."
        case .futureMajor:
            return spanish
                ? "Esta versión de iOS es más reciente que el motor compatible actual."
                : "This iOS release is newer than the current supported engine."
        case .memoryIntegrityEnforcement:
            return spanish
                ? "Este modelo usa protecciones de memoria que el motor actual no admite."
                : "This model uses memory protections that the current engine does not support."
        }
    }
}

enum EaglePrepareExecutionRoute: String, Equatable {
    case stableLegacy = "stable-legacy"
    case blockedFieldRestart = "blocked-field-restart"
    case a18KernelStageLab = "a18-kernel-stage-lab"

    var allowsPrepare: Bool {
        self != .blockedFieldRestart
    }
}

func devicemachine() -> String {
    var sysinfo = utsname()
    uname(&sysinfo)

    let mirror = Mirror(reflecting: sysinfo.machine)
    return mirror.children.reduce("") { identifier, element in
        guard let value = element.value as? Int8, value != 0 else { return identifier }
        return identifier + String(UnicodeScalar(UInt8(value)))
    }
}

func hasmie(machine: String) -> Bool {
    // iPad17,* is the M5 family. Keep it outside Prepare just as the
    // iPhone18,* A19 family is, before touching offsets or DarkSword.
    machine.hasPrefix("iPhone18,") || machine.hasPrefix("iPad17,")
}

func hasmie() -> Bool {
    hasmie(machine: devicemachine())
}

/// Darwin build identifier for the running OS (for example, `22G100`).
/// Compatibility exceptions must use this value instead of treating every
/// release with the same marketing version as identical.
func eagleSystemBuild() -> String? {
    var size = 0
    guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0,
          size > 1 else {
        return nil
    }

    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0 else {
        return nil
    }
    return String(cString: buffer)
}

/// Pure dispatch for the access engine. Public builds use the same stable
/// route that supported iPhone 16 devices used before the temporary field
/// block. Enabling the isolated lab still requires an explicit compilation
/// condition and an exact model/build match.
func eaglePrepareExecutionRoute(
    version: OperatingSystemVersion,
    machine: String,
    systemBuild: String?
) -> EaglePrepareExecutionRoute {
    guard machine == "iPhone17,3",
          version.majorVersion == 18,
          version.minorVersion == 5 else {
        return .stableLegacy
    }

#if EAGLE_A18_PREPARE_LAB
    let trimmedBuild = systemBuild?.trimmingCharacters(
        in: .whitespacesAndNewlines
    )
    let normalizedBuild = (trimmedBuild?.isEmpty == false &&
        trimmedBuild != "unknown") ? trimmedBuild : nil
    if normalizedBuild == "22F76" {
        return .a18KernelStageLab
    }
    return .blockedFieldRestart
#else
    _ = systemBuild
    return .stableLegacy
#endif
}

/// Pure compatibility resolver. Accepting the version and machine explicitly
/// makes every boundary testable without pretending a simulator has kernel
/// access.
func eagleSupportAssessment(
    version: OperatingSystemVersion,
    machine: String,
    systemBuild: String? = nil
) -> EagleSupportAssessment {
    // Public builds preserve the previously working stable route for iPhone 16
    // on iOS 18.5. Private lab builds may still isolate an exact OTA while
    // investigating device-specific reports.
    let prepareRoute = eaglePrepareExecutionRoute(
        version: version,
        machine: machine,
        systemBuild: systemBuild
    )
    if prepareRoute == .blockedFieldRestart {
        return EagleSupportAssessment(
            status: .unsupported,
            reason: .iphone16IOS185FieldRestart
        )
    }
    if prepareRoute == .a18KernelStageLab {
        return EagleSupportAssessment(
            status: .possible,
            reason: .iphone16IOS185KernelStageLab
        )
    }

    if hasmie(machine: machine) {
        return EagleSupportAssessment(
            status: .unsupported,
            reason: .memoryIntegrityEnforcement
        )
    }

    switch version.majorVersion {
    case ..<16:
        return EagleSupportAssessment(status: .unsupported, reason: .belowIOS16)

    case 16:
        // The 16.7.2 report belongs to an iPhone. No iPadOS 16 route has been
        // validated for Eagle, so do not promote that one-device exception.
        if machine.hasPrefix("iPad") {
            return EagleSupportAssessment(status: .possible, reason: .ios16Experimental)
        }
        if version.minorVersion == 7, version.patchVersion == 2 {
            return EagleSupportAssessment(
                status: .testedNeedsMoreTesting,
                reason: .ios1672LimitedTesting
            )
        }
        return EagleSupportAssessment(status: .possible, reason: .ios16Experimental)

    case 17:
        return EagleSupportAssessment(status: .supported, reason: .ios17Through1871)

    case 18:
        let isAtOrBefore1871 = version.minorVersion < 7 ||
            (version.minorVersion == 7 && version.patchVersion <= 1)
        return isAtOrBefore1871
            ? EagleSupportAssessment(status: .supported, reason: .ios17Through1871)
            : EagleSupportAssessment(status: .unsupported, reason: .ios1872OrNewer)

    case 19...25:
        return EagleSupportAssessment(status: .unsupported, reason: .unrecognizedMajorGap)

    case 26:
        let is260Through2601 = version.minorVersion == 0 && version.patchVersion <= 1
        return is260Through2601
            ? EagleSupportAssessment(status: .supported, reason: .ios260Through2601)
            : EagleSupportAssessment(status: .unsupported, reason: .ios26After2601)

    default:
        return EagleSupportAssessment(status: .unsupported, reason: .futureMajor)
    }
}

func eagleSupportAssessment() -> EagleSupportAssessment {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let machine = devicemachine()
    let needsBuildForFieldRouting = machine == "iPhone17,3" &&
        version.majorVersion == 18 && version.minorVersion == 5
    return eagleSupportAssessment(
        version: version,
        machine: machine,
        systemBuild: needsBuildForFieldRouting ? eagleSystemBuild() : nil
    )
}

func isunsupported() -> Bool {
    !eagleSupportAssessment().allowsPrepare
}
