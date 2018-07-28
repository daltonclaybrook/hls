//
//  Tag.swift
//  media-server
//
//  Created by Dalton Claybrook on 2/19/17.
//
//

import Foundation

public struct StreamInfo {
  public typealias BPS = Int // bits per second

  public let programID: Int?
  public let bandwidth: BPS?
  public let resolution: Resolution?
  public let codecs: String?
}

public struct Resolution {
  public let width: Int
  public let height: Int
}

public struct EncryptionKey {
  public let method: String?
  public var uri: String?
  public let iv: String?

  static var none: EncryptionKey {
    return EncryptionKey(method: "NONE", uri: nil, iv: nil)
  }
}

public enum PlaylistType: String {
  case vod = "VOD"
  case event = "EVENT"
  case live
}

public enum PlaylistTag {
  case header
  case streamInfo(StreamInfo, uri: String)
  case version(Int)
  case sequence(Int)
  case targetDuration(Int)
  case key(EncryptionKey)
  case segmentInfo(duration: Double, uri: String)
  case endList
  case discontinuity
  case discontinuitySequence(Int)
  case playlistType(PlaylistType)
}
