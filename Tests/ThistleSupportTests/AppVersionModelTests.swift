import Foundation
import Testing

@testable import ThistleSupport

struct AppVersionModelTests {
  @Test func releaseTagGreaterThanCurrentVersion() throws {
    let current = try #require(AppVersionModel("1.0"))
    let latest = try #require(AppVersionModel("v1.0.1"))
    #expect(latest > current)
  }

  @Test func equivalentVersionsCanUseDifferentComponentCounts() throws {
    let short = try #require(AppVersionModel("1.0"))
    let long = try #require(AppVersionModel("1.0.0"))
    #expect(short == long)
  }

  @Test func buildMetadataDoesNotAffectComparison() throws {
    let current = try #require(AppVersionModel("1.2.3+260208.0706"))
    let latest = try #require(AppVersionModel("v1.2.4"))
    #expect(latest > current)
  }

  @Test func latestVersionCanBeSeveralReleasesAhead() throws {
    let current = try #require(AppVersionModel("1.0.0"))
    let latest = try #require(AppVersionModel("v1.3.0"))
    #expect(latest > current)
  }

  @Test func numericComponentsAreNotComparedLexicographically() throws {
    let current = try #require(AppVersionModel("1.9.0"))
    let latest = try #require(AppVersionModel("v1.10.0"))
    #expect(latest > current)
  }

  @Test func earlierMinorVersionIsNotGreaterWhenPatchIsHigher() throws {
    let current = try #require(AppVersionModel("1.10.0"))
    let older = try #require(AppVersionModel("v1.9.9"))
    #expect(older < current)
  }
}
