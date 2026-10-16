//
//  Compatibility adapter for existing archive call sites.
//  The archive implementation lives in EagleCore/Archives/EagleZIPArchive.swift.
//  Original archive author: neonmodder123, 17/05/2026.
//

import Foundation

// Keep existing archive callers compatible with the owned app diagnostic route.
typealias CurrentArchiveDiagnostics = EagleAppDiagnostics

nonisolated extension ZipArchive {
    public convenience init(data: Data) throws {
        try self.init(data: data, log: CurrentArchiveDiagnostics.log)
    }
}

public func createZipArchive(fromDirectory sourceURL: URL, to destinationURL: URL, compressionMethod: UInt16 = 0) throws {
    try createZipArchive(
        fromDirectory: sourceURL,
        to: destinationURL,
        compressionMethod: compressionMethod,
        log: CurrentArchiveDiagnostics.log
    )
}
