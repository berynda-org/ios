import BeryndaCore

extension WorkRightsClaim {
    var title: String {
        switch self {
        case .publicDomain: L("Суспільне надбання")
        case .openLicense: L("Відкрита ліцензія")
        case .byPermission: L("Дозволено правовласником")
        case .selfPublished: L("Самостійна публікація")
        }
    }

    var symbol: String {
        switch self {
        case .publicDomain: "building.columns"
        case .openLicense: "checkmark.seal"
        case .byPermission: "hand.raised"
        case .selfPublished: "person.crop.rectangle"
        }
    }

    var explanation: String {
        switch self {
        case .publicDomain:
            L("Каталог містить підтвердження статусу суспільного надбання для цього твору. Умови використання конкретного видання та його файлів можуть відрізнятися.")
        case .openLicense:
            L("Матеріали опубліковано на умовах відкритої ліцензії. Умови використання наведено для конкретного видання.")
        case .byPermission:
            L("Матеріали опубліковано з дозволу правовласника; умови можуть відрізнятися для окремих видань.")
        case .selfPublished:
            L("Матеріали опубліковано самостійно. Це не означає, що твір є суспільним надбанням або дозволений для вільного використання.")
        }
    }
}
