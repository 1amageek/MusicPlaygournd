import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: SessionModel
    var deckWorkspace: DeckWorkspace? = nil
    @State private var lineRects: [Int: CGRect] = [:]
    @State private var timelineScroll: CGFloat = 0
    @State private var logsExpanded = false
    @State private var playMode = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if model.project == nil && !model.hasOpenDocument && (deckWorkspace == nil || (deckWorkspace?.a.project == nil && deckWorkspace?.b.project == nil && deckWorkspace?.a.hasOpenDocument == false && deckWorkspace?.b.hasOpenDocument == false)) {
                WelcomeView(model: model)
            } else {
                editorWorkspace
            }
        }
        .preferredColorScheme(.dark)
    }

    private var editorWorkspace: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                FileSidebarView(model: model, browser: model.fileBrowser, deckWorkspace: deckWorkspace)
                    .navigationSplitViewColumnWidth(min: 160, ideal: 220, max: 320)
            } detail: {
                VStack(spacing: 0) {
                    if let deckWorkspace {
                        DeckHeaderView(workspace: deckWorkspace)
                        Divider()
                    }
                    workspace
                    Divider()
                    logs
                }
                .ignoresSafeArea(.container, edges: deckWorkspace != nil && columnVisibility != .detailOnly ? .top : [])
            }
            .navigationSplitViewStyle(.balanced)
            .toolbarBackgroundVisibility(deckWorkspace == nil ? .automatic : .hidden, for: .windowToolbar)
            .toolbar {
                if deckWorkspace == nil {
                    ToolbarItem(placement: .principal) { MusicHeaderView(model: model) }
                }
            }
        }
        .background(Color(red: 0.06, green: 0.07, blue: 0.08))
        .preferredColorScheme(.dark)
        .frame(minWidth: 850, minHeight: 540)
        .background(WorkspaceWindowSizeView())
        .background {
            if let deckWorkspace { TrackpadEdgeView(enabled: $playMode, workspace: deckWorkspace) }
        }
        .task {
            while !Task.isCancelled {
                if let deckWorkspace { deckWorkspace.refresh() } else { model.refresh() }
                do { try await Task.sleep(for: .milliseconds(33)) }
                catch { break }
            }
        }
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            if model.hasOpenDocument || deckWorkspace != nil {
                HStack(spacing: 0) {
                    if let deckWorkspace {
                        FileTabsView(model: deckWorkspace.a, accent: deckWorkspace.colorA,
                            deckName: "A", editing: deckWorkspace.selectedDeck == 0,
                            activate: { deckWorkspace.selectedDeck = 0 }, load: { deckWorkspace.loadSelected(0) })
                        Divider()
                        FileTabsView(model: deckWorkspace.b, accent: deckWorkspace.colorB,
                            deckName: "B", editing: deckWorkspace.selectedDeck == 1,
                            activate: { deckWorkspace.selectedDeck = 1 }, load: { deckWorkspace.loadSelected(1) })
                    } else { FileTabsView(model: model) }
                    layoutMenu.padding(.horizontal, 6)
                }
                .frame(height: 30)
                Divider()
            }
            Group {
                if model.hasOpenDocument {
                    VSplitView {
                        HSplitView {
                            editor
                            if !model.inlineLayout && !model.bottomLayout {
                                TimelineView(loop: model.editorLoop, rowLines: model.rowLines, lineRects: lineRects, beatPosition: model.beatPosition, isPlaying: model.isPlaying, onScroll: { timelineScroll += $0 }, mutedTracks: model.rowMuteStates, onToggleTrackMute: model.toggleTrackMute)
                                    .frame(minWidth: 340)
                            }
                        }
                        if !model.inlineLayout && model.bottomLayout { rhythm }
                    }
                } else {
                    Text("No Selection").font(.system(size: 20)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var layoutMenu: some View {
        let menu = Menu {
            Picker("Rhythm display", selection: Binding(
                get: { model.inlineLayout ? 0 : (model.bottomLayout ? 2 : 1) },
                set: { layout in
                    model.inlineLayout = layout == 0
                    model.bottomLayout = layout == 2
                }
            )) {
                Text("Inline Results").tag(0)
                Text("Side Timeline").tag(1)
                Text("Bottom Overview").tag(2)
            }.pickerStyle(.inline)
        } label: {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 36, height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Rhythm display layout")
        .accessibilityIdentifier("editor-layout-menu")
        .help("Rhythm display layout")

        if #available(macOS 26.0, *) {
            menu.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            menu.background(.regularMaterial, in: Capsule())
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            CodeEditor(text: $model.source, inlineLoop: model.editorLoop, inlineEnabled: model.inlineLayout, resultLines: model.resultLines,
                beatPosition: model.beatPosition, isPlaying: model.isPlaying, selectionLine: model.selectionLine, selectionToken: model.selectionToken,
                rhythmLines: Array(Set(model.rowLines.values)).sorted(), rowLines: model.rowLines,
                patternTexts: Dictionary(uniqueKeysWithValues: (model.editorLoop?.rows ?? []).compactMap { row in row.patternText.map { (row.sourceID, $0) } }),
                activeTokens: model.activeTokens,
                scrollDelta: timelineScroll, onLayout: { lineRects = $0 },
                beforeEdit: model.beforeEdit, onEdit: model.sourceChanged,
                completions: { source, offset in try await model.completions(source: source, utf16Offset: offset) },
                onCompletionStatus: { model.completionStatus = $0 },
                semanticTokens: { try await model.semanticTokens(source: $0) },
                syntaxContext: model.syntaxContext, onHighlightStatus: { model.highlightingStatus = $0 },
                isReadOnly: model.activeDocument.isReadOnly,
                switches: model.switches, switchSelections: model.switchSelections,
                switchesEnabled: model.switchesEnabled, onSelectSwitch: model.selectSwitch,
                activeSwitchRanges: model.activeSwitchRanges,
                sliders: model.inlineSliders, sliderValues: model.inlineSliderValues, onSliderChange: model.setInlineSlider,
                mutedTracks: model.rowMuteStates, onToggleTrackMute: model.toggleTrackMute,
                onFormat: { try await model.formatSource($0) },
                onFormatFailure: { model.hostDiagnostic = $0 }, selectionRange: model.selectionRange, visualization: model.editorLoop == nil ? nil : model.controlVisualization,
                documentID: model.activeDocumentID, editorState: model.activeDocument.editorState, openDocumentIDs: Set((deckWorkspace.map { $0.a.documents + $0.b.documents } ?? model.documents).map(\.id)),
                onEditorStateChange: { id, state in model.documents.first { $0.id == id }?.editorState = state })
        }.frame(minWidth: 350, minHeight: 220)

    }

    @ViewBuilder
    private var logs: some View {
        DisclosureGroup(isExpanded: $logsExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if !model.diagnostic.isEmpty {
                    Button { model.revealDiagnostic() } label: {
                        Label("Edit needs attention", systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.diagnosticRange == nil)
                    ScrollView {
                        Text(model.diagnostic)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 130)
                }
                if !model.hostDiagnostic.isEmpty {
                    Text(model.hostDiagnostic).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.orange).textSelection(.enabled)
                }
                if diagnosticCount == 0 {
                    Text("No diagnostics")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if !model.highlightingStatus.isEmpty {
                    Text(model.highlightingStatus)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if !model.completionStatus.isEmpty {
                    Divider()
                    Text(model.completionStatus)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .help(model.completionStatus)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: diagnosticCount == 0 ? "doc.text" : "exclamationmark.circle.fill")
                    .foregroundStyle(diagnosticCount == 0 ? Color.secondary : Color.orange)
                Text("Logs")
                Spacer()
                Text(diagnosticCountLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(diagnosticCount == 0 ? Color.secondary : Color.orange)
                    .padding(.trailing, deckWorkspace == nil ? 0 : 96)
            }
        }
        .overlay(alignment: .topTrailing) {
            if deckWorkspace != nil {
                Button { playMode.toggle() } label: {
                    Text("Play Mode").font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9).frame(height: 20)
                        .background(playMode ? Color.orange : Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(playMode ? .black : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play Mode")
                .accessibilityValue(playMode ? "On. Press Escape to exit." : "Off")
                .help("Play Mode: two fingers anywhere adjust crossfade. One finger on left/right edge scratches A/B; bottom edge adjusts crossfade. Escape exits.")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(height: logsExpanded ? nil : 36)
        .background(diagnosticCount == 0 ? Color.white.opacity(0.025) : Color.orange.opacity(0.07))
    }

    private var diagnosticCount: Int { (model.diagnostic.isEmpty ? 0 : 1) + (model.hostDiagnostic.isEmpty ? 0 : 1) }

    private var diagnosticCountLabel: String {
        let count = diagnosticCount
        return "\(count) error\(count == 1 ? "" : "s")"
    }

    private var rhythm: some View {
        VStack(spacing: 0) {
        RhythmView(loop: model.editorLoop, beatPosition: model.beatPosition, isPlaying: model.isPlaying, revealTrack: model.revealTrack, mutedTracks: model.rowMuteStates, onToggleTrackMute: model.toggleTrackMute)
            .frame(minWidth: 340, minHeight: 230)
        selectedResult
        }
    }
    @ViewBuilder private var selectedResult: some View {
        if model.editorLoop != nil, let visualization = model.controlVisualization {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.visualizationStatus).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                ControlTraceResult(visualization: visualization).frame(height: 88)
            }.padding(8)
        }
    }

}
