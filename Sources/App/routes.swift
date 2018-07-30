import Vapor

/// Register your application's routes here.
public func routes(_ router: Router) throws {
  // Basic "Hello, world!" example
  router.get("hello") { req in
    return "Hello, world!"
  }

  let baseURL = Environment.get("BASE_URL") ?? "http://localhost:8080"
  let playlistController = PlaylistController(baseURL: baseURL)
  router.get("master", use: playlistController.getMaster)
  router.get("media", use: playlistController.getMedia)
  router.post("start-stitching", use: playlistController.startStitching)

  router.post("live/start", use: playlistController.startLive)
  router.get("live/master", use: playlistController.getFakeLiveMaster)
  router.get("live/media", use: playlistController.getFakeLiveMedia)
}
