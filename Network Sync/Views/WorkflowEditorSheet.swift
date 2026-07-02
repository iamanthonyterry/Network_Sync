import SwiftUI

/// Create or edit a Workflow: name, target devices, an ordered list of
/// steps, and an optional schedule of its own.
struct WorkflowEditorSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let existingWorkflow: Workflow?

    @State private var name: String
    @State private var steps: [WorkflowStep]
    @State private var targetDeckIDs: Set<UUID>
    @State private var schedule: ScheduleSettings
    @State private var editingStep: WorkflowStep? = nil

    init(workflow: Workflow?) {
        existingWorkflow = workflow
        _name          = State(initialValue: workflow?.name ?? "")
        _steps         = State(initialValue: workflow?.steps ?? [])
        _targetDeckIDs = State(initialValue: Set(workflow?.targetDeckIDs ?? []))
        _schedule      = State(initialValue: workflow?.schedule ?? ScheduleSettings())
    }

    var canSave: Bool { !name.isEmpty && !steps.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List {
                detailsSection
                targetDevicesSection
                stepsSection
                scheduleSection
            }
            .listStyle(.inset)
        }
        .frame(width: 520, height: 620)
        .sheet(item: $editingStep) { step in
            if let index = steps.firstIndex(where: { $0.id == step.id }) {
                WorkflowStepConfigSheet(step: $steps[index])
            }
        }
    }

    private var header: some View {
        HStack {
            Text(existingWorkflow == nil ? "New Workflow" : "Edit Workflow")
                .font(.title2).bold()
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button(existingWorkflow == nil ? "Create" : "Save") { save() }
                .buttonStyle(.borderedProminent).disabled(!canSave)
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Details

    private var detailsSection: some View {
        Section("Details") {
            TextField("Workflow Name", text: $name)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Target Devices

    private var targetDevicesSection: some View {
        Section("Runs On") {
            Toggle("All Devices", isOn: Binding(
                get: { targetDeckIDs.isEmpty },
                set: { if $0 { targetDeckIDs.removeAll() } }
            ))
            if !appState.hyperDecks.isEmpty {
                ForEach(appState.hyperDecks) { deck in
                    Toggle(deck.name, isOn: Binding(
                        get: { targetDeckIDs.isEmpty || targetDeckIDs.contains(deck.id) },
                        set: { isOn in
                            if isOn {
                                targetDeckIDs.insert(deck.id)
                                if targetDeckIDs.count == appState.hyperDecks.count { targetDeckIDs.removeAll() }
                            } else {
                                if targetDeckIDs.isEmpty { targetDeckIDs = Set(appState.hyperDecks.map(\.id)) }
                                targetDeckIDs.remove(deck.id)
                            }
                        }
                    ))
                }
            } else {
                Text("No devices configured yet.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Steps

    private var stepsSection: some View {
        Section {
            if steps.isEmpty {
                Text("Add steps below to build your workflow.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(steps) { step in
                    stepRow(step)
                }
                .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { steps.remove(atOffsets: $0) }
            }
            addStepMenu
        } header: {
            Text("Steps")
        } footer: {
            Text("Steps run in order, top to bottom. Files flow from one step to the next.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func stepRow(_ step: WorkflowStep) -> some View {
        HStack(spacing: 10) {
            Image(systemName: step.kind.icon)
                .foregroundStyle(step.kind.color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.kind.title).font(.body)
                Text(step.action.summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                editingStep = step
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture { editingStep = step }
    }

    private var addStepMenu: some View {
        Menu {
            ForEach(StepKind.allCases) { kind in
                Button {
                    steps.append(WorkflowStep(action: .defaultAction(for: kind)))
                } label: {
                    Label(kind.title, systemImage: kind.icon)
                }
            }
        } label: {
            Label("Add Step", systemImage: "plus.circle.fill")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        Section("Schedule") {
            Toggle("Run Automatically", isOn: $schedule.isEnabled)
            if schedule.isEnabled {
                HStack(spacing: 8) {
                    Stepper(value: $schedule.hour, in: 0...23) {
                        Text(String(format: "%02d", schedule.hour)).monospacedDigit().frame(width: 28)
                    }
                    Text(":")
                    Stepper(value: $schedule.minute, in: 0...59, step: 5) {
                        Text(String(format: "%02d", schedule.minute)).monospacedDigit().frame(width: 28)
                    }
                    Text(schedule.displayTime).font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
                }
                Toggle("Repeat Daily", isOn: $schedule.repeatDaily)
            }
        }
    }

    // MARK: - Save

    private func save() {
        var workflow = existingWorkflow ?? Workflow(name: name)
        workflow.name = name
        workflow.steps = steps
        workflow.targetDeckIDs = Array(targetDeckIDs)
        workflow.schedule = schedule

        if existingWorkflow == nil {
            appState.addWorkflow(workflow)
        } else {
            appState.updateWorkflow(workflow)
        }
        SchedulerService.shared.sync()
        dismiss()
    }
}
