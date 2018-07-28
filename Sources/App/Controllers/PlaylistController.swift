//
//  PlaylistController.swift
//  App
//
//  Created by Dalton Claybrook on 7/28/18.
//

import Vapor

enum PlaylistControllerError: Error {
  case badPlaylistResponse
  case urlEncodingFailed
  case unknown
}

final class PlaylistController {
  private let baseURL: String

  init(baseURL: String) {
    self.baseURL = baseURL
  }

  func getMaster(_ request: Request) throws -> Future<Playlist> {
    let contentURL = "http://d2nob5kdy2t5a5.cloudfront.net/brnufyko/vid/master.m3u8"
    let stitchURL = "http://d2nob5kdy2t5a5.cloudfront.net/6ijfky34/vid/master.m3u8"

    let client = try request.client()
    let contentResponse = client.get(contentURL)
    let stitchResponse = client.get(stitchURL)

    return contentResponse.and(stitchResponse)
      .map { responses -> Playlist in
        let (contentResponse, stitchResponse) = responses
        let contentPlaylist = try self.parsePlaylist(from: contentResponse, url: contentURL)
        let stitchPlaylist = try self.parsePlaylist(from: stitchResponse, url: stitchURL)
        return try self.playlistByAssociating(content: contentPlaylist, withStitch: stitchPlaylist)
      }
  }

  func getMedia(_ request: Request) throws -> Future<Playlist> {
    let query = try request.query.decode(MediaQuery.self)

    let client = try request.client()
    let contentResponse = client.get(query.content)
    let stitchResponse = client.get(query.stitch)

    return contentResponse.and(stitchResponse)
      .map { responses -> Playlist in
        let (contentResponse, stitchResponse) = responses
        let contentPlaylist = try self.parsePlaylist(from: contentResponse, url: query.content)
        let stitchPlaylist = try self.parsePlaylist(from: stitchResponse, url: query.stitch)
        return try self.playlistByInsertingTags(
          fromStitch: stitchPlaylist,
          stitchURL: query.stitch,
          intoContent: contentPlaylist,
          contentURL: query.content
        )
      }
  }

  // MARK: - Helpers

  private func parsePlaylist(from response: Response, url: String) throws -> Playlist {
    guard let data = response.http.body.data else {
      throw PlaylistControllerError.badPlaylistResponse
    }

    let parser = PlaylistParser()
    let playlist = try parser.parse(playlistData: data)
    var utility = PlaylistUtility(playlist: playlist)
    try utility.expandURIsIfNecessary(withPlaylistURL: url)
    return utility.playlist
  }

  private func playlistByInsertingTags(
    fromStitch stitchPlaylist: Playlist,
    stitchURL: String,
    intoContent contentPlaylist: Playlist,
    contentURL: String
  ) throws -> Playlist {
    var contentUtility = PlaylistUtility(playlist: contentPlaylist)
    var stitchUtility = PlaylistUtility(playlist: stitchPlaylist)

    try contentUtility.expandURIsIfNecessary(withPlaylistURL: contentURL)
    try stitchUtility.expandURIsIfNecessary(withPlaylistURL: stitchURL)

    let insertionPoint: TimeInterval = 20
    let tagsToInsert = stitchUtility.allSegments(addDiscontinuityMarkers: true, withKey: contentUtility.playlist.encryptionKey)
    try contentUtility.insertTags(tagsToInsert, at: insertionPoint)
    try contentUtility.correctTargetDurationIfNecessary()

    return contentUtility.playlist
  }

  private func playlistByAssociating(content: Playlist, withStitch stitch: Playlist) throws -> Playlist {
    return try zip(0..., content.tags)
      .reduce(content) { playlist, tagPair in
        let (index, tag) = tagPair
        guard case .streamInfo(let info, let uri) = tag else { return playlist }

        var playlist = playlist
        let stitchURI = try stitchURIMatching(streamInfo: info, fromStitchPlaylist: stitch)
        let fullURL = try fullMediaURL(withContentURI: uri, stitchURI: stitchURI)
        playlist.tags[index] = .streamInfo(info, uri: fullURL)
        return playlist
      }
  }

  private func stitchURIMatching(streamInfo: StreamInfo, fromStitchPlaylist stitch: Playlist) throws -> String {
    guard let contentBandwidth = streamInfo.bandwidth else { throw Abort.playlistError }

    var closestInfo: (StreamInfo, String)?
    try stitch.tags.forEach { tag in
      guard case .streamInfo(let info, let uri) = tag else { return }
      if let closest = closestInfo {
        guard let closestBandwidth = closest.0.bandwidth,
          let competingBandwidth = info.bandwidth else { throw Abort.playlistError }

        if competingBandwidth > contentBandwidth && closestBandwidth <= contentBandwidth {
          // bandwidth lower than the content is always preferred
          return
        } else if competingBandwidth <= contentBandwidth && closestBandwidth > contentBandwidth {
          // bandwidth lower than the content is always preferred
          closestInfo = (info, uri)
        } else if abs(contentBandwidth - competingBandwidth) < abs(contentBandwidth - closestBandwidth) {
          // both are over bandwidth, or both are under bandwidth, and the competing bandwidth is closer
          closestInfo = (info, uri)
        }
      } else {
        closestInfo = (info, uri)
      }
    }

    if let stitchURI = closestInfo?.1 {
      return stitchURI
    } else {
      throw Abort.playlistError
    }
  }

  private func fullMediaURL(withContentURI contentURI: String, stitchURI: String) throws -> String {
    guard
      let encodedContent = contentURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
      let encodedStitch = stitchURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    else { throw PlaylistControllerError.urlEncodingFailed }
    return "\(baseURL)/media?content=\(encodedContent)&stitch=\(encodedStitch)"
  }
}
