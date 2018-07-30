//
//  Playlist+Additions.swift
//  App
//
//  Created by Dalton Claybrook on 7/29/18.
//

import Foundation
import Vapor

extension Playlist {
  var encryptionKey: EncryptionKey? {
    for tag in tags {
      guard case let .key(encryptionKey) = tag else { continue }
      return encryptionKey
    }
    return nil
  }

  var mediaSequence: Int {
    for tag in tags {
      guard case .sequence(let value) = tag else { continue }
      return value
    }
    return 0
  }

  var discontinuitySequence: Int {
    for tag in tags {
      guard case .discontinuitySequence(let value) = tag else { continue }
      return value
    }
    return 0
  }

  var targetDuration: Int {
    for tag in tags {
      guard case .targetDuration(let value) = tag else { continue }
      return value
    }
    return 10
  }

  var version: Int {
    for tag in tags {
      guard case .version(let value) = tag else { continue }
      return value
    }
    return 4
  }
}

extension Playlist: ResponseEncodable {
  public func encode(for req: Request) throws -> EventLoopFuture<Response> {
    let data = try PlaylistParser().generatePlaylistData(with: self)
    let body = HTTPBody(data: data)

    var headers = HTTPHeaders()
    headers.add(name: .contentType, value: "application/vnd.apple.mpegurl")

    let httpResponse = HTTPResponse(status: .ok, headers: headers, body: body)
    let response = Response(http: httpResponse, using: req.sharedContainer)

    let promise = req.eventLoop.newPromise(Response.self)
    promise.succeed(result: response)
    return promise.futureResult
  }
}
