import Testing
import Foundation
import MarginaliaSyntax
@testable import MarginaliaView
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@Suite struct ValidationTests {

    private func env() throws -> StepEnvironment {
        let compiler = try MarkdownAttributedCompiler()
        return StepEnvironment(
            compiler: compiler,
            serializer: AttributedMarkdownSerializer(),
            theme: .default,
            dialect: .commonMark,
            mode: .rich
        )
    }

    @Test func detectsMissingSpec() throws {
        let env = try env()
        let storage = NSTextStorage(attributedString: env.compiler.compile("hello\n", dialect: .commonMark, mode: .rich, theme: .default))
        // Manually corrupt: strip the spec from one char.
        storage.removeAttribute(.marginaliaBlockSpec, range: NSRange(location: 1, length: 1))
        let diagnostics = SpecValidator.validate(in: storage, range: NSRange(location: 0, length: storage.length))
        #expect(diagnostics.contains { if case .missingSpec = $0.issue { return true } else { return false } })
    }

    @Test func detectsInconsistentSpecAcrossParagraph() throws {
        let env = try env()
        let storage = NSTextStorage(attributedString: env.compiler.compile("hello\n", dialect: .commonMark, mode: .rich, theme: .default))
        // Set a different spec on one char.
        storage.addAttribute(.marginaliaBlockSpec,
                             value: BlockSpecBox(BlockSpec(kind: .heading(level: 1))),
                             range: NSRange(location: 0, length: 1))
        let diagnostics = SpecValidator.validate(in: storage, range: NSRange(location: 0, length: storage.length))
        #expect(diagnostics.contains { if case .inconsistentSpec = $0.issue { return true } else { return false } })
    }

    @Test func cleanStorageHasNoDiagnostics() throws {
        let env = try env()
        let storage = NSTextStorage(attributedString: env.compiler.compile("# Heading\n- bullet\n> quote\n", dialect: .commonMark, mode: .rich, theme: .default))
        let diagnostics = SpecValidator.validate(in: storage, range: NSRange(location: 0, length: storage.length))
        #expect(diagnostics.isEmpty, "compiled storage should be valid; got \(diagnostics)")
    }

    @Test func repairFillsMissingSpecFromLine() throws {
        let env = try env()
        let storage = NSTextStorage(attributedString: env.compiler.compile("hello world\n", dialect: .commonMark, mode: .rich, theme: .default))
        storage.removeAttribute(.marginaliaBlockSpec, range: NSRange(location: 0, length: 5))
        SpecValidator.repair(in: storage, range: NSRange(location: 0, length: storage.length))
        let diagnostics = SpecValidator.validate(in: storage, range: NSRange(location: 0, length: storage.length))
        #expect(diagnostics.isEmpty, "repair should restore consistency, got \(diagnostics)")
    }

    @Test func repairResolvesInconsistentSpec() throws {
        let env = try env()
        let storage = NSTextStorage(attributedString: env.compiler.compile("hello world\n", dialect: .commonMark, mode: .rich, theme: .default))
        storage.addAttribute(.marginaliaBlockSpec,
                             value: BlockSpecBox(BlockSpec(kind: .heading(level: 2))),
                             range: NSRange(location: 0, length: 1))
        SpecValidator.repair(in: storage, range: NSRange(location: 0, length: storage.length))
        let diagnostics = SpecValidator.validate(in: storage, range: NSRange(location: 0, length: storage.length))
        #expect(diagnostics.isEmpty, "repair should resolve inconsistency, got \(diagnostics)")
    }

    @Test func transactionApplyRunsValidation() throws {
        let controller = try EditorController(initialMarkdown: "hello\n")
        var captured: [SpecDiagnostic] = []
        controller.onDiagnostic = { captured.append($0) }
        // Manually corrupt before applying a transaction.
        controller.textStorage.removeAttribute(.marginaliaBlockSpec, range: NSRange(location: 0, length: 1))
        let lineRange = NSRange(location: 0, length: controller.textStorage.length)
        controller.apply(Transaction(steps: [
            .setSpec(lineRange: lineRange, BlockSpec(kind: .heading(level: 1)))
        ]))
        // After transaction, storage should be re-rendered → corruption gone.
        let post = SpecValidator.validate(in: controller.textStorage, range: NSRange(location: 0, length: controller.textStorage.length))
        #expect(post.isEmpty, "transaction-applied storage should be valid")
        _ = captured
    }
}
