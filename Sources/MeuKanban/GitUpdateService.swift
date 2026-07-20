import AppKit
import Foundation

/// Busca atualizações no repositório Git quando o app é executado a partir
/// de uma cópia do projeto que tenha um remoto e uma branch configurada.
@MainActor
final class GitUpdateService: ObservableObject {
    @Published var updateAvailable = false
    @Published var updateMessage = ""
    @Published var updateResultMessage: String?

    private var repositoryURL: URL?

    func checkForUpdate() async {
        guard let repository = findRepository() else { return }
        repositoryURL = repository

        let status = await runGit(["status", "--porcelain"], at: repository)
        guard status.exitCode == 0, status.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let fetch = await runGit(["fetch", "--quiet"], at: repository)
        guard fetch.exitCode == 0 else { return }

        let behind = await runGit(["rev-list", "--count", "HEAD..@{u}"], at: repository)
        guard behind.exitCode == 0,
              let commits = Int(behind.output.trimmingCharacters(in: .whitespacesAndNewlines)), commits > 0 else { return }

        updateMessage = "Há \(commits) atualização(ões) disponível(is) no repositório. Deseja baixar a nova versão agora?"
        updateAvailable = true
    }

    func update() async {
        guard let repository = repositoryURL else { return }
        let result = await runGit(["pull", "--ff-only"], at: repository)
        updateResultMessage = result.exitCode == 0
            ? "Atualização baixada. Feche e abra o app novamente para usar a nova versão."
            : "Não foi possível atualizar automaticamente. Verifique a conexão e o repositório Git."
    }

    private func findRepository() -> URL? {
        var current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        while current.path != "/" {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(".git").path) { return current }
            current.deleteLastPathComponent()
        }
        return nil
    }

    private func runGit(_ arguments: [String], at directory: URL) async -> (exitCode: Int32, output: String) {
        await Task.detached {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            task.arguments = arguments
            task.currentDirectoryURL = directory
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            do {
                try task.run()
                task.waitUntilExit()
                let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
                return (task.terminationStatus, String(decoding: bytes, as: UTF8.self))
            } catch {
                return (-1, "")
            }
        }.value
    }
}
