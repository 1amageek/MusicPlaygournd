import Darwin
import Foundation
import Testing
import Synchronization
@testable import MusicPlaygourndCore

extension NativeHostTests {
    struct EvaluationProcessCleanupTests {
        @Test(.timeLimit(.minutes(1)), arguments: [0, 3])
        func progressArrivesBeforeProcessExitAndPreservesFailures(exitCode: Int) async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let finished = root.appending(path: "finished")
            let received = Mutex(0)
            let evaluator = SourceEvaluator(packageURL: root, workspace: root, swiftExecutable: "/usr/bin/false")
            let script = """
            import sys, time
            print('Fetching https://example.com/', end='', flush=True)
            time.sleep(0.1)
            print('Music.git', flush=True)
            time.sleep(0.5)
            open(\(finished.path.debugDescription), 'w').close()
            sys.exit(\(exitCode))
            """
            do {
                _ = try await evaluator.run("/usr/bin/python3", ["-c", script], timeout: 5, progress: { message in
                    #expect(message == "Fetching https://example.com/Music.git")
                    #expect(!FileManager.default.fileExists(atPath: finished.path))
                    received.withLock { $0 += 1 }
                })
                #expect(exitCode == 0)
            } catch let error as EvaluationError {
                guard case .processFailed = error else { throw error }
                #expect(exitCode == 3)
            }
            #expect(received.withLock { $0 } == 1)
        }

        @Test(.timeLimit(.minutes(1)), arguments: [false, true])
        func compilerGroupsAreReapedOnTimeoutAndCancellation(cancel: Bool) async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "compiler-cleanup-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer {
                do { try FileManager.default.removeItem(at: directory) }
                catch { Issue.record(error) }
            }
            let identities = directory.appending(path: "children")
            let script = """
            import os, subprocess, time
            os.setsid()
            child = subprocess.Popen(['/usr/bin/python3', '-c', 'import os,time; os.setsid(); time.sleep(60)'])
            time.sleep(0.05)
            with open(\(identities.path.debugDescription), 'w') as output:
                output.write(str(os.getpid()) + ' ' + str(child.pid))
            time.sleep(60)
            """
            let workspace = directory.appending(path: "work")
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            let evaluator = SourceEvaluator(packageURL: directory, workspace: workspace, swiftExecutable: "/usr/bin/false")
            let operation = Task {
                try await evaluator.run("/usr/bin/python3", ["-c", script], timeout: cancel ? 30 : 1)
            }
            if cancel {
                for _ in 0..<100 {
                    if FileManager.default.fileExists(atPath: identities.path) { break }
                    try await Task.sleep(for: .milliseconds(10))
                }
                operation.cancel()
            }
            do {
                _ = try await operation.value
                Issue.record("The compiler operation must fail")
            } catch is CancellationError {
                #expect(cancel)
            } catch let error as EvaluationError {
                guard case .timedOut = error else { throw error }
                #expect(!cancel)
            }
            let pids = try String(contentsOf: identities, encoding: .utf8).split(separator: " ").map {
                try #require(pid_t($0))
            }
            #expect(pids.count == 2)
            for pid in pids {
                #expect(kill(pid, 0) == -1)
                #expect(errno == ESRCH)
            }
            try await evaluator.shutdown()
        }
    }
}
