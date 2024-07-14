//
//  Env.swift
//  zelby-compagnion
//
//  Created by Maxime Dias on 14/07/2024.
//

import Foundation

struct Env {
    static var apiKey: String {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "ExternalApiKey") as? String else {
            fatalError("Unable to fetch api key")
        }
        return key
    }
    
    static var baseUrl: String {
        guard let url = Bundle.main.object(forInfoDictionaryKey: "BaseUrl") as? String else {
            fatalError("Unable to fetch base url")
        }
        return url
    }
}
