//
//  AppInfoCell.swift
//  PartyUI
//
//  Created by lunginspector on 3/3/26.
//

import SwiftUI

public struct AppInfoCell: View {
    public init() {}
    
    public var body: some View {
        HStack(spacing: 14) {
            AppIcon()
            VStack(alignment: .leading) {
                Text(AppInfo.appName)
                    .font(.system(.title3, weight: .semibold))
                Text(LaraL10n.text(
                    en: "Version \(AppInfo.appVersion) (\(AppInfo.appBuild))",
                    es: "Versión \(AppInfo.appVersion) (\(AppInfo.appBuild))"
                ))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// icon for AppInfoCell
public struct AppIcon: View {
    var image: Image
    
    init(image: Image = Image(uiImage: AppInfo.appIcon ?? UIImage())) {
        self.image = image
    }
    
    public var body: some View {
        if #available(iOS 19.0, *) {
            image
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .background(Color(.systemGray6))
                .clipShape(.rect(cornerRadius: 18))
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
        } else {
            image
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .background(Color(.systemGray6))
                .clipShape(.rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.primary.opacity(0.2), lineWidth: 2)
                }
        }
    }
}
