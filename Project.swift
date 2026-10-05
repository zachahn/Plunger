import ProjectDescription

let project = Project(
    name: "Plunger",
    settings: .settings(base: [
        "CODE_SIGN_STYLE": "Automatic",
        "DEVELOPMENT_TEAM": "TZWTJP2JSN",
    ]),
    targets: [
        .target(
            name: "Plunger",
            destinations: .macOS,
            product: .app,
            bundleId: "com.zachahn.Plunger",
            deploymentTargets: .macOS("26.5"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Plunger",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "LSApplicationCategoryType": "public.app-category.developer-tools",
                "LSUIElement": true,
                "NSHumanReadableCopyright": "",
                "SUEnableAutomaticChecks": true,
                "SUFeedURL": "https://raw.githubusercontent.com/zachahn/Plunger/main/appcast.xml",
                "SUPublicEDKey": "aVfR/4R4PI6EQhamZkTHZB8kwK/1k2IN87CPITODP3o=",
            ]),
            buildableFolders: [
                "Plunger/Sources",
                "Plunger/Resources",
            ],
            dependencies: [
                .external(name: "Sparkle"),
            ],
            settings: .settings(base: [
                "CODE_SIGN_IDENTITY": "Apple Development",
                "MARKETING_VERSION": "1.2",
                "CURRENT_PROJECT_VERSION": "8",
                "ENABLE_HARDENED_RUNTIME": "YES",
                "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
                "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
                "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
            ])
        ),
        .target(
            name: "PlungerTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.zachahn.PlungerTests",
            deploymentTargets: .macOS("26.5"),
            infoPlist: .default,
            buildableFolders: [
                "Plunger/Tests"
            ],
            dependencies: [.target(name: "Plunger")],
            settings: .settings(base: [
                "CODE_SIGN_IDENTITY": "Apple Development",
                "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
                "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
            ])
        ),
    ]
)
