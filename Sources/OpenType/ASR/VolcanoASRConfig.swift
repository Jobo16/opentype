import Foundation

struct VolcanoASRConfig: ASRProviderConfig, Sendable {

    static let provider = ASRProvider.volcano
    static var displayName: String { "火山引擎 (Volcano Engine)" }
    var provider: ASRProvider { Self.provider }

    static let resourceIdSeedASR = "volc.seedasr.sauc.duration"
    static let resourceIdBigASR  = "volc.bigasr.sauc.duration"
    static let resourceIdAuto    = "auto"

    static var credentialFields: [CredentialField] {[
        CredentialField(key: "appKey", label: "App ID", placeholder: "APPID", isSecure: false),
        CredentialField(key: "accessKey", label: "Access Token", placeholder: "Access token", isSecure: true),
        CredentialField(
            key: "resourceId",
            label: "识别模型",
            defaultValue: resourceIdAuto,
            options: [
                FieldOption(value: resourceIdAuto,   label: "自动（优先 2.0，额度用完切 1.0）"),
                FieldOption(value: resourceIdSeedASR, label: "流式语音识别模型 2.0"),
                FieldOption(value: resourceIdBigASR,  label: "流式语音识别大模型"),
            ]
        ),
    ]}

    let appKey: String
    let accessKey: String
    let resourceId: String
    let uid: String

    init?(credentials: [String: String]) {
        guard let appKey = credentials["appKey"], !appKey.isEmpty,
              let accessKey = credentials["accessKey"], !accessKey.isEmpty
        else { return nil }
        self.appKey = appKey
        self.accessKey = accessKey
        let raw = credentials["resourceId"] ?? Self.resourceIdAuto
        if raw == Self.resourceIdAuto || raw.isEmpty {
            self.resourceId = credentials["resolvedResourceId"]?.isEmpty == false
                ? credentials["resolvedResourceId"]!
                : Self.resourceIdSeedASR
        } else {
            self.resourceId = raw
        }
        self.uid = UUID().uuidString
    }

    func toCredentials() -> [String: String] {
        ["appKey": appKey, "accessKey": accessKey, "resourceId": resourceId]
    }

    var isValid: Bool {
        !appKey.isEmpty && !accessKey.isEmpty
    }
}
