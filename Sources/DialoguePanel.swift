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
        case .send: DialogueSend(dialogues: dialogues, doc: doc)
        case .sending: VStack(spacing: 0) { Spacer(minLength: 0); DialogueSending(dialogues: dialogues); Spacer(minLength: 0) }
        case .sent: VStack(spacing: 0) { Spacer(minLength: 0); DialogueSent(dialogues: dialogues); Spacer(minLength: 0) }
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
                    Card(padding: 12, spacing: 6) {
                        HStack {
                            SectionTitle(L.t("dlg.who.title"))
                            Spacer(minLength: 4)
                            if dialogues.hasProtagonists { Tag(text: L.t(dialogues.protagonists.count == 1 ? "dlg.who.tag1" : "dlg.who.tag", dialogues.protagonists.count), kind: .ok) }
                        }
                        Text(L.t(dialogues.hasProtagonists ? "dlg.who.note" : "dlg.who.none")).font(.system(size: 11)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                        if !dialogues.hasProtagonists {
                            Button { UserDefaults.standard.set(2, forKey: "rightTab") } label: { Text(L.t("dlg.who.open")).frame(maxWidth: .infinity) }.buttonStyle(FlatButton()).padding(.top, 2)
                        }
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
                    RoundedRectangle(cornerRadius: Theme.rChip, style: .continuous).fill(Theme.ctl)
                    RoundedRectangle(cornerRadius: Theme.rChip, style: .continuous).fill(Theme.accent).frame(width: max(g.size.width * (speech ? dialogues.progress : 0.5), 6))
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
    @State private var nameDraft = ""
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
            if !dialogues.speakerNames.isEmpty || dialogues.unknownCount > 0 {
                FlowLayout(spacing: 5) {                                   // les filtres passent à la ligne au lieu de déborder à droite
                        Button { dialogues.filter = nil } label: { Chip(text: L.t("dlg.who.all"), on: dialogues.filter == nil) }.buttonStyle(.plain)
                        ForEach(dialogues.speakerNames, id: \.name) { s in
                            Button { dialogues.filter = dialogues.filter == s.name ? nil : s.name } label: { SpeakerChip(dialogues: dialogues, name: s.name, count: s.count, on: dialogues.filter == s.name) }.buttonStyle(.plain)
                        }
                }
            }
            HStack(spacing: 6) {
                if dialogues.hasProtagonists { Button { dialogues.attribute() } label: { Chip(text: L.t("dlg.who.again")) }.buttonStyle(.plain) }
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
                    if let n = dialogues.displayName(l) {
                        HStack(spacing: 5) { Circle().fill(dialogues.color(named: n)).frame(width: 8, height: 8); Text(n).font(.system(size: 10.5, weight: .semibold)).lineLimit(1) }
                            .padding(.horizontal, 8).frame(height: 18).background(Theme.ctl, in: RoundedRectangle(cornerRadius: Theme.rChip, style: .continuous))
                    } else { Tag(text: L.t("dlg.who.unknown"), kind: .warn) }
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
                speakerMenu(l)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous).strokeBorder(on ? Theme.accent : Theme.line, lineWidth: on ? 1.2 : 0.5))
        .contentShape(Rectangle())
        .onTapGesture { if !editing { dialogues.select(l.id) } }                                              // clic simple immédiat (pas d'attente du double-clic)
        .simultaneousGesture(TapGesture(count: 2).onEnded { if !editing { dialogues.select(l.id); begin(l) } })
    }

    private func begin(_ l: DialogueLine) { draft = l.text; nameDraft = l.who ?? ""; cursor = 0; dialogues.editing = l.id }

    /// Choix du personnage d'une réplique : un protagoniste reconnu, un nom déjà employé, ou personne.
    private func speakerMenu(_ l: DialogueLine) -> some View {
        let current = dialogues.displayName(l) ?? L.t("dlg.who.unknown")
        let used = dialogues.speakerNames.map(\.name).filter { n in !dialogues.protagonists.contains { $0.title == n } }
        return Menu {
            ForEach(dialogues.protagonists) { p in Button(p.title) { dialogues.setSpeaker(l.id, protagonist: p.id) } }
            if !used.isEmpty { Divider(); ForEach(used, id: \.self) { n in Button(n) { dialogues.setName(l.id, n) } } }
            Divider()
            Button(L.t("dlg.who.nobody")) { dialogues.setSpeaker(l.id, protagonist: nil) }
        } label: {
            HStack { Text(L.t("dlg.who.menu") + " : " + current).lineLimit(1).truncationMode(.tail); Spacer(minLength: 4); Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)) }
                .font(.system(size: 11.5)).padding(.horizontal, 10).frame(height: 26).frame(maxWidth: .infinity)
                .background(Theme.ctl, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
        }.menuStyle(.borderlessButton).menuIndicator(.hidden)
    }

    private func editor(_ l: DialogueLine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LineEditor(text: $draft, cursor: $cursor).frame(height: 74)
                .background(Theme.ctl, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            TextField(L.t("dlg.who.name.ph"), text: $nameDraft).textFieldStyle(.plain).font(.system(size: 12)).padding(.horizontal, 8).frame(height: 26)
                .background(Theme.ctl, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(L.t("dlg.edit.hint")).font(.system(size: 10.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button { commit(l); dialogues.editing = nil } label: { Text(L.t("dlg.save")).frame(maxWidth: .infinity) }.buttonStyle(FlatButton(kind: .primary, height: 26))
                Button { commit(l); dialogues.split(l.id, at: cursor); dialogues.editing = nil } label: { Text(L.t("dlg.split")).frame(maxWidth: .infinity) }
                    .buttonStyle(FlatButton(height: 26)).disabled(cursor <= 0 || cursor >= draft.count).opacity(cursor <= 0 || cursor >= draft.count ? 0.4 : 1)
                Button { dialogues.editing = nil } label: { Text(L.t("dlg.cancel")).frame(maxWidth: .infinity) }.buttonStyle(FlatButton(height: 26))
            }.font(.system(size: 11.5))
        }
    }

    /// Enregistre le texte et, s'il a changé, le nom du personnage.
    private func commit(_ l: DialogueLine) {
        dialogues.setText(l.id, draft)
        let n = nameDraft.trimmingCharacters(in: .whitespaces)
        if n != (l.who ?? ""), !n.isEmpty { dialogues.setName(l.id, n) }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button { dialogues.addToPieces() } label: { Text(L.t("dlg.pieces.add")).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity) }.buttonStyle(FlatButton())
                    .disabled(dialogues.chosen.isEmpty).opacity(dialogues.chosen.isEmpty ? 0.45 : 1)
                Button { dialogues.exportFiles() } label: {
                    Text(dialogues.exporting ? "\(Int(dialogues.exportProgress * 100)) %" : L.t("dlg.export")).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
                }.buttonStyle(FlatButton()).disabled(dialogues.exporting || dialogues.chosen.isEmpty).opacity(dialogues.exporting || dialogues.chosen.isEmpty ? 0.45 : 1)
            }.font(.system(size: 11.5))
            Button { dialogues.openSend() } label: { Text(L.t("dlg.send", dialogues.activeCount)).frame(maxWidth: .infinity) }
                .buttonStyle(CastButton()).disabled(dialogues.activeCount == 0).opacity(dialogues.activeCount == 0 ? 0.45 : 1)
            HStack(spacing: 5) { Key("Espace"); Text(L.t("dlg.keys.listen")).font(.system(size: 10.5)).foregroundStyle(Theme.text2) }
        }
    }
}

/// Pastille de filtre d'un personnage : vignette de son visage (ou pastille de couleur), nom, nombre de répliques.
private struct SpeakerChip: View {
    @ObservedObject var dialogues: DialogueModel
    let name: String, count: Int, on: Bool
    @State private var image: NSImage?
    var body: some View {
        HStack(spacing: 5) {
            if let image { Image(nsImage: image).resizable().scaledToFill().frame(width: 16, height: 16).clipShape(Circle()).overlay(Circle().strokeBorder(dialogues.color(named: name), lineWidth: 1.5)) }
            else { Circle().fill(dialogues.color(named: name)).frame(width: 8, height: 8) }
            Text("\(name) · \(count)").lineLimit(1)
        }
        .font(.system(size: 11.5, weight: on ? .semibold : .regular))
        .padding(.horizontal, 10).frame(height: 24)
        .foregroundStyle(on ? Theme.onAccent : Theme.text).background(on ? Theme.accent : Theme.ctl, in: RoundedRectangle(cornerRadius: Theme.rChip, style: .continuous))
        .task(id: name) {
            if let person = dialogues.protagonist(named: name)?.person { image = await dialogues.doc.find.avatar(person) }
        }
    }
}

// MARK: - Envoi à mCASTING

private struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool
    var enabled = true
    var body: some View {
        HStack { Text(title).font(.system(size: 12.5)).lineLimit(2).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 6); FlatSwitch(isOn: $isOn) }
            .padding(.vertical, 3).opacity(enabled ? 1 : 0.45).disabled(!enabled)
    }
}

private struct FieldRow: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.text2).frame(width: 58, alignment: .leading)
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(.system(size: 12.5)).padding(.horizontal, 8).frame(height: 28)
                .background(Theme.ctl, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

private struct DialogueSend: View {
    @ObservedObject var dialogues: DialogueModel
    let doc: Doc
    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    Card(padding: 12, spacing: 8) {
                        SectionTitle(L.t("dlg.send.source"))
                        Segmented(options: [("series", L.t("dlg.send.kind.series")), ("film", L.t("dlg.send.kind.film")), ("other", L.t("dlg.send.kind.other"))], selection: $dialogues.cast.kind)
                        FieldRow(label: L.t("dlg.send.title"), text: $dialogues.cast.title)
                        FieldRow(label: L.t("dlg.send.episode"), text: $dialogues.cast.episode, placeholder: L.t("dlg.send.episode.ph"))
                        HStack(spacing: 8) {
                            Text(L.t("dlg.send.lang")).font(.system(size: 11.5)).foregroundStyle(Theme.text2).frame(width: 58, alignment: .leading)
                            Menu {
                                ForEach(TranscriptionSupport.languages, id: \.code) { l in Button(l.label) { dialogues.cast.lang = String(l.code.prefix(2)).lowercased() } }
                            } label: { Text((TranscriptionSupport.languages.first { $0.code.hasPrefix(dialogues.cast.lang) }?.label ?? dialogues.cast.lang) + " ▾").font(.system(size: 12.5)) }
                                .menuStyle(.borderlessButton).fixedSize()
                            Spacer(minLength: 0)
                        }
                    }
                    Card(padding: 12, spacing: 6) {
                        HStack { SectionTitle(L.t("dlg.send.chars")); Spacer(minLength: 4); Text(L.t("dlg.send.chars.sub")).font(.system(size: 10.5)).foregroundStyle(Theme.text2) }
                        let names = dialogues.speakerNames
                        if names.isEmpty { Text(L.t("dlg.send.chars.none")).font(.system(size: 11)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true) }
                        ForEach(names, id: \.name) { n in
                            HStack(spacing: 8) {
                                Circle().fill(dialogues.color(named: n.name)).frame(width: 8, height: 8)
                                TextField(n.name, text: Binding(get: { dialogues.sendNames[n.name] ?? n.name }, set: { dialogues.sendNames[n.name] = $0 }))
                                    .textFieldStyle(.plain).font(.system(size: 12.5)).padding(.horizontal, 8).frame(height: 26)
                                    .background(Theme.ctl, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                Text("\(n.count)").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2).frame(minWidth: 18, alignment: .trailing)
                            }
                        }
                        if dialogues.unknownCount > 0 { Text(L.t("dlg.send.nochar", dialogues.unknownCount)).font(.system(size: 11)).foregroundStyle(Theme.warn) }
                    }
                    Card(padding: 12, spacing: 4) {
                        SectionTitle(L.t("dlg.send.content"))
                        SwitchRow(title: L.t("dlg.send.audio"), isOn: $dialogues.cast.audio, enabled: doc.info.audio != nil)
                        SwitchRow(title: L.t("dlg.send.isolate"), isOn: $dialogues.cast.isolate, enabled: dialogues.cast.audio && dialogues.voiceIsolationAvailable)
                        if dialogues.cast.isolate && dialogues.cast.audio { Text(L.t("dlg.send.isolate.note")).font(.system(size: 11)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true) }
                        SwitchRow(title: L.t("dlg.send.tags"), isOn: $dialogues.cast.tags)
                    }
                    Text(L.t("dlg.send.copyright")).font(.system(size: 10.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                    if let f = dialogues.sendFailure { Text(L.t(f)).font(.system(size: 11.5)).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4) }
                }
            }
            VStack(spacing: 6) {
                let ok = dialogues.castingAvailable && !dialogues.cast.title.trimmingCharacters(in: .whitespaces).isEmpty
                Button { dialogues.send() } label: { Text(L.t("dlg.send", dialogues.sendable.count)).frame(maxWidth: .infinity) }.buttonStyle(CastButton()).disabled(!ok).opacity(ok ? 1 : 0.45)
                if !dialogues.castingAvailable { Text(L.t("dlg.send.nocasting")).font(.system(size: 10.5)).foregroundStyle(Theme.warn) }
                Button { dialogues.closeSend() } label: { Text(L.t("dlg.cancel")).frame(maxWidth: .infinity) }.buttonStyle(FlatButton())
            }
        }
    }
}

private struct DialogueSending: View {
    @ObservedObject var dialogues: DialogueModel
    var body: some View {
        Card(padding: 16, spacing: 12) {
            Text(L.t("dlg.send.running")).font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Theme.rChip, style: .continuous).fill(Theme.ctl)
                    RoundedRectangle(cornerRadius: Theme.rChip, style: .continuous).fill(Theme.ok).frame(width: max(g.size.width * dialogues.sendProgress, 6))
                }
            }.frame(height: 6)
            Text("\(Int(dialogues.sendProgress * 100)) %").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2).frame(maxWidth: .infinity)
            Button { dialogues.cancelSend() } label: { Text(L.t("dlg.cancel")).frame(minWidth: 90) }.buttonStyle(FlatButton()).frame(maxWidth: .infinity)
        }
    }
}

private struct DialogueSent: View {
    @ObservedObject var dialogues: DialogueModel
    var body: some View {
        let r = dialogues.sendResult
        Card(padding: 16, spacing: 10) {
            VStack(spacing: 10) {
                Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(.white).frame(width: 44, height: 44).background(Theme.ok, in: Circle())
                Text(L.t((r?.count ?? 0) == 1 ? "dlg.sent.title1" : "dlg.sent.title", r?.count ?? 0)).font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.center)
                let head = dialogues.cast.title + (dialogues.cast.episode.isEmpty ? "" : " · " + dialogues.cast.episode)
                let who = (r?.perCharacter ?? []).map { "\($0.name) \($0.count)" }.joined(separator: ", ")
                Text(L.t("dlg.sent.body", head + (who.isEmpty ? "." : " — " + who + "."))).font(.system(size: 11.5)).foregroundStyle(Theme.text2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity)
            VStack(spacing: 8) {
                Button { dialogues.openCasting() } label: { Text(L.t("dlg.sent.open")).frame(maxWidth: .infinity) }.buttonStyle(FlatButton(kind: .primary))
                Button { dialogues.finishSend() } label: { Text(L.t("dlg.sent.done")).frame(maxWidth: .infinity) }.buttonStyle(FlatButton())
            }
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
