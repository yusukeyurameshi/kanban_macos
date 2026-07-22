import SwiftUI
import UniformTypeIdentifiers

@main
struct MeuKanbanApp: App {
    @StateObject private var store = KanbanStore()
    @StateObject private var updater = GitUpdateService()

    var body: some Scene {
        WindowGroup("Meu Kanban") {
            ContentView()
                .environmentObject(store)
                .environmentObject(updater)
                .frame(minWidth: 1040, minHeight: 650)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Novo projeto") { store.presentNewProject = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Nova tarefa") { store.presentNewTask = true }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .importExport) {
                Button("Importar Kanban JSON…") { store.importJSON() }
                Button("Exportar Kanban JSON…") { store.exportJSON() }
            }
        }
    }
}

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo, doing, done
    var id: String { rawValue }
    var title: String {
        switch self { case .todo: "A fazer"; case .doing: "Em andamento"; case .done: "Concluídas" }
    }
    var symbol: String {
        switch self { case .todo: "circle"; case .doing: "circle.dotted"; case .done: "checkmark.circle.fill" }
    }
}

enum TaskPriority: String, Codable, CaseIterable, Identifiable {
    case critical, attention, controlled
    var id: String { rawValue }
    var title: String {
        switch self { case .critical: "Crítico"; case .attention: "Atenção"; case .controlled: "Sob controle" }
    }
    var color: Color {
        switch self { case .critical: .red; case .attention: .yellow; case .controlled: .green }
    }
}

struct KanbanTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var details: String = ""
    var projectID: UUID
    var status: TaskStatus = .todo
    var priority: TaskPriority = .controlled
    var dueDate: Date?
    var createdAt = Date()

    init(id: UUID = UUID(), title: String, details: String = "", projectID: UUID, status: TaskStatus = .todo, priority: TaskPriority = .controlled, dueDate: Date? = nil, createdAt: Date = Date()) {
        self.id = id; self.title = title; self.details = details; self.projectID = projectID
        self.status = status; self.priority = priority; self.dueDate = dueDate; self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey { case id, title, details, projectID, status, priority, dueDate, createdAt }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        details = try container.decodeIfPresent(String.self, forKey: .details) ?? ""
        projectID = try container.decode(UUID.self, forKey: .projectID)
        status = try container.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .todo
        priority = try container.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .controlled
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

struct Project: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var color: String
}

struct KanbanData: Codable {
    var projects: [Project]
    var tasks: [KanbanTask]
    var updatedAt = Date()
}

@MainActor
final class KanbanStore: ObservableObject {
    @Published var data: KanbanData = .init(projects: [], tasks: []) { didSet { save() } }
    @Published var selection: SidebarSelection? = .overview
    @Published var presentNewProject = false
    @Published var presentNewTask = false
    @Published var taskBeingEdited: KanbanTask?
    @Published var errorMessage: String?

    enum SidebarSelection: Hashable { case overview, project(UUID) }

    private let fileManager = FileManager.default
    private lazy var storageURL: URL = {
        let folder = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Meu Kanban", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("kanban.json")
    }()

    init() { load() }

    func tasks(for project: Project, includingDone: Bool = true) -> [KanbanTask] {
        data.tasks.filter { $0.projectID == project.id && (includingDone || $0.status != .done) }
    }

    func move(_ id: UUID, to status: TaskStatus) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        data.tasks[index].status = status
        data.updatedAt = Date()
    }

    func addProject(name: String, color: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        let project = Project(name: cleanName, color: color)
        data.projects.append(project)
        selection = .project(project.id)
    }

    func addTask(title: String, details: String, projectID: UUID, priority: TaskPriority, dueDate: Date?) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        data.tasks.append(KanbanTask(title: cleanTitle, details: details, projectID: projectID, priority: priority, dueDate: dueDate))
    }

    func deleteTask(_ task: KanbanTask) { data.tasks.removeAll { $0.id == task.id } }

    func updateTask(_ task: KanbanTask) {
        guard let index = data.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        data.tasks[index] = task
        data.updatedAt = Date()
    }

    /// Atualiza a cor das tarefas conforme o prazo, sem reduzir uma
    /// sinalização já elevada. É seguro executar esta rotina repetidamente.
    func refreshPriorities(for now: Date = Date()) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var changed = false

        for index in data.tasks.indices {
            guard let dueDate = data.tasks[index].dueDate else { continue }
            let dueDay = calendar.startOfDay(for: dueDate)

            if dueDay < today, data.tasks[index].priority != .critical {
                data.tasks[index].priority = .critical
                changed = true
            } else if calendar.isDate(dueDay, inSameDayAs: today), data.tasks[index].priority == .controlled {
                data.tasks[index].priority = .attention
                changed = true
            }
        }

        if changed { data.updatedAt = now }
    }

    private func load() {
        let url = storageURL
        if let decoded = decode(from: url) { data = decoded; return }
        guard let bundled = Bundle.module.url(forResource: "kanban", withExtension: "json"),
              let initial = decode(from: bundled) else { return }
        data = initial
    }

    private func decode(from url: URL) -> KanbanData? {
        guard let bytes = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(KanbanData.self, from: bytes)
    }

    private func save() {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        do { try encoder.encode(data).write(to: storageURL, options: .atomic) }
        catch { errorMessage = "Não foi possível salvar o arquivo kanban.json." }
    }

    func importJSON() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let imported = decode(from: url) else { errorMessage = "Este arquivo não é um kanban.json válido."; return }
        data = imported
    }

    func exportJSON() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "kanban.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        do { try encoder.encode(data).write(to: url, options: .atomic) }
        catch { errorMessage = "Não foi possível exportar o arquivo JSON." }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: KanbanStore
    @EnvironmentObject private var updater: GitUpdateService

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selection) {
                Section("Visões") {
                    Label("Todas as pendentes", systemImage: "square.grid.2x2").tag(KanbanStore.SidebarSelection.overview)
                }
                Section("Projetos") {
                    ForEach(store.data.projects) { project in
                        Label(project.name, systemImage: "circle.fill")
                            .foregroundStyle(Color(hex: project.color))
                            .tag(KanbanStore.SidebarSelection.project(project.id))
                    }
                }
            }
            .navigationTitle("Meu Kanban")
            .toolbar { ToolbarItem { Button { store.presentNewProject = true } label: { Label("Projeto", systemImage: "folder.badge.plus") } } }
        } detail: {
            Group {
                switch store.selection ?? .overview {
                case .overview: OverviewBoard()
                case .project(let id):
                    if let project = store.data.projects.first(where: { $0.id == id }) { ProjectBoard(project: project) }
                    else { ContentUnavailableView("Projeto não encontrado", systemImage: "folder.badge.questionmark") }
                }
            }
            .toolbar { ToolbarItem(placement: .primaryAction) { Button { store.presentNewTask = true } label: { Label("Nova tarefa", systemImage: "plus") } } }
        }
        .sheet(isPresented: $store.presentNewProject) { NewProjectSheet() }
        .sheet(isPresented: $store.presentNewTask) { NewTaskSheet() }
        .sheet(item: $store.taskBeingEdited) { EditTaskSheet(task: $0) }
        .task {
            store.refreshPriorities()
            await updater.checkForUpdate()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1_800))
                guard !Task.isCancelled else { break }
                store.refreshPriorities()
            }
        }
        .alert("Nova versão disponível", isPresented: $updater.updateAvailable) {
            Button("Agora") { Task { await updater.update() } }
            Button("Depois", role: .cancel) {}
        } message: { Text(updater.updateMessage) }
        .alert("Atualização", isPresented: Binding(get: { updater.updateResultMessage != nil }, set: { if !$0 { updater.updateResultMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(updater.updateResultMessage ?? "") }
        .alert("Atenção", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(store.errorMessage ?? "") }
    }
}

struct OverviewBoard: View {
    @EnvironmentObject private var store: KanbanStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Header(title: "Todas as tarefas", subtitle: "Tarefas agrupadas por projeto")
                ForEach(store.data.projects) { project in
                    ProjectLane(project: project, tasks: store.tasks(for: project))
                }
                if store.data.projects.isEmpty { ContentUnavailableView("Nenhum projeto", systemImage: "folder.badge.plus", description: Text("Crie um projeto para começar.")) }
            }.padding(28)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ProjectLane: View {
    let project: Project; let tasks: [KanbanTask]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(project.name, systemImage: "circle.fill").font(.headline).foregroundStyle(Color(hex: project.color))
            ScrollView(.horizontal, showsIndicators: false) { HStack(alignment: .top, spacing: 14) { ForEach(TaskStatus.allCases) { status in TaskColumn(status: status, tasks: tasks.filter { $0.status == status }) } } }
        }
    }
}

struct ProjectBoard: View {
    @EnvironmentObject private var store: KanbanStore
    let project: Project
    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 22) {
                Header(title: project.name, subtitle: "Arraste as tarefas entre as colunas")
                HStack(alignment: .top, spacing: 16) {
                    ForEach(TaskStatus.allCases) { status in TaskColumn(status: status, tasks: store.tasks(for: project).filter { $0.status == status }) }
                }
            }.padding(28)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
}

struct Header: View {
    let title: String; let subtitle: String
    var body: some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(.largeTitle.bold()); Text(subtitle).foregroundStyle(.secondary) } }
}

struct TaskColumn: View {
    @EnvironmentObject private var store: KanbanStore
    let status: TaskStatus; let tasks: [KanbanTask]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(status.title)  \(tasks.count)", systemImage: status.symbol).font(.headline).foregroundStyle(status == .done ? .green : .primary)
            VStack(spacing: 9) {
                ForEach(tasks) { task in TaskCard(task: task).draggable(task.id.uuidString) }
            }
            Spacer(minLength: 30)
        }
        .padding(13).frame(width: 285, alignment: .topLeading).frame(minHeight: 390, alignment: .topLeading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
        .dropDestination(for: String.self) { values, _ in
            guard let raw = values.first, let id = UUID(uuidString: raw) else { return false }
            store.move(id, to: status); return true
        }
    }
}

struct TaskCard: View {
    @EnvironmentObject private var store: KanbanStore
    let task: KanbanTask
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(task.priority.color).frame(width: 9, height: 9)
                Text(task.priority.title).font(.caption.weight(.medium)).foregroundStyle(task.priority.color)
            }
            Text(task.title).fontWeight(.semibold).fixedSize(horizontal: false, vertical: true)
            if !task.details.isEmpty { Text(task.details).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            HStack { if let date = task.dueDate { Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(role: .destructive) { store.deleteTask(task) } label: { Image(systemName: "trash") }.buttonStyle(.borderless).opacity(0.55) }
        }
        .padding(12).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(task.priority.color.opacity(0.55), lineWidth: 1)).shadow(color: .black.opacity(0.07), radius: 3, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(count: 2) { store.taskBeingEdited = task }
    }
}

struct NewProjectSheet: View {
    @EnvironmentObject private var store: KanbanStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var color = "4F46E5"
    var body: some View { VStack(alignment: .leading, spacing: 16) { Text("Novo projeto").font(.title2.bold()); TextField("Nome do projeto", text: $name); Picker("Cor", selection: $color) { Text("Índigo").tag("4F46E5"); Text("Azul").tag("2563EB"); Text("Verde").tag("059669"); Text("Laranja").tag("EA580C"); Text("Rosa").tag("DB2777") }.pickerStyle(.segmented); HStack { Spacer(); Button("Cancelar") { dismiss() }; Button("Criar") { store.addProject(name: name, color: color); dismiss() }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) } }.padding(24).frame(width: 420) }
}

struct NewTaskSheet: View {
    @EnvironmentObject private var store: KanbanStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""; @State private var details = ""; @State private var projectID: UUID?; @State private var priority: TaskPriority = .controlled; @State private var hasDate = false; @State private var dueDate = Date()
    var body: some View { VStack(alignment: .leading, spacing: 14) { Text("Nova tarefa").font(.title2.bold()); TextField("Título", text: $title); TextField("Detalhes (opcional)", text: $details); Picker("Projeto", selection: $projectID) { Text("Selecione").tag(UUID?.none); ForEach(store.data.projects) { Text($0.name).tag(Optional($0.id)) } }; Picker("Sinalização", selection: $priority) { ForEach(TaskPriority.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented); Toggle("Definir prazo", isOn: $hasDate); if hasDate { DatePicker("Prazo", selection: $dueDate, displayedComponents: .date) }; HStack { Spacer(); Button("Cancelar") { dismiss() }; Button("Adicionar") { if let id = projectID { store.addTask(title: title, details: details, projectID: id, priority: priority, dueDate: hasDate ? dueDate : nil); dismiss() } }.buttonStyle(.borderedProminent).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || projectID == nil) } }.padding(24).frame(width: 430) }
}

struct EditTaskSheet: View {
    @EnvironmentObject private var store: KanbanStore
    @Environment(\.dismiss) private var dismiss
    let task: KanbanTask
    @State private var title: String
    @State private var details: String
    @State private var projectID: UUID
    @State private var status: TaskStatus
    @State private var priority: TaskPriority
    @State private var hasDate: Bool
    @State private var dueDate: Date

    init(task: KanbanTask) {
        self.task = task
        _title = State(initialValue: task.title)
        _details = State(initialValue: task.details)
        _projectID = State(initialValue: task.projectID)
        _status = State(initialValue: task.status)
        _priority = State(initialValue: task.priority)
        _hasDate = State(initialValue: task.dueDate != nil)
        _dueDate = State(initialValue: task.dueDate ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Editar tarefa").font(.title2.bold())
            TextField("Título", text: $title)
            TextField("Detalhes (opcional)", text: $details)
            Picker("Projeto", selection: $projectID) { ForEach(store.data.projects) { Text($0.name).tag($0.id) } }
            Picker("Status", selection: $status) { ForEach(TaskStatus.allCases) { Text($0.title).tag($0) } }
            Picker("Sinalização", selection: $priority) { ForEach(TaskPriority.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            Toggle("Definir prazo", isOn: $hasDate)
            if hasDate { DatePicker("Prazo", selection: $dueDate, displayedComponents: .date) }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Salvar") {
                    var edited = task
                    edited.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    edited.details = details
                    edited.projectID = projectID
                    edited.status = status
                    edited.priority = priority
                    edited.dueDate = hasDate ? dueDate : nil
                    store.updateTask(edited)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 430)
    }
}

extension Color { init(hex: String) { let value = UInt64(hex, radix: 16) ?? 0; self.init(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1) } }
