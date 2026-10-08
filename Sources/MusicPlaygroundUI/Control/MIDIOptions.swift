import SwiftUI

public struct MIDIOptions<ID: Hashable>: View {
    let inputs: [HostChoice<ID>]
    let outputs: [HostChoice<ID>]
    @Binding var input: ID?
    @Binding var output: ID?
    @Binding var notes: Bool
    @Binding var clock: String
    let refresh: () -> Void
    let selectedControl: String?
    let learning: Bool
    let bindingDescription: String?
    let learn: () -> Void
    let cancelLearn: () -> Void
    let removeBinding: () -> Void
    @Binding var expanded: Bool

    public init(inputs: [HostChoice<ID>], outputs: [HostChoice<ID>], input: Binding<ID?>, output: Binding<ID?>,
                notes: Binding<Bool>, clock: Binding<String>, refresh: @escaping () -> Void,
                selectedControl: String?, learning: Bool, bindingDescription: String?,
                learn: @escaping () -> Void, cancelLearn: @escaping () -> Void, removeBinding: @escaping () -> Void,
                expanded: Binding<Bool>) {
        self.inputs = inputs; self.outputs = outputs; self._input = input; self._output = output
        self._notes = notes; self._clock = clock; self.refresh = refresh
        self.selectedControl = selectedControl; self.learning = learning; self.bindingDescription = bindingDescription
        self.learn = learn; self.cancelLearn = cancelLearn; self.removeBinding = removeBinding
        self._expanded = expanded
    }

    public var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("DEVICES").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: refresh) { Label("Refresh", systemImage: "arrow.clockwise").contentShape(Rectangle()) }
                        .buttonStyle(.borderless).accessibilityLabel("Refresh MIDI devices")
                }
                device(title: "Input", symbol: "arrow.down.to.line", choices: inputs, selection: $input, identifier: "midi-input")
                device(title: "Output", symbol: "arrow.up.to.line", choices: outputs, selection: $output, identifier: "midi-output")
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Send loop notes", isOn: $notes).disabled(output == nil)
                        #if os(macOS)
                        .toggleStyle(.checkbox)
                        #else
                        .toggleStyle(.switch).controlSize(.small)
                        #endif
                        .accessibilityIdentifier("midi-notes").contentShape(Rectangle())
                    Text(output == nil ? "Choose an output to send notes." : "Send the accepted score to the selected output.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label("Clock", systemImage: "metronome").font(.system(size: 12, weight: .medium))
                    HStack(spacing: 4) {
                        clockButton("Off", value: "off", enabled: true)
                        clockButton("Send", value: "send", enabled: output != nil)
                        clockButton("Receive", value: "receive", enabled: input != nil)
                    }.accessibilityIdentifier("midi-clock")
                    Text(clock == "send" ? "Send this deck’s tempo and transport." : clock == "receive" ? "Follow the selected input’s clock and transport." : "This deck uses its own tempo.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Label("MIDI Learn", systemImage: "slider.horizontal.3").font(.system(size: 12, weight: .medium))
                    Text(selectedControl ?? "Select a control to assign MIDI.")
                        .font(.system(size: 12)).foregroundStyle(selectedControl == nil ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("midi-learn-target")
                    if learning {
                        Label("Move a knob on your MIDI controller…", systemImage: "dot.radiowaves.left.and.right")
                            .foregroundStyle(.mint).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    } else if let bindingDescription {
                        Text(bindingDescription).font(.system(size: 11, design: .monospaced)).foregroundStyle(.mint)
                    } else if input == nil {
                        Text("Choose an input to learn a control.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(learning ? "Cancel Learn" : "Learn") { if learning { cancelLearn() } else { learn() } }
                            .disabled(!learning && (input == nil || selectedControl == nil))
                            .contentShape(Rectangle()).accessibilityIdentifier("midi-learn")
                        if bindingDescription != nil {
                            Button("Remove", action: removeBinding).contentShape(Rectangle()).accessibilityLabel("Remove MIDI binding")
                        }
                    }.buttonStyle(.bordered).controlSize(.small)
                }
            }.padding(.top, 12)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "pianokeys").foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MIDI").font(.system(size: 13, weight: .semibold))
                    Text(input == nil && output == nil ? "No devices selected" : "\(input == nil ? "Input off" : "Input selected") · \(output == nil ? "Output off" : "Output selected")")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.frame(minHeight: 36).contentShape(Rectangle())
                .accessibilityElement(children: .combine).accessibilityLabel("MIDI Options")
        }.contentShape(Rectangle())
            .padding(12).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.08)))
    }

    private func device(title: String, symbol: String, choices: [HostChoice<ID>], selection: Binding<ID?>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium))
            Picker(title, selection: selection) {
                Text("None").tag(Optional<ID>.none)
                ForEach(choices) { Text($0.name).tag(Optional($0.id)) }
            }.labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).frame(minHeight: 34).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle()).accessibilityLabel("MIDI \(title)").accessibilityIdentifier(identifier)
            if choices.isEmpty {
                Text("No \(title.lowercased()) devices available.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
    private func clockButton(_ label: String, value: String, enabled: Bool) -> some View {
        Button { clock = value } label: {
            Text(label).font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).frame(minHeight: 32)
                .background(clock == value ? Color.mint.opacity(0.2) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(clock == value ? .mint : .primary).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled).accessibilityLabel("MIDI clock \(label)")
            .accessibilityIdentifier("midi-clock-\(value)")
            .accessibilityValue(clock == value ? "Selected" : "Not selected")
    }
}
