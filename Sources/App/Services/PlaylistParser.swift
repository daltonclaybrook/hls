//
//  PlaylistParser.swift
//  media-server
//
//  Created by Dalton Claybrook on 2/18/17.
//
//

import Foundation

public final class PlaylistParser {
  public static let shared = PlaylistParser()

  enum ParserError: Error {
    case invalidData, invalidString, noTags
  }

  //MARK: Public

  public func parse(playlistData: Data) throws -> Playlist {
    guard let playlistString = String(data: playlistData, encoding: .utf8)?.strippingTrailingCommas() else {
      throw ParserError.invalidData
    }
    let scanner = Scanner(string: playlistString)

    var tags = [PlaylistTag]()
    while !scanner.isAtEnd {
      guard let tag = scanTag(with: scanner) else { continue }
      tags.append(tag)
    }

    if tags.count <= 0 {
      throw ParserError.noTags
    }
    return Playlist(tags: tags)
  }

  public func generatePlaylistData(with playlist: Playlist) throws -> Data {
    let playlistString = playlist.tags.map { $0.stringValue }.joined(separator: "\n")
    return playlistString.convertToData()
  }

  //MARK: Private

  private func scanTag(with scanner: Scanner) -> PlaylistTag? {
    guard scanner.ms_scanString("#") != nil else { return nil }
    guard let tagString = scanner.ms_scanUpToString("\n") else { return nil }
    let components = tagString.components(separatedBy: ":")
    let contents = scanContents(with: scanner)
    return PlaylistTag(components: components, contents: contents)
  }

  private func scanContents(with scanner: Scanner) -> String? {
    _ = scanner.ms_scanString("\n")
    var contents = scanner.ms_scanUpToString("#")?.trimmingCharacters(in: .whitespacesAndNewlines)
    if contents?.isEmpty ?? false {
      contents = nil
    }
    return contents
  }
}

extension Scanner {
  func ms_scanUpToString(_ string: String) -> String? {
    #if os(Linux)
    return scanUpToString(string)
    #else
    var outString: NSString? = nil
    scanUpTo(string, into: &outString)
    return outString as String?
    #endif
  }

  func ms_scanString(_ string: String) -> String? {
    #if os(Linux)
    return scanString(string)
    #else
    var outString: NSString? = nil
    scanString(string, into: &outString)
    return outString as String?
    #endif
  }
}

extension String {
  func strippingTrailingCommas() -> String {
    return replacingOccurrences(of: ",\n", with: "\n")
  }
}
