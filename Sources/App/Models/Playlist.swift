//
//  M3U8.swift
//  media-server
//
//  Created by Dalton Claybrook on 2/18/17.
//
//

import Foundation
import Vapor

//TODO: This should be a dumb model. A helper utility should be doing the mutations.
public struct Playlist {
  var tags: [PlaylistTag]

  init(tags: [PlaylistTag] = []) {
    self.tags = tags
  }
}

extension Playlist {
  var encryptionKey: EncryptionKey? {
    return tags.compactMap { tag in
      if case .key(let encryptionKey) = tag {
        return encryptionKey
      }
      return nil
      }.first
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
