//
//  ResourceCacheTests.swift
//  ZillaTests
//

import Testing
@testable import Zilla
import BugzillaKit
import Foundation

@MainActor
struct ResourceCacheTests {

    @Test func cacheMissTriggersFetchAndStoresValue() async throws {
        let cache = ResourceCache()
        var calls = 0
        let value: Int = try await cache.fetch(key: CacheKey.bug(123), force: false) {
            calls += 1
            return 42
        }
        #expect(value == 42)
        #expect(calls == 1)
        #expect(cache.get(CacheKey.bug(123), as: Int.self) == 42)
    }

    @Test func freshCacheHitSkipsFetch() async throws {
        let cache = ResourceCache()
        var calls = 0
        let _: Int = try await cache.fetch(key: CacheKey.bug(123), force: false) {
            calls += 1
            return 42
        }
        let second: Int = try await cache.fetch(key: CacheKey.bug(123), force: false) {
            calls += 1
            return 100
        }
        #expect(second == 42)
        #expect(calls == 1)
    }

    @Test func forceTrueAlwaysFetchesAndReplaces() async throws {
        let cache = ResourceCache()
        var calls = 0
        let _: Int = try await cache.fetch(key: CacheKey.bug(123), force: false) {
            calls += 1
            return 42
        }
        let second: Int = try await cache.fetch(key: CacheKey.bug(123), force: true) {
            calls += 1
            return 100
        }
        #expect(second == 100)
        #expect(calls == 2)
        #expect(cache.get(CacheKey.bug(123), as: Int.self) == 100)
    }

    @Test func invalidateForcesNextFetch() async throws {
        let cache = ResourceCache()
        var calls = 0
        let _: Int = try await cache.fetch(key: CacheKey.bug(123), force: false) {
            calls += 1
            return 42
        }
        cache.invalidate(CacheKey.bug(123))
        let second: Int = try await cache.fetch(key: CacheKey.bug(123), force: false) {
            calls += 1
            return 100
        }
        #expect(second == 100)
        #expect(calls == 2)
    }

    @Test func invalidateBugClearsAllRelatedKeys() async throws {
        let cache = ResourceCache()
        let _: Int = try await cache.fetch(key: CacheKey.bug(123), force: false) { 1 }
        let _: Int = try await cache.fetch(key: CacheKey.comments(bugID: 123), force: false) { 2 }
        let _: Int = try await cache.fetch(key: CacheKey.dependencyMeta(123), force: false) { 3 }
        cache.invalidateBug(id: 123)
        #expect(cache.get(CacheKey.bug(123), as: Int.self) == nil)
        #expect(cache.get(CacheKey.comments(bugID: 123), as: Int.self) == nil)
        #expect(cache.get(CacheKey.dependencyMeta(123), as: Int.self) == nil)
    }

    @Test func concurrentCallsDedupToSingleFetch() async throws {
        let cache = ResourceCache()
        let counter = CallCounter()
        async let a: Int = cache.fetch(key: CacheKey.bug(123), force: false) {
            await counter.increment()
            try await Task.sleep(for: .milliseconds(50))
            return 42
        }
        async let b: Int = cache.fetch(key: CacheKey.bug(123), force: false) {
            await counter.increment()
            try await Task.sleep(for: .milliseconds(50))
            return 99
        }
        let av = try await a
        let bv = try await b
        #expect(av == bv)
        #expect(await counter.value == 1)
    }

    @Test func clearRemovesAllEntries() async throws {
        let cache = ResourceCache()
        let _: Int = try await cache.fetch(key: CacheKey.bug(1), force: false) { 1 }
        let _: Int = try await cache.fetch(key: CacheKey.bug(2), force: false) { 2 }
        cache.clear()
        #expect(cache.get(CacheKey.bug(1), as: Int.self) == nil)
        #expect(cache.get(CacheKey.bug(2), as: Int.self) == nil)
    }

    @Test func versionBumpsOnStore() async throws {
        let cache = ResourceCache()
        let initial = cache.version
        let _: Int = try await cache.fetch(key: CacheKey.bug(1), force: false) { 1 }
        #expect(cache.version > initial)
    }

    @Test func freshnessReportsMissingThenFresh() async throws {
        let cache = ResourceCache()
        #expect(cache.freshness(for: CacheKey.bug(1)) == .missing)
        let _: Int = try await cache.fetch(key: CacheKey.bug(1), force: false) { 1 }
        #expect(cache.freshness(for: CacheKey.bug(1)) == .fresh)
    }

    @Test func invalidateCancelsInflightAndAllowsFreshFetch() async throws {
        let cache = ResourceCache()
        var providerCalls = 0

        let slowFetch = Task<Int, Error> {
            try await cache.fetch(key: CacheKey.bug(1), force: false) {
                providerCalls += 1
                try await Task.sleep(for: .milliseconds(500))
                return 1
            }
        }

        try await Task.sleep(for: .milliseconds(50))
        cache.invalidate(CacheKey.bug(1))

        var slowFetchCancelled = false
        do {
            _ = try await slowFetch.value
        } catch is CancellationError {
            slowFetchCancelled = true
        }
        #expect(slowFetchCancelled)

        let result: Int = try await cache.fetch(key: CacheKey.bug(1), force: false) {
            providerCalls += 1
            return 2
        }
        #expect(result == 2)
        #expect(cache.get(CacheKey.bug(1), as: Int.self) == 2)
        #expect(providerCalls == 2)
    }

    @Test func staleInflightDoesNotOverwriteFreshResult() async throws {
        let cache = ResourceCache()

        let stale = Task<Int, Error> {
            try await cache.fetch(key: CacheKey.bug(1), force: false) {
                try await Task.sleep(for: .milliseconds(300))
                return 1  // pre-update value
            }
        }

        try await Task.sleep(for: .milliseconds(30))
        cache.invalidate(CacheKey.bug(1))

        let fresh: Int = try await cache.fetch(key: CacheKey.bug(1), force: true) {
            return 2  // post-update value
        }
        #expect(fresh == 2)
        #expect(cache.get(CacheKey.bug(1), as: Int.self) == 2)

        _ = try? await stale.value
        #expect(cache.get(CacheKey.bug(1), as: Int.self) == 2)
    }
}

actor CallCounter {
    var value = 0
    func increment() { value += 1 }
}
