//
//  PlaylistBuilder.swift
//  hls-server
//
//  Created by Dalton Claybrook on 6/11/17.
//
//

import Foundation
import Vapor

struct MediaCounts {
  let mediaSequence: Int
  let discontinuitySequence: Int
  let segmentCount: Int
}

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

  mutating func stitch(
    playlist stitchPlaylist: Playlist,
    atMediaSequence stitchSequence: Int,
    withOriginalDiscontinuitySequence discontinuitySequence: Int
  ) throws {
    var segmentsToStitch = stitchPlaylist.tags.filter { $0.isSegmentInfo }
    let mediaSequence = playlist.mediaSequence
    let segmentsToRemove = min(max(0, mediaSequence - stitchSequence), segmentsToStitch.count)
    segmentsToStitch.removeFirst(segmentsToRemove)

    var hasInsertedDiscontinuity = segmentsToRemove != 0
    var addToIndex = 0

    var addToDiscontinuity = 0
    if segmentsToRemove > 0 {
      addToDiscontinuity += 1
    }
    if segmentsToStitch.isEmpty {
      addToDiscontinuity += 1
    }
    if let indexOfDiscontinuitySequence = playlist.tags.index(where: { $0.isDiscontinuitySequence }) {
      playlist.tags[indexOfDiscontinuitySequence] = .discontinuitySequence(discontinuitySequence + addToDiscontinuity)
    }

    var tagIndex = -1
    zip(0..., playlist.tags).forEach { values in
      let (index, tag) = values
      guard tag.isSegmentInfo else { return }
      tagIndex += 1

      guard
        tagIndex + mediaSequence >= stitchSequence,
        !segmentsToStitch.isEmpty
      else { return }

      if !hasInsertedDiscontinuity {
        hasInsertedDiscontinuity = true
        playlist.tags.insert(.discontinuity, at: index + addToIndex)
        addToIndex += 1
      }
      let stitchSegment = segmentsToStitch.removeFirst()
      playlist.tags[index + addToIndex] = stitchSegment

      if segmentsToStitch.isEmpty {
        playlist.tags.insert(.discontinuity, at: index + addToIndex + 1)
      }
    }

    try correctTargetDurationIfNecessary()
  }

  mutating func convertToLivePlaylist(withStartDate startDate: Date) {
    let currentDate = Date()
    let timeSinceStart = currentDate.timeIntervalSince(startDate)
    let segments = playlist.tags.filter { $0.isSegmentInfo }

    var startIndex = 0
    var totalTime: TimeInterval = 0
    for (index, segment) in zip(0..., segments) {
      guard case let .segmentInfo(duration, _) = segment else { continue }
      totalTime += duration
      if totalTime >= timeSinceStart {
        startIndex = index
        break
      }
    }

    let endIndex = min(startIndex + 5, segments.count)
    let finalSegments = segments[startIndex..<endIndex]
    var finalTags: [PlaylistTag] = [
      .header,
      .targetDuration(playlist.targetDuration),
      .version(4),
      .sequence(startIndex),
      .discontinuitySequence(0)
    ]
    finalTags.append(contentsOf: finalSegments)
    playlist.tags = finalTags
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

  func getCounts() -> MediaCounts {
    var mediaSequence = 0
    var discontinuitySequence = 0
    var segmentCount = 0
    playlist.tags.forEach { tag in
      switch tag {
      case let .sequence(value):
        mediaSequence = value
      case let .discontinuitySequence(value):
        discontinuitySequence = value
      case .segmentInfo:
        segmentCount += 1
      default:
        break
      }
    }
    return MediaCounts(
      mediaSequence: mediaSequence,
      discontinuitySequence: discontinuitySequence,
      segmentCount: segmentCount
    )
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

extension PlaylistTag {
  var isSegmentInfo: Bool {
    if case .segmentInfo = self {
      return true
    } else {
      return false
    }
  }

  var isDiscontinuitySequence: Bool {
    if case .discontinuitySequence = self {
      return true
    } else {
      return false
    }
  }
}
