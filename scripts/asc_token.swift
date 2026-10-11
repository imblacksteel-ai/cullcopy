// App Store Connect API のアクセストークン（JWT、20分有効）を標準出力に出す
//
//   TOKEN=$(swift scripts/asc_token.swift)
//
// API キーはキーチェーン（アカウント名 kumofuton、KEYCHAIN_ACCOUNT で変更可）から読む。
// トークンは画面に出さず、コマンドの中でだけ使うこと
import CryptoKit
import Foundation

func secret(_ name: String) -> String {
    let account = ProcessInfo.processInfo.environment["KEYCHAIN_ACCOUNT"] ?? "kumofuton"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["find-generic-password", "-a", account, "-s", name, "-w"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          let value = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
              .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        FileHandle.standardError.write("キーチェーンに「\(name)」がありません。docs/release.md を見てください。\n".data(using: .utf8)!)
        exit(1)
    }
    return value
}

func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

let keyID = secret("ASC_KEY_ID")
let issuer = secret("ASC_ISSUER_ID")
guard let p8Data = Data(base64Encoded: secret("ASC_KEY_P8_BASE64")),
      let pem = String(data: p8Data, encoding: .utf8),
      let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else {
    FileHandle.standardError.write("API キーを読み込めませんでした。\n".data(using: .utf8)!)
    exit(1)
}

let now = Int(Date().timeIntervalSince1970)
let header = try! JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": keyID, "typ": "JWT"])
let payload = try! JSONSerialization.data(withJSONObject: ["iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"])
let signingInput = base64URL(header) + "." + base64URL(payload)
let signature = try! key.signature(for: Data(signingInput.utf8))
print(signingInput + "." + base64URL(signature.rawRepresentation))
