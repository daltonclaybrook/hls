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
  case liveURLNotSet
  case unknown
}

enum StitchingState {
  case notStitching
  case waitingToStitch
  case stitching(sequence: Int, discontinuity: Int)
}

final class PlaylistController {
  private let baseURL: String
  private let stitchURL = "http://d2nob5kdy2t5a5.cloudfront.net/6ijfky34/vid/master.m3u8"
  private var state: StitchingState = .notStitching
  private var liveStartDate = Date()
  private var liveURL = ""

  init(baseURL: String) {
    self.baseURL = baseURL
  }

  // MARK: - Endpoints

  func getMaster(_ request: Request) throws -> Future<Playlist> {
    let query = try request.query.decode(MasterQuery.self)

    let client = try request.client()
    let contentResponse = client.get(query.content)
    let stitchResponse = client.get(stitchURL)

    return contentResponse.and(stitchResponse)
      .map { responses -> Playlist in
        let (contentResponse, stitchResponse) = responses
        let contentPlaylist = try self.parsePlaylist(from: contentResponse, url: query.content, expand: true)
        let stitchPlaylist = try self.parsePlaylist(from: stitchResponse, url: self.stitchURL, expand: true)
        return try self.playlistByAssociating(content: contentPlaylist, withStitch: stitchPlaylist)
      }
  }

  func getMedia(_ request: Request) throws -> Future<Playlist> {
    let query = try request.query.decode(MediaQuery.self)
    let client = try request.client()

    switch state {
    case .notStitching:
      return fetchUnmodifiedMediaPlaylist(with: client, query: query)
    case .waitingToStitch:
      return fetchMediaPlaylistAndTransitionToStitching(with: client, query: query)
    case let .stitching(sequence, discontinuity):
      return fetchAndStitchMediaPlaylists(with: client, query: query, mediaSequence: sequence, discontinuitySequence: discontinuity)
    }
  }

  func startStitching(_ request: Request) -> Response {
    self.state = .waitingToStitch
    return Response(http: HTTPResponse(status: .ok), using: request.sharedContainer)
  }

  func startLive(_ request: Request) throws -> Future<Response> {
    let payload = try request.content.decode(LiveURLPayload.self)
    return payload.map { payload in
      self.liveStartDate = Date()
      self.liveURL = payload.liveURL
      return Response(http: HTTPResponse(status: .ok), using: request.sharedContainer)
    }
  }

  func getFakeLiveMaster(_ request: Request) throws -> Future<Playlist> {
    guard !liveURL.isEmpty else {
      throw PlaylistControllerError.liveURLNotSet
    }

    let client = try request.client()
    return client.get(liveURL)
      .map { response in
        let playlist = try self.parsePlaylist(from: response, url: self.liveURL, expand: true)
        return try self.playlistByAddingProxyURLs(toPlaylist: playlist)
      }
  }

  func getFakeLiveMedia(_ request: Request) throws -> Future<Playlist> {
    let query = try request.query.decode(MasterQuery.self)
    let client = try request.client()
    return client.get(query.content)
      .map { response in
        let playlist = try self.parsePlaylist(from: response, url: query.content, expand: false)
        var utility = PlaylistUtility(playlist: playlist)
        utility.convertToLivePlaylist(withStartDate: self.liveStartDate)
        return utility.playlist
      }
  }

  // MARK: - Media Playlist Fetching

  private func fetchUnmodifiedMediaPlaylist(with client: Client, query: MediaQuery) -> Future<Playlist> {
    return client.get(query.content)
      .map { response in
        guard let data = response.http.body.data else {
          throw PlaylistControllerError.badPlaylistResponse
        }
        return try PlaylistParser().parse(playlistData: data)
      }
  }

  private func fetchMediaPlaylistAndTransitionToStitching(with client: Client, query: MediaQuery) -> Future<Playlist> {
    return fetchUnmodifiedMediaPlaylist(with: client, query: query)
      .do { playlist in
        let counts = PlaylistUtility(playlist: playlist).getCounts()
        self.state = .stitching(
          sequence: counts.mediaSequence + counts.segmentCount,
          discontinuity: counts.discontinuitySequence
        )
      }
  }

  private func fetchAndStitchMediaPlaylists(
    with client: Client,
    query: MediaQuery,
    mediaSequence: Int,
    discontinuitySequence: Int
  ) -> Future<Playlist> {
    let contentResponse = client.get(query.content)
    let stitchResponse = client.get(query.stitch)

    return contentResponse
      .and(stitchResponse)
      .map { responses in
        let (contentResponse, stitchResponse) = responses
        let contentPlaylist = try self.parsePlaylist(from: contentResponse, url: query.content, expand: false)
        let stitchPlaylist = try self.parsePlaylist(from: stitchResponse, url: query.stitch, expand: true)

        var utility = PlaylistUtility(playlist: contentPlaylist)
        try utility.stitch(
          playlist: stitchPlaylist,
          atMediaSequence: mediaSequence,
          withOriginalDiscontinuitySequence: discontinuitySequence
        )
        return utility.playlist
      }
  }

  // MARK: - Helpers

  private func parsePlaylist(from response: Response, url: String, expand: Bool) throws -> Playlist {
    guard let data = response.http.body.data else {
      throw PlaylistControllerError.badPlaylistResponse
    }

    let parser = PlaylistParser()
    let playlist = try parser.parse(playlistData: data)
    var utility = PlaylistUtility(playlist: playlist)
    if expand {
      try utility.expandURIsIfNecessary(withPlaylistURL: url)
    }
    return utility.playlist
  }

  private func playlistByAssociating(content: Playlist, withStitch stitch: Playlist) throws -> Playlist {
    return try zip(0..., content.tags)
      .reduce(into: content) { playlist, tagPair in
        let (index, tag) = tagPair
        guard case let .streamInfo(info, uri) = tag else { return }

        let stitchURI = try stitchURIMatching(streamInfo: info, fromStitchPlaylist: stitch)
        let fullURL = try fullMediaURL(withContentURI: uri, stitchURI: stitchURI)
        playlist.tags[index] = .streamInfo(info, uri: fullURL)
      }
  }

  private func playlistByAddingProxyURLs(toPlaylist: Playlist) throws -> Playlist {
    return try zip(0..., toPlaylist.tags)
      .reduce(into: toPlaylist) { playlist, tagPair in
        let (index, tag) = tagPair
        guard case let .streamInfo(info, uri) = tag else { return }

        let fakeURL = try self.fakeLiveMediaURL(withURI: uri)
        playlist.tags[index] = .streamInfo(info, uri: fakeURL)
      }
  }

  private func stitchURIMatching(streamInfo: StreamInfo, fromStitchPlaylist stitch: Playlist) throws -> String {
    guard let contentBandwidth = streamInfo.bandwidth else {
      throw Abort.playlistError
    }

    var closestInfo: (info: StreamInfo, uri: String)?
    try stitch.tags.forEach { tag in
      guard case let .streamInfo(info, uri) = tag else { return }
      if let closest = closestInfo {
        guard let closestBandwidth = closest.info.bandwidth,
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

    if let stitchURI = closestInfo?.uri {
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

  private func fakeLiveMediaURL(withURI uri: String) throws -> String {
    guard let encodedURI = uri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
      throw PlaylistControllerError.urlEncodingFailed
    }
    return "\(baseURL)/live/media?content=\(encodedURI)"
  }
}
