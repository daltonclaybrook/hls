//
//  PlaylistBuilder.swift
//  hls-server
//
//  Created by Dalton Claybrook on 6/11/17.
//
//

import Foundation
import Vapor

struct PlaylistUtility {

  private(set) var playlist: Playlist

  init(playlist: Playlist) {
    self.playlist = playlist
  }

  // MARK: Mutation

  mutating func expandURIsIfNecessary(withPlaylistURL urlString: String) throws {
    guard let playlistURL = URL(string: urlString)?.deletingLastPathComponent() else { throw Abort.playlistError }
    for (idx, tag) in playlist.tags.enumerated() {
      switch tag {
      case .streamInfo(let info, let uri):
        let expanded = try expandedURI(fromURI: uri, playlistURL: playlistURL)
        playlist.tags[idx] = .streamInfo(info, uri: expanded)
      case .segmentInfo(let duration, let uri):
        let expanded = try expandedURI(fromURI: uri, playlistURL: playlistURL)
        playlist.tags[idx] = .segmentInfo(duration: duration, uri: expanded)
      case .key(var key):
        guard let keyURI = key.uri else { continue }
        let expanded = try expandedURI(fromURI: keyURI, playlistURL: playlistURL)
        key.uri = expanded
        playlist.tags[idx] = .key(key)
      default:
        continue
      }
    }
  }

  mutating func insertTags(_ tagsToInsert: [PlaylistTag], at duration: TimeInterval) throws {
    var durationParsed: TimeInterval = 0
    var didInsert = false

    for (idx, tag) in playlist.tags.enumerated() {
      guard case .segmentInfo(let segmentDuration, _) = tag else { continue }
      durationParsed += segmentDuration
      if durationParsed >= duration {
        playlist.tags.insert(contentsOf: tagsToInsert, at: idx + 1)
        didInsert = true
        break
      }
    }

    if !didInsert {
      // duration was longer than this playlist
      throw Abort.playlistError
    }
  }

  mutating func correctTargetDurationIfNecessary() throws {
    var maxDuration: Double = 0
    var targetDurationTagIndex: Int? = nil
    for (idx, tag) in playlist.tags.enumerated() {
      switch tag {
      case .targetDuration:
        targetDurationTagIndex = idx
      case .segmentInfo(let duration, _):
        maxDuration = max(maxDuration, duration)
      default:
        continue
      }
    }

    if let index = targetDurationTagIndex {
      playlist.tags[index] = .targetDuration(Int(ceil(maxDuration)))
    } else {
      throw Abort.playlistError
    }
  }

  // MARK: Information

  func allSegments(fillingInterval: TimeInterval = TimeInterval.greatestFiniteMagnitude, addDiscontinuityMarkers: Bool = false, withKey key: EncryptionKey? = nil) -> [PlaylistTag] {
    var segments = [PlaylistTag]()
    var durationAdded: TimeInterval = 0
    for tag in playlist.tags {
      guard case .segmentInfo(let duration, _) = tag else { continue }
      segments.append(tag)
      durationAdded += duration
      if durationAdded >= fillingInterval {
        break
      }
    }

    if addDiscontinuityMarkers {
      segments.insert(.discontinuity, at: 0)
      segments.append(.discontinuity)
      segments.insert(.key(playlist.encryptionKey ?? .none), at: 1)
      segments.append(.key(key ?? .none))
    }
    return segments
  }

  // MARK: Private

  private func expandedURI(fromURI uri: String, playlistURL: URL) throws -> String {
    guard let tagURI = URL(string: uri) else { throw Abort.playlistError }
    if tagURI.host == nil {
      return playlistURL.appendingPathComponent(tagURI.path).absoluteString
    } else {
      return uri
    }
  }
}
