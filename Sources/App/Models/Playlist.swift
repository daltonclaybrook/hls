//
//  M3U8.swift
//  media-server
//
//  Created by Dalton Claybrook on 2/18/17.
//
//

import Foundation

public struct Playlist {
  var tags: [PlaylistTag]

  init(tags: [PlaylistTag] = []) {
    self.tags = tags
  }
}
