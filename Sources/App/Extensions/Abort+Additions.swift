//
//  Abort+Additions.swift
//  media-server
//
//  Created by Dalton Claybrook on 2/26/17.
//
//

import Vapor

public extension Abort {
  public static var invalidJSON: Abort {
    return Abort(.badRequest, reason: "The request body did not contain valid JSON or the request did not contain a proper Content-Type header.")
  }

  public static var playlistError: Abort {
    return Abort(.internalServerError, reason: "Something went wrong while generating the playlist")
  }
}
