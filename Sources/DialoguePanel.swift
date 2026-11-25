// mSLICE — onglet « Dialogues » du panneau de droite (design Flat Mat, d'après maquettes/dialogues.html) : choix de la source du texte, extraction,
// liste des répliques (recherche, écoute, corrections), bouton d'envoi à mCASTING (désactivé : étape suivante).
import AppKit
import SwiftUI

struct DialoguePanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var doc: Doc
    @ObservedObject var dialogues: DialogueModel

    var body: some View {
        switch dialogues.phase {
        case .source: DialogueSource(dialogues: dialogues, doc: doc)
        case .extracting: VStack(spacing: 0) { Spacer(minLength: 0); DialogueRunning(dialogues: dialogues); Spacer(minLength: 0) }
        case .list: DialogueList(dialogues: dialogues)
        }
    }
}

// MARK: - Source

private struct SourceRow: View {
    let title: String
    var value: String?
    var on = false
    var enabled = true
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().strokeBorder(on ? Theme.accent : Theme.text2.opacity(0.5), lineWidth: 1.5).frame(width: 14, height: 14)
                    if on { Circle().fill(Theme.accent).frame(width: 7, height: 7) }
                }
                Text(title).font(.system(size: 12.5, weight: on ? .semibold : .regular)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                if let value { Text(value).font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(1) }
            }
            .padding(.horizontal, 10).frame(height: 34).contentShape(Rectangle())
            .background(on ? Theme.ctl : .clear, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.5)
    }
}

private struct DialogueSource: View {
    @ObservedObject var dialogues: DialogueModel
    let doc: Doc
    var body: some View {
        let embedded = dialogues.sources.filter(\.isEmbedded), files = dialogues.sources.filter { !$0.isEmbedded }
        let subs: Bool = { if case .subtitles = dialogues.choice { return true } else { return false } }()
        VStack(spacing: 10) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    Card(padding: 10, spacing: 2) {
                        SectionTitle(L.t("dlg.src.title")).padding(.horizontal, 2).padding(.bottom, 4)
                        if embedded.isEmpty { SourceRow(title: L.t("dlg.src.embedded.row"), value: L.t("dlg.src.none"), enabled: false) }
                        ForEach(embedded) { s in SourceRow(title: dialogues.title(s), on: dialogues.choice == .subtitles(s.id)) { dialogues.choice = .subtitles(s.id) } }
                        if files.isEmpty { SourceRow(title: L.t("dlg.src.file.row"), value: L.t("dlg.src.none"), enabled: false) }
                        ForEach(files) { s in SourceRow(title: dialogues.title(s), on: dialogues.choice == .subtitles(s.id)) { dialogues.choice = .subtitles(s.id) } }
                        SourceRow(title: L.t("dlg.src.transcribe"), value: dialogues.canTranscribe ? languageLabel : nil, on: dialogues.choice == .transcribe, enabled: dialogues.canTranscribe) { dialogues.choice = .transcribe }
                            .overlay(alignment: .trailing) {
                                if dialogues.canTranscribe {
                                    Menu { ForEach(TranscriptionSupport.languages, id: \.code) { l in Button(l.label) { dialogues.setLanguage(l.code); dialogues.choice = .transcribe } } } label: { Color.clear.frame(width: 100, height: 34) }
                                        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 100, height: 34)
                                }
                            }
                        Text(note(subs: subs, hasSubs: !dialogues.sources.isEmpty)).font(.system(size: 11)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 2)
                    }
                    if let f = dialogues.failure {
                        Text(L.t(f)).font(.system(size: 11.5)).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                    }
                    if dialogues.askInstall { installCard }
                    if dialogues.installing {
                        Card(padding: 12) { HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L.t("dlg.installing")).font(.system(size: 12)).foregroundStyle(Theme.text2) } }
                    }
                }
            }
            VStack(spacing: 6) {
                Button { dialogues.start() } label: { Text(L.t("dlg.go")).frame(maxWidth: .infinity) }
                    .buttonStyle(FlatButton(kind: .primary, height: 36)).disabled(!canGo).opacity(canGo ? 1 : 0.4)
                Text(L.t(subs ? "dlg.go.time.subs" : "dlg.go.time")).font(.system(size: 11)).foregroundStyle(Theme.text2)
                if dialogues.hasLines { Button { dialogues.backToList() } label: { Text(L.t("dlg.back")).frame(maxWidth: .infinity) }.buttonStyle(FlatButton()) }
            }
        }
    }

    private var languageLabel: String { (TranscriptionSupport.languages.first { $0.code == dialogues.language }?.label ?? dialogues.language) + " ▾" }

    private var canGo: Bool {
        if dialogues.askInstall || dialogues.installing { return false }
        if dialogues.choice == .transcribe { return dialogues.canTranscribe }
        return true
    }

    private func note(subs: Bool, hasSubs: Bool) -> String {
        if subs { return L.t("dlg.note.subs") }
        if !TranscriptionSupport.available { return L.t("dlg.unsupported") }
        if doc.info.audio == nil { return L.t("dlg.noaudio") }
        return L.t(hasSubs ? "dlg.note.transcribe" : "dlg.note.nosubs")
    }

    private var installCard: some View {
        Card(padding: 12, spacing: 8) {
            Text(L.t("dlg.install.title")).font(.system(size: 13, weight: .semibold))
            Text(L.t("dlg.install.body", TranscriptionSupport.languages.first { $0.code == dialogues.language }?.label ?? dialogues.language))
                .font(.system(size: 11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { dialogues.acceptInstall() } label: { Text(L.t("dlg.install.go")).frame(maxWidth: .infinity) }.buttonStyle(FlatButton(kind: .primary))
                Button { dialogues.askInstall = false } label: { Text(L.t("dlg.cancel")).frame(maxWidth: .infinity) }.buttonStyle(FlatButton())
            }
        }
    }
}

// MARK: - Extraction

private struct DialogueRunning: View {
    @ObservedObject var dialogues: DialogueModel
    var body: some View {
        let speech = dialogues.step == "speech"
        Card(padding: 16, spacing: 12) {
            Text(L.t("dlg.running")).font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.ctl)
                    Capsule().fill(Theme.accent).frame(width: max(g.size.width * (speech ? dialogues.progress : 0.5), 6))
                }
            }.frame(height: 6)
            VStack(alignment: .leading, spacing: 7) {
                step(L.t(speech ? "dlg.step.speech" : "dlg.step.subs"), state: speech ? (dialogues.progress >= 0.999 ? .done : .running) : .running,
                     value: speech ? "\(Int(dialogues.progress * 100)) %" : L.t("dlg.step.now"))
                step(L.t("dlg.step.split"), state: speech && dialogues.progress >= 0.999 ? .running : .waiting, value: speech && dialogues.progress >= 0.999 ? L.t("dlg.step.now") : "")
            }
            Button { dialogues.cancel() } label: { Text(L.t("dlg.cancel")).frame(minWidth: 90) }.buttonStyle(FlatButton()).frame(maxWidth: .infinity)
        }
    }
    private enum StepState { case done, running, waiting }
    private func step(_ title: String, state: StepState, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: state == .done ? "checkmark" : "circle").font(.system(size: 11, weight: .semibold)).frame(width: 16)
                .foregroundStyle(state == .done ? Theme.ok : state == .running ? Theme.accent : Theme.text2.opacity(0.5))
            Text(title).font(.system(size: 12)).foregroundStyle(state == .waiting ? Theme.text2 : Theme.text)
            Spacer(minLength: 0)
            Text(state == .waiting && value.isEmpty ? L.t("dlg.step.wait") : value).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2)
        }
    }
}

// MARK: - Liste

private struct DialogueList: View {
    @ObservedObject var dialogues: DialogueModel
    @State private var draft = ""
    @State private var cursor = 0

    var body: some View {
        VStack(spacing: 10) {
            header
            let lines = dialogues.visible
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(lines) { l in row(l).id(l.id) }
                        if lines.isEmpty { Text(L.t("dlg.none")).font(.system(size: 12)).foregroundStyle(Theme.text2).padding(.top, 20) }
                    }
                }
                .onChange(of: dialogues.selected) { _, id in if let id, dialogues.editing == nil { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } } }
            }
            footer
        }
    }

    private var header: some View {
        Card(padding: 10, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.t("dlg.list.title", dialogues.activeCount)).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 4)
                if let s = dialogues.data { Text(L.t(s.kind == .subtitles ? "dlg.from.subtitles" : "dlg.from.transcript", s.detail)).font(.system(size: 11)).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.middle) }
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text2)
                TextField(L.t("dlg.search"), text: $dialogues.query).textFieldStyle(.plain).font(.system(size: 12))
                if !dialogues.query.isEmpty { Button { dialogues.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.text2) }.buttonStyle(.plain) }
            }.padding(.horizontal, 10).frame(height: 28).background(Theme.ctl, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
            HStack(spacing: 6) {
                if dialogues.discardedCount > 0 {
                    Button { dialogues.showDiscarded.toggle() } label: { Chip(text: L.t("dlg.discarded", dialogues.discardedCount), on: dialogues.showDiscarded) }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Button { dialogues.changeSource() } label: { Chip(text: L.t("dlg.change")) }.buttonStyle(.plain)
            }
        }
    }

    private func row(_ l: DialogueLine) -> some View {
        let on = dialogues.selected == l.id, editing = dialogues.editing == l.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.time(l.start)).font(.system(size: 10.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.text2).frame(width: 44, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    if let w = l.who { Tag(text: w, kind: .accent) }
                    if editing { editor(l) } else {
                        Text(l.text).font(.system(size: 12.5)).foregroundStyle(l.discarded ? Theme.text2 : Theme.text)
                            .strikethrough(l.discarded).fixedSize(horizontal: false, vertical: true)
                    }
                    if !editing, l.corrected || l.discarded {
                        HStack(spacing: 4) { if l.corrected { Tag(text: L.t("dlg.tag.corrected"), kind: .warn) }; if l.discarded { Tag(text: L.t("dlg.tag.discarded")) } }
                    }
                }
                Spacer(minLength: 0)
            }
            if on && !editing {
                HStack(spacing: 6) {
                    Button { dialogues.listen(l) } label: { Text("▶ " + L.t("dlg.listen")).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity) }.buttonStyle(FlatButton(height: 26))
                    Button { begin(l) } label: { Text(L.t("dlg.edit")).frame(maxWidth: .infinity) }.buttonStyle(FlatButton(height: 26))
                    Button { dialogues.setDiscarded(l.id, !l.discarded) } label: { Text(L.t(l.discarded ? "dlg.restore" : "dlg.discard")).frame(maxWidth: .infinity) }.buttonStyle(FlatButton(height: 26))
                }.font(.system(size: 11.5))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous).strokeBorder(on ? Theme.accent : Theme.line, lineWidth: on ? 1.2 : 0.5))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if !editing { dialogues.select(l.id); begin(l) } }
        .onTapGesture { if !editing { dialogues.select(l.id) } }
    }

    private func begin(_ l: DialogueLine) { draft = l.text; cursor = 0; dialogues.editing = l.id }

    private func editor(_ l: DialogueLine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LineEditor(text: $draft, cursor: $cursor).frame(height: 74)
                .background(Theme.ctl, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(L.t("dlg.edit.hint")).font(.system(size: 10.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button { dialogues.setText(l.id, draft); dialogues.editing = nil } label: { Text(L.t("dlg.save")).frame(maxWidth: .infinity) }.buttonStyle(FlatButton(kind: .primary, height: 26))
                Button { dialogues.setText(l.id, draft); dialogues.split(l.id, at: cursor); dialogues.editing = nil } label: { Text(L.t("dlg.split")).frame(maxWidth: .infinity) }
                    .buttonStyle(FlatButton(height: 26)).disabled(cursor <= 0 || cursor >= draft.count).opacity(cursor <= 0 || cursor >= draft.count ? 0.4 : 1)
                Button { dialogues.editing = nil } label: { Text(L.t("dlg.cancel")).frame(maxWidth: .infinity) }.buttonStyle(FlatButton(height: 26))
            }.font(.system(size: 11.5))
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Button {} label: { Text(L.t("dlg.send", dialogues.activeCount)).frame(maxWidth: .infinity) }
                .buttonStyle(CastButton()).disabled(true).opacity(0.45)
            Text(L.t("dlg.send.soon")).font(.system(size: 10.5)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
            HStack(spacing: 5) { Key("Espace"); Text(L.t("dlg.keys.listen")).font(.system(size: 10.5)).foregroundStyle(Theme.text2) }
        }
    }
}

/// Bouton vert d'envoi à mCASTING.
private struct CastButton: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 12.5, weight: .semibold)).padding(.horizontal, 12).frame(height: 38).foregroundStyle(.white)
            .background(Theme.ok, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous)).opacity(c.isPressed ? 0.85 : 1)
    }
}

/// Zone de texte à plusieurs lignes qui rend la position du curseur (pour « couper en deux ici »).
private struct LineEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursor: Int
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let tv = NSTextView()
        tv.isRichText = false; tv.allowsUndo = true; tv.drawsBackground = false
        tv.font = .systemFont(ofSize: 12.5); tv.textColor = Theme.textNS
        tv.textContainerInset = NSSize(width: 4, height: 5)
        tv.isHorizontallyResizable = false; tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        tv.delegate = context.coordinator
        tv.string = text
        let sv = NSScrollView(); sv.documentView = tv; sv.hasVerticalScroller = false; sv.drawsBackground = false
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return sv
    }
    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let tv = sv.documentView as? NSTextView, tv.string != text else { return }
        tv.string = text
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LineEditor
        init(_ p: LineEditor) { parent = p }
        func textDidChange(_ n: Notification) { guard let tv = n.object as? NSTextView else { return }; parent.text = tv.string; parent.cursor = tv.selectedRange().location }
        func textViewDidChangeSelection(_ n: Notification) { guard let tv = n.object as? NSTextView else { return }; parent.cursor = tv.selectedRange().location }
    }
}
