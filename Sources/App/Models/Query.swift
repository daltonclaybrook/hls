//
//  MediaQuery.swift
//  App
//
//  Created by Dalton Claybrook on 7/28/18.
//

import Foundation

struct MasterQuery: Decodable {
  let content: String
}

struct MediaQuery: Decodable {
  let content: String
  let stitch: String
}

struct LiveURLPayload: Decodable {
  let liveURL: String
}
