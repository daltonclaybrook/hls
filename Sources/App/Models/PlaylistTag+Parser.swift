//
//  PlaylistTag+Parser.swift
//  media-server
//
//  Created by Dalton Claybrook on 2/20/17.
//
//

import Foundation

extension StreamInfo {

  public init(params: [String:String]) {
    programID = params["PROGRAM-ID"].flatMap { Int($0) }
    bandwidth = params["BANDWIDTH"].flatMap { Int($0) }
    resolution = params["RESOLUTION"].flatMap { Resolution(string: $0) }
    codecs = params["CODECS"]
  }

  public var stringValue: String {
    var outString = ""
    // programID is deprecated, so we do not export it.
    if let bandwidth = bandwidth {
      outString += "BANDWIDTH=\(bandwidth),"
    }
    if let resolution = resolution {
      outString += "RESOLUTION=\(resolution.stringValue),"
    }
    if let codecs = codecs {
      // codecs has quotes around the value
      outString += "CODECS=\"\(codecs)\","
    }
    if !outString.isEmpty { _ = outString.removeLast() }
    return outString
  }
}

extension Resolution {

  public init?(string: String) {
    let components = string.components(separatedBy: "x")
    guard components.count == 2 else { return nil }
    guard let width = Int(components[0]),
      let height = Int(components[1]) else { return nil }
    self.width = width
    self.height = height
  }

  public var stringValue: String {
    return "\(width)x\(height)"
  }
}

extension EncryptionKey {

  public init(params: [String:String]) {
    method = params["METHOD"]
    uri = params["URI"]
    iv = params["IV"]
  }

  public var stringValue: String {
    var outComponents = [String]()
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
    self = components.first.flatMap { PlaylistType(rawValue: $0) } ?? .live
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
    let params = components.first.flatMap { [String:String](paramString: $0) } ?? [:]

    switch name {
    case "EXTM3U":
      self = .header
    case "EXT-X-STREAM-INF":
      if let uri = contents {
        self = .streamInfo(StreamInfo(params: params), uri: uri)
      } else { return nil }
    case "EXT-X-VERSION":
      if let version = components.first.flatMap({ Int($0) }) {
        self = .version(version)
      } else { return nil }
    case "EXT-X-MEDIA-SEQUENCE":
      if let sequence = components.first.flatMap({ Int($0) }) {
        self = .sequence(sequence)
      } else { return nil }
    case "EXT-X-TARGETDURATION":
      if let duration = components.first.flatMap({ Int($0) }) {
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
      if let sequence = components.first.flatMap({ Int($0) }) {
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
    case .streamInfo(let streamInfo, let uri):
      return "#EXT-X-STREAM-INF:\(streamInfo.stringValue)\n\(uri)"
    case .version(let version):
      return "#EXT-X-VERSION:\(version)"
    case .sequence(let sequence):
      return "#EXT-X-MEDIA-SEQUENCE:\(sequence)"
    case .targetDuration(let duration):
      return "#EXT-X-TARGETDURATION:\(duration)"
    case .key(let key):
      return "#EXT-X-KEY:\(key.stringValue)"
    case .segmentInfo(let duration, let uri):
      // these have a comma at the end of the tag line. This is how they come out of elastic transcoder.
      return "#EXTINF:\(duration),\n\(uri)"
    case .endList:
      return "#EXT-X-ENDLIST"
    case .discontinuity:
      return "#EXT-X-DISCONTINUITY"
    case .discontinuitySequence(let sequence):
      return "#EXT-X-DISCONTINUITY-SEQUENCE:\(sequence)"
    case .playlistType(let type):
      return type.stringValue.flatMap { "#EXT-X-PLAYLIST-TYPE:\($0)" } ?? ""
    }
  }
}

extension Dictionary {
  init?(paramString: String) {
    var outDict = [Key:Value]()
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

    if outDict.count > 0 {
      self = outDict
    } else {
      return nil
    }
  }
}
