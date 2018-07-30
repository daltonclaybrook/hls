//
//  PlaylistTag+Parser.swift
//  media-server
//
//  Created by Dalton Claybrook on 2/20/17.
//
//

import Foundation

extension StreamInfo {
  public init(params: [String: String]) {
    programID = params["PROGRAM-ID"].flatMap(Int.init)
    bandwidth = params["BANDWIDTH"].flatMap(Int.init)
    resolution = params["RESOLUTION"].flatMap(Resolution.init)
    codecs = params["CODECS"]
  }

  public var stringValue: String {
    var outComponents: [String] = []
    // programID is deprecated, so we do not export it.
    if let bandwidth = bandwidth {
      outComponents.append("BANDWIDTH=\(bandwidth)")
    }
    if let resolution = resolution {
      outComponents.append("RESOLUTION=\(resolution.stringValue)")
    }
    if let codecs = codecs {
      // codecs has quotes around the value
      outComponents.append("CODECS=\"\(codecs)\"")
    }
    return outComponents.joined(separator: ",")
  }
}

extension Resolution {
  public init?(string: String) {
    let components = string.components(separatedBy: "x")
    guard
      components.count == 2,
      let width = Int(components[0]),
      let height = Int(components[1])
    else { return nil }

    self.width = width
    self.height = height
  }

  public var stringValue: String {
    return "\(width)x\(height)"
  }
}

extension EncryptionKey {
  public init(params: [String: String]) {
    method = params["METHOD"]
    uri = params["URI"]
    iv = params["IV"]
  }

  public var stringValue: String {
    var outComponents: [String] = []
    if let method = method {
      outComponents.append("METHOD=\(method)")
    }
    if let uri = uri {
      outComponents.append("URI=\"\(uri)\"")
    }
    if let iv = iv {
      outComponents.append("IV=\(iv)")
    }
    return outComponents.joined(separator: ",")
  }
}

extension PlaylistType {
  public init(components: [String]) {
    self = components.first.flatMap(PlaylistType.init) ?? .live
  }

  public var stringValue: String? {
    // live events don't use a playlist tag
    return self != .live ? "\(rawValue)" : nil
  }
}

public extension PlaylistTag {
  public init?(components: [String], contents: String?) {
    guard components.count > 0 else { return nil }

    var components = components
    let name = components.removeFirst()
    let params = components.first.flatMap { [String: String](paramString: $0) } ?? [:]

    switch name {
    case "EXTM3U":
      self = .header
    case "EXT-X-STREAM-INF":
      if let uri = contents {
        self = .streamInfo(StreamInfo(params: params), uri: uri)
      } else { return nil }
    case "EXT-X-VERSION":
      if let version = components.first.flatMap(Int.init) {
        self = .version(version)
      } else { return nil }
    case "EXT-X-MEDIA-SEQUENCE":
      if let sequence = components.first.flatMap(Int.init) {
        self = .sequence(sequence)
      } else { return nil }
    case "EXT-X-TARGETDURATION":
      if let duration = components.first.flatMap(Int.init) {
        self = .targetDuration(duration)
      } else { return nil }
    case "EXT-X-KEY":
      self = .key(EncryptionKey(params: params))
    case "EXTINF":
      let durationString = components.first?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
      if let uri = contents, let duration = durationString.flatMap({ Double($0) }) {
        self = .segmentInfo(duration: duration, uri: uri)
      } else { return nil }
    case "EXT-X-ENDLIST":
      self = .endList
    case "EXT-X-DISCONTINUITY":
      self = .discontinuity
    case "EXT-X-DISCONTINUITY-SEQUENCE":
      if let sequence = components.first.flatMap(Int.init) {
        self = .discontinuitySequence(sequence)
      } else { return nil }
    case "EXT-X-PLAYLIST-TYPE":
      self = .playlistType(PlaylistType(components: components))
    default:
      return nil
    }
  }

  public var stringValue: String {
    switch self {
    case .header:
      return "#EXTM3U"
    case let .streamInfo(streamInfo, uri):
      return "#EXT-X-STREAM-INF:\(streamInfo.stringValue)\n\(uri)"
    case let .version(version):
      return "#EXT-X-VERSION:\(version)"
    case let .sequence(sequence):
      return "#EXT-X-MEDIA-SEQUENCE:\(sequence)"
    case let .targetDuration(duration):
      return "#EXT-X-TARGETDURATION:\(duration)"
    case let .key(key):
      return "#EXT-X-KEY:\(key.stringValue)"
    case let .segmentInfo(duration, uri):
      // these have a comma at the end of the tag line. This is how they come out of elastic transcoder.
      return "#EXTINF:\(duration),\n\(uri)"
    case .endList:
      return "#EXT-X-ENDLIST"
    case .discontinuity:
      return "#EXT-X-DISCONTINUITY"
    case let .discontinuitySequence(sequence):
      return "#EXT-X-DISCONTINUITY-SEQUENCE:\(sequence)"
    case let .playlistType(type):
      return type.stringValue.flatMap { "#EXT-X-PLAYLIST-TYPE:\($0)" } ?? ""
    }
  }
}

extension Dictionary {
  init?(paramString: String) {
    var outDict = [Key: Value]()
    let scanner = Scanner(string: paramString)
    while !scanner.isAtEnd {
      guard let key = scanner.ms_scanUpToString("=") else { break }
      _ = scanner.ms_scanString("=")
      var value: String? = nil
      if scanner.ms_scanString("\"") != nil {
        value = scanner.ms_scanUpToString("\"")
        _ = scanner.ms_scanString("\"")
      } else {
        value = scanner.ms_scanUpToString(",")
      }
      _ = scanner.ms_scanString(",")

      if let key = key as? Key, let value = value as? Value {
        outDict[key] = value
      }
    }

    if !outDict.isEmpty {
      self = outDict
    } else {
      return nil
    }
  }
}
