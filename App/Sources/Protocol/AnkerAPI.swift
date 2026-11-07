import Foundation

enum AnkerRegion: String, CaseIterable, Identifiable {
    case us
    case eu

    var id: String { rawValue }

    var appBaseURL: String {
        self == .us ? "https://make-app.ankermake.com" : "https://make-app-eu.ankermake.com"
    }

    var mqttHost: String {
        self == .us ? "make-mqtt.ankermake.com" : "make-mqtt-eu.ankermake.com"
    }

    var label: String {
        self == .us ? "US / Americas" : "EU / Europe"
    }
}

struct AnkerPrinter: Identifiable, Hashable {
    let serial: String
    let name: String
    let model: String
    /// 32-byte AES key (hex-encoded in the API response)
    let secretKeyHex: String

    var id: String { serial }

    var isM5C: Bool { model.uppercased().contains("V8110") }
    var displayName: String { name.isEmpty ? serial : name }
}

struct AnkerAccount: Hashable {
    let email: String
    let userID: String
    let authToken: String
    let region: AnkerRegion

    var mqttUsername: String { "eufy_\(userID)" }
    var mqttPassword: String { email }
}

/// Minimal client for the AnkerMake cloud APIs (reverse-engineered, see the
/// `Ankermgmt/ankermake-m5-protocol` project).
///
/// - `POST /v2/passport/login` with ECDH-P256-encrypted password → auth token
/// - `GET  /v1/passport/profile` → user id / email
/// - `POST /v1/app/query_fdm_list` → printer list incl. per-printer MQTT AES key
final class AnkerAPI {

    enum APIError: Error, LocalizedError {
        case badResponse(String)
        case missingField(String)
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .badResponse(let m): return "Unexpected API response: \(m)"
            case .missingField(let f): return "API response missing field '\(f)'"
            case .http(let code): return "HTTP error \(code)"
            }
        }
    }

    func login(region: AnkerRegion, email: String, password: String) async throws -> String {
        let (pubKey, encPwd) = try AnkerCrypto.encryptLoginPassword(password)

        var request = URLRequest(url: URL(string: "\(region.appBaseURL)/v2/passport/login")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Headers mirror the desktop client (some endpoints validate them).
        request.setValue("anker_make", forHTTPHeaderField: "App_name")
        request.setValue("", forHTTPHeaderField: "App_version")
        request.setValue("PC", forHTTPHeaderField: "Model_type")
        request.setValue("windows", forHTTPHeaderField: "Os_type")
        request.setValue("10sp1", forHTTPHeaderField: "Os_version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_secret_info": ["public_key": pubKey],
            "email": email,
            "password": encPwd,
        ])

        let json = try await perform(request)
        let data = try unwrap(json)
        guard let token = data["auth_token"] as? String else {
            throw APIError.missingField("auth_token")
        }
        return token
    }

    func profile(region: AnkerRegion, token: String) async throws -> (userID: String, email: String) {
        var request = URLRequest(url: URL(string: "\(region.appBaseURL)/v1/passport/profile")!)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "X-Auth-Token")

        let json = try await perform(request)
        let data = try unwrap(json)
        guard let userID = data["user_id"] as? String else {
            throw APIError.missingField("user_id")
        }
        let email = data["email"] as? String ?? ""
        return (userID, email)
    }

    func printerList(region: AnkerRegion, token: String) async throws -> [AnkerPrinter] {
        var request = URLRequest(url: URL(string: "\(region.appBaseURL)/v1/app/query_fdm_list")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-Auth-Token")
        request.httpBody = Data("{}".utf8)

        let json = try await perform(request)
        guard let list = json as? [[String: Any]] else {
            throw APIError.badResponse("query_fdm_list did not return a list")
        }

        return list.compactMap { entry in
            guard let sn = entry["station_sn"] as? String else { return nil }
            let name = entry["station_name"] as? String
                ?? entry["dev_name"] as? String
                ?? entry["name"] as? String
                ?? ""
            let model = entry["model"] as? String
                ?? entry["device_model"] as? String
                ?? entry["station_model"] as? String
                ?? ""
            guard let secret = entry["secret_key"] as? String, !secret.isEmpty else { return nil }
            return AnkerPrinter(serial: sn, name: name, model: model, secretKeyHex: secret)
        }
    }

    // MARK: - Plumbing

    private func perform(_ request: URLRequest) async throws -> Any {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.http(http.statusCode)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.badResponse("not a JSON object")
        }
        return obj
    }

    private func unwrap(_ json: Any) throws -> [String: Any] {
        guard let obj = json as? [String: Any] else {
            throw APIError.badResponse("not a JSON object")
        }
        let code = (obj["code"] as? Int) ?? -1
        guard code == 0 else {
            throw APIError.badResponse((obj["msg"] as? String) ?? "code \(code)")
        }
        guard let data = obj["data"] as? [String: Any] else {
            throw APIError.missingField("data")
        }
        return data
    }
}
