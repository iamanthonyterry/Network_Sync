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
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    stepRow(step, index: index)
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

    private func stepRow(_ step: WorkflowStep, index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: step.kind.icon)
                .foregroundStyle(step.kind.color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.kind.title).font(.body)
                Text(step.action.summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()

            VStack(spacing: 0) {
                Button {
                    guard index > 0 else { return }
                    steps.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)

                Button {
                    guard index < steps.count - 1 else { return }
                    steps.move(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(index == steps.count - 1)
            }
            .font(.caption)

            Button {
                editingStep = step
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)

            Button {
                steps.remove(at: index)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
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
                Picker("", selection: $schedule.mode) {
                    ForEach(ScheduleMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                switch schedule.mode {
                case .daily:
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
                    if schedule.repeatDaily {
                        weekdaySelector
                    }

                case .oneTime:
                    DatePicker(
                        "Run At",
                        selection: $schedule.oneTimeDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    Text("Runs once at the selected date and time, then turns off.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var weekdaySelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Runs On").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(Weekday.allCases) { day in
                    let isOn = schedule.selectedWeekdays.contains(day)
                    Button {
                        if isOn {
                            schedule.selectedWeekdays.remove(day)
                        } else {
                            schedule.selectedWeekdays.insert(day)
                        }
                    } label: {
                        Text(day.shortLabel)
                            .font(.caption).bold()
                            .frame(width: 32, height: 28)
                            .background(isOn ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                            .foregroundStyle(isOn ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(schedule.displayWeekdays)
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.top, 2)
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
