// mSLICE — onglet « Trouver » du panneau de droite (design Flat Mat, d'après maquettes/trouver.html) :
// avant l'analyse, analyse en cours, résultats (scènes, sons), sélection ET / SAUF avec passages, ajout aux morceaux.
import AppKit
import SwiftUI

struct FindPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var doc: Doc
    @ObservedObject var find: FindModel
    var openEdit: () -> Void

    var body: some View {
        Group {
            if find.running { centered(RunningCard(find: find, doc: doc)) }
            else if find.failed && !find.hasIndex { centered(FailedCard(find: find)) }
            else if !find.hasIndex { centered(BeforeCard(find: find, doc: doc)) }
            else if !find.terms.isEmpty { SelectionView(model: model, doc: doc, find: find) }
            else { ResultsView(model: model, doc: doc, find: find, openEdit: openEdit) }
        }
        .onDisappear { find.thumbs.reset() }
        .onAppear {
            find.listenHandler = { t in
                model.player.seek(t); doc.ensureVisible(t); model.player.play()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { model.player.pause() }
            }
        }
    }

    private func centered<C: View>(_ card: C) -> some View {
        VStack(spacing: 0) { Spacer(minLength: 0); card; Spacer(minLength: 0) }
    }
}

// MARK: - Avant, pendant, échec

private struct BigIcon: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).font(.system(size: 18, weight: .regular)).foregroundStyle(Theme.text2)
            .frame(width: 44, height: 44).background(Theme.ctl, in: Circle())
    }
}

private struct Fact: View {
    let symbol: String, text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.text2).frame(width: 16)
            Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private func duration(_ s: Double) -> String { s < 90 ? L.t("find.dur.s", max(Int(s.rounded()), 1)) : L.t("find.dur.min", Int((s / 60).rounded())) }

private struct BeforeCard: View {
    @ObservedObject var find: FindModel
    let doc: Doc
    var body: some View {
        let audio = doc.info.isAudioOnly
        let estimate = max((doc.duration / 55 / 5).rounded(.up) * 5, 5)
        Card(padding: 16, spacing: 10) {
            VStack(spacing: 10) {
                BigIcon(symbol: "magnifyingglass")
                Text(L.t(audio ? "find.before.title.audio" : "find.before.title")).font(.system(size: 13, weight: .semibold))
                Text(L.t(audio ? "find.before.body.audio" : "find.before.body")).font(.system(size: 11.5)).foregroundStyle(Theme.text2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 5) {
                Fact(symbol: "clock", text: L.t("find.before.time", duration(estimate), Fmt.time(doc.duration, decimals: false)))
                Fact(symbol: "lock", text: L.t("find.before.local"))
                Fact(symbol: "checkmark", text: L.t("find.before.kept"))
            }
            Button { find.start() } label: { Text(L.t("find.analyze")).frame(minWidth: 116) }.buttonStyle(FlatButton(kind: .primary)).frame(maxWidth: .infinity).padding(.top, 4)
        }
    }
}

private struct StepRow: View {
    enum State { case done, running, waiting }
    let state: State, title: String, value: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: state == .done ? "checkmark" : (state == .running ? "circle.dotted" : "circle")).font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(state == .done ? Theme.ok : Theme.text2).frame(width: 16)
            Text(title).font(.system(size: 12)).foregroundStyle(state == .waiting ? Theme.text2 : Theme.text).lineLimit(1)
            Spacer(minLength: 6)
            Text(value).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2).lineLimit(1).fixedSize()
        }
    }
}

private struct RunningCard: View {
    @ObservedObject var find: FindModel
    let doc: Doc
    var body: some View {
        let p = find.progress
        Card(padding: 16, spacing: 10) {
            Text(L.t("find.running", Int((p.fraction * 100).rounded()))).font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity)
            GeometryReader { g in ZStack(alignment: .leading) { Capsule().fill(Theme.ctl); Capsule().fill(Theme.accent).frame(width: g.size.width * min(max(p.fraction, 0), 1)) } }.frame(height: 6)
            VStack(spacing: 6) {
                if p.hasAudio { StepRow(state: p.sounds >= 1 ? .done : .running, title: L.t("find.step.sounds"), value: p.sounds >= 1 ? L.t("find.dur.s", max(Int(p.soundsSeconds.rounded()), 1)) : "\(Int(p.sounds * 100)) %") }
                if p.hasVideo { StepRow(state: p.images >= 1 ? .done : (p.images > 0 ? .running : .waiting), title: L.t("find.step.images"), value: p.images > 0 ? "\(Fmt.time(p.imagesTime, decimals: false)) / \(Fmt.time(doc.duration, decimals: false))" : L.t("find.step.wait")) }
            }
            Text(note(p)).font(.system(size: 11.5)).foregroundStyle(Theme.text2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
            Button { find.cancel() } label: { Text(L.t("common.cancel")).frame(minWidth: 116) }.buttonStyle(FlatButton()).frame(maxWidth: .infinity).padding(.top, 2)
        }
    }
    private func note(_ p: AnalysisProgress) -> String {
        if p.paused { return L.t("find.paused") }
        if let r = find.remaining { return L.t("find.eta", duration(r)) }
        return L.t("find.working")
    }
}

private struct FailedCard: View {
    @ObservedObject var find: FindModel
    var body: some View {
        Card(padding: 16, spacing: 10) {
            VStack(spacing: 10) {
                BigIcon(symbol: "exclamationmark.triangle")
                Text(L.t("find.failed.title")).font(.system(size: 13, weight: .semibold))
                Text(L.t("find.failed.body")).font(.system(size: 11.5)).foregroundStyle(Theme.text2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity)
            Button { find.start() } label: { Text(L.t("find.retry")).frame(minWidth: 116) }.buttonStyle(FlatButton(kind: .primary)).frame(maxWidth: .infinity).padding(.top, 4)
        }
    }
}

// MARK: - Résultats

private struct FindRow: View {
    let symbol: String, name: String, value: String
    @State private var hover = false
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Theme.text2).frame(width: 16)
            Text(name).font(.system(size: 12.5)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 6)
            Text(value).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(hover ? Theme.text : Theme.text2).lineLimit(1).fixedSize().layoutPriority(1)
        }
        .padding(.horizontal, 8).frame(height: 28)
        .background(hover ? Theme.ctl : .clear, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
        .contentShape(Rectangle()).onHover { hover = $0 }
    }
}

private struct ResultsView: View {
    @ObservedObject var model: AppModel
    let doc: Doc
    @ObservedObject var find: FindModel
    var openEdit: () -> Void
    @State private var allScenes = false
    @State private var allSounds = false
    private let limit = 8

    @State private var showThemes = false
    @State private var showSetup = false

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    if let a = find.added { AddedCard(info: a, openEdit: openEdit) }
                    if find.protagonists.isEmpty {
                        // pas encore de personnes : les cartes de mise en route (modèle à installer, reconnaissance à lancer)
                        if doc.info.video != nil { CharactersCard(find: find) }
                        if doc.info.audio != nil { VoicesCard(find: find) }
                    } else {
                        ProtagonistsCard(model: model, doc: doc, find: find)
                        if !find.suggestions.isEmpty { SuggestionsCard(find: find) }
                        if doc.info.video != nil, find.faces == nil { CharactersCard(find: find) }
                        if doc.info.audio != nil, find.voices == nil { VoicesCard(find: find) }
                    }
                    fold(L.t("people.fold.themes"), open: $showThemes) {
                        if doc.info.video != nil { listCard(title: "find.scenes", rows: find.summary.scenes, all: $allScenes, sound: false) }
                        if doc.info.audio != nil { listCard(title: "find.sounds", rows: find.summary.sounds, all: $allSounds, sound: true) }
                    }
                    fold(setupSummary, open: $showSetup) {
                        if doc.info.video != nil, !find.protoSel.isEmpty { WholeShotsRow(find: find) }
                        headerCard
                        if doc.info.video != nil, find.faces != nil { CharactersCard(find: find, lists: false) }
                        if doc.info.audio != nil, find.voices != nil { VoicesCard(find: find, lists: false) }
                    }
                }
            }
            if !find.protoSel.isEmpty { PeopleBar(model: model, find: find) }
        }
    }

    /// État de la reconnaissance, en une ligne repliée : les cartes de réglage (installer, supprimer, relancer) ne s'ouvrent que sur demande.
    private var setupSummary: String {
        func mark(_ on: Bool) -> String { on ? "✓" : "–" }
        var parts: [String] = []
        if doc.info.video != nil { parts.append(L.t("people.setup.faces") + " " + mark(find.faces != nil)) }
        if doc.info.audio != nil { parts.append(L.t("people.setup.voices") + " " + mark(find.voices != nil)) }
        return L.t("people.fold.setup") + " · " + parts.joined(separator: " · ")
    }

    private func fold<C: View>(_ title: String, open: Binding<Bool>, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.15)) { open.wrappedValue.toggle() } } label: {
                HStack { Text(title).font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(1); Spacer(minLength: 6)
                    Image(systemName: open.wrappedValue ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.text2) }
                    .frame(height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open.wrappedValue { content() }
        }
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
    }

    private var headerCard: some View {
        Card {
            HStack(spacing: 8) {
                SectionTitle(L.t("find.analyzed"))
                Spacer(minLength: 4)
                if let i = find.index {
                    Tag(text: i.hasVideo ? L.t("find.done.tag", duration(i.seconds), i.shotCount) : duration(i.seconds), kind: .ok)
                }
                Button { find.start() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text2).frame(width: 22, height: 22) }
                    .buttonStyle(.plain).help(L.t("find.reanalyze"))
            }
        }
    }

    private func listCard(title: String, rows: [SummaryRow], all: Binding<Bool>, sound: Bool) -> some View {
        Card(spacing: 4) {
            SectionTitle(L.t(title)).padding(.bottom, 2)
            if rows.isEmpty { Text(L.t("find.nothing")).font(.system(size: 11)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 8) }
            ForEach(all.wrappedValue ? rows : Array(rows.prefix(limit))) { r in
                Button { find.add(r.term) } label: {
                    FindRow(symbol: r.term.symbol, name: r.term.name, value: sound ? L.t("find.row.count", r.count, Fmt.time(r.seconds, decimals: false)) : Fmt.time(r.seconds, decimals: false))
                }.buttonStyle(.plain)
            }
            if rows.count > limit {
                Button { all.wrappedValue.toggle() } label: {
                    Text(all.wrappedValue ? L.t("find.less") : L.t("find.more", rows.count - limit)).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.text2)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).frame(height: 26).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if !sound, let missing = missingKeyScenes, !rows.isEmpty {
                Text(L.t("find.none.scenes", missing)).font(.system(size: 11)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 8).padding(.top, 2)
            }
        }
    }

    /// Familles qu'on cherche souvent (feu, feux d'artifice, foule) et qui n'apparaissent pas : on le dit au lieu de laisser croire à un oubli.
    private var missingKeyScenes: String? {
        let present = Set(find.summary.scenes.map(\.term.key))
        let names = ["fire", "fireworks", "crowd"].filter { !present.contains($0) }.compactMap { SceneFamilies.byID[$0]?.name.lowercased() }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }
}

private struct AddedCard: View {
    let info: AddedInfo
    var openEdit: () -> Void
    var body: some View {
        Card(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ok).frame(width: 32, height: 32).background(Theme.ok.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.count == 1 ? L.t("find.added1", Fmt.time(info.seconds, decimals: false)) : L.t("find.added", info.count, Fmt.time(info.seconds, decimals: false))).font(.system(size: 13, weight: .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(L.t("find.added.sub")).font(.system(size: 11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Button(action: openEdit) { Text(L.t("find.open.edit")).frame(maxWidth: .infinity) }.buttonStyle(FlatButton(kind: .primary))
        }
    }
}

// MARK: - Personnages (modèle optionnel)

private struct Avatar: View {
    let row: CharacterRow
    @ObservedObject var find: FindModel
    @State private var image: NSImage?
    @State private var hover = false
    @State private var editing = false
    @State private var draft = ""

    private var selected: Bool { find.terms.contains { $0.kind == .person && $0.key == String(row.id) } }

    var body: some View {
        Button { find.add(find.personTerm(row.id)) } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(Theme.ctl)
                    if let image { Image(nsImage: image).resizable().scaledToFill() } else { Image(systemName: "person.fill").font(.system(size: 20)).foregroundStyle(Theme.text2) }
                }
                .frame(width: 54, height: 54).clipShape(Circle())
                .overlay(Circle().stroke(selected ? Theme.accent : Theme.line, lineWidth: selected ? 2 : 1))
                Text(row.title).font(.system(size: 11.5, weight: row.name == nil ? .medium : .semibold)).foregroundStyle(row.name == nil ? Theme.text2 : Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.8).truncationMode(.tail).frame(maxWidth: .infinity)
                Text(L.t("find.chars.stat", row.appearances, Fmt.time(row.seconds, decimals: false))).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Theme.text2).lineLimit(1)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 6).padding(.horizontal, 2)
            .background(hover || selected ? Theme.ctl : .clear, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }
        .task(id: row.best) { image = await find.avatar(row.id) }
        .contextMenu {
            Button(L.t("find.chars.rename")) { draft = row.name ?? ""; editing = true }
            Menu(L.t("find.chars.merge")) {
                ForEach(find.characters.filter { $0.id != row.id }) { other in
                    Button(other.title) {
                        let (keep, drop) = row.seconds >= other.seconds ? (row.id, other.id) : (other.id, row.id)
                        find.merge(drop, into: keep)
                    }
                }
            }.disabled(find.characters.count < 2)
            Button(L.t("find.chars.split")) { find.split(row.id) }.disabled(!find.canSplit(row.id))
            Divider()
            Button(L.t("find.chars.hide")) { find.hide(row.id) }
        }
        .popover(isPresented: $editing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L.t("find.chars.name.title")).font(.system(size: 12, weight: .semibold))
                TextField(L.t("find.chars.name.ph"), text: $draft).textFieldStyle(.roundedBorder).frame(width: 190).onSubmit(save)
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Button(L.t("common.cancel")) { editing = false }.buttonStyle(FlatButton(height: 26))
                    Button(L.t("find.chars.name.save"), action: save).buttonStyle(FlatButton(kind: .primary, height: 26))
                }
            }.padding(12)
        }
    }

    private func save() { find.rename(row.id, to: draft); editing = false }
}

private struct CharactersCard: View {
    @ObservedObject var find: FindModel
    var lists = true                  // faux : carte de réglage seule (installer, supprimer, relancer), sans la grille de visages
    @ObservedObject private var store = ModelStore.shared
    private let spec = ModelCatalog.characters
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: 3)

    private var modelState: ModelStore.State { spec.available ? store.state(spec) : .notInstalled }

    var body: some View {
        Card(spacing: 8) {
            HStack(spacing: 8) {
                SectionTitle(find.characters.isEmpty ? L.t("find.chars.title") : "\(L.t("find.chars.title")) · \(find.characters.count)")
                Spacer(minLength: 4)
                if find.faces == nil { Tag(text: L.t("find.chars.tag")) }
                else if !find.recognizing, find.modelReady {
                    Button { find.recognize() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text2).frame(width: 22, height: 22) }
                        .buttonStyle(.plain).help(L.t("find.chars.recognize.again"))
                }
            }
            content
        }
    }

    @ViewBuilder private var content: some View {
        if find.recognizing { running }
        else if find.faces != nil {
            if !lists { EmptyView() }
            else if find.characters.isEmpty { note(L.t("find.chars.none")) }
            else {
                LazyVGrid(columns: columns, spacing: 4) { ForEach(find.characters.prefix(24)) { Avatar(row: $0, find: find) } }
                note(L.t("find.chars.hint"))
            }
            if case .installed = modelState { installedRow }
        } else {
            switch modelState {
            case .installed:
                note(L.t("find.chars.ready"))
                if find.recognizeFailed { Text(L.t("find.chars.rfailed")).font(.system(size: 11)).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true) }
                Button { find.recognize() } label: { Text(L.t("find.chars.recognize")).frame(maxWidth: .infinity) }.buttonStyle(FlatButton(kind: .primary, height: 28))
                installedRow
            case .downloading(let p):
                note(L.t("find.chars.body", spec.sizeMB))
                HStack { Text(L.t("find.chars.downloading", Int(p * 100))).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2); Spacer(); Button(L.t("common.cancel")) { store.cancel(spec) }.buttonStyle(FlatButton(height: 26)) }
            case .failed(let e):
                note(L.t("find.chars.body", spec.sizeMB))
                Text(L.t("find.chars.failed", e)).font(.system(size: 11)).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true)
                Button { store.install(spec) } label: { Text(L.t("find.retry")) }.buttonStyle(FlatButton(height: 26))
            case .notInstalled:
                note(L.t("find.chars.body", spec.sizeMB))
                if spec.available { Button { store.install(spec) } label: { Text(L.t("find.chars.download", spec.sizeMB)).frame(maxWidth: .infinity) }.buttonStyle(FlatButton(height: 28)) }
            }
        }
    }

    private func note(_ s: String) -> some View { Text(s).font(.system(size: 11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true) }

    private var installedRow: some View {
        HStack { Tag(text: L.t("find.chars.installed"), kind: .ok, symbol: "checkmark"); Spacer(); Button(L.t("find.chars.remove")) { store.remove(spec) }.buttonStyle(FlatButton(height: 26)) }
    }

    private var running: some View {
        let p = find.recognizeProgress
        return VStack(spacing: 8) {
            Text(L.t("find.chars.running", Int((p.fraction * 100).rounded()))).font(.system(size: 12.5, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { g in ZStack(alignment: .leading) { Capsule().fill(Theme.ctl); Capsule().fill(Theme.accent).frame(width: g.size.width * min(max(p.fraction, 0), 1)) } }.frame(height: 6)
            note(p.paused ? L.t("find.paused") : (find.recognizeRemaining.map { L.t("find.eta", duration($0)) } ?? L.t("find.working")))
            Button { find.cancelRecognize() } label: { Text(L.t("common.cancel")).frame(minWidth: 116) }.buttonStyle(FlatButton()).frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Voix (second modèle optionnel)

private struct VoicesCard: View {
    @ObservedObject var find: FindModel
    var lists = true                  // faux : carte de réglage seule, sans la liste des voix
    @ObservedObject private var store = ModelStore.shared
    private let spec = ModelCatalog.voices
    private var modelState: ModelStore.State { spec.available ? store.state(spec) : .notInstalled }

    var body: some View {
        Card(spacing: 8) {
            HStack(spacing: 8) {
                SectionTitle(find.voiceRows.isEmpty ? L.t("find.voices.title") : "\(L.t("find.voices.title")) · \(find.voiceRows.count)")
                Spacer(minLength: 4)
                if find.voices == nil { Tag(text: L.t("find.chars.tag")) }
                else if !find.recognizingVoices, find.voiceModelReady {
                    Button { find.recognizeVoices() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text2).frame(width: 22, height: 22) }
                        .buttonStyle(.plain).help(L.t("find.chars.recognize.again"))
                }
            }
            content
        }
    }

    @ViewBuilder private var content: some View {
        if find.recognizingVoices { running }
        else if find.voices != nil {
            if !lists { EmptyView() }
            else if find.voiceRows.isEmpty { note(L.t("find.voices.none")) }
            else { VStack(spacing: 2) { ForEach(find.voiceRows.prefix(12)) { VoiceLine(row: $0, find: find) } } }
            if case .installed = modelState { installedRow }
        } else {
            switch modelState {
            case .installed:
                note(L.t("find.voices.ready"))
                if find.voicesFailed { Text(L.t("find.voices.rfailed")).font(.system(size: 11)).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true) }
                Button { find.recognizeVoices() } label: { Text(L.t("find.voices.recognize")).frame(maxWidth: .infinity) }.buttonStyle(FlatButton(kind: .primary, height: 28))
                installedRow
            case .downloading(let p):
                note(L.t("find.voices.body", spec.sizeMB))
                HStack { Text(L.t("find.chars.downloading", Int(p * 100))).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2); Spacer(); Button(L.t("common.cancel")) { store.cancel(spec) }.buttonStyle(FlatButton(height: 26)) }
            case .failed(let e):
                note(L.t("find.voices.body", spec.sizeMB))
                Text(L.t("find.chars.failed", e)).font(.system(size: 11)).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true)
                Button { store.install(spec) } label: { Text(L.t("find.retry")) }.buttonStyle(FlatButton(height: 26))
            case .notInstalled:
                note(L.t("find.voices.body", spec.sizeMB))
                if spec.available { Button { store.install(spec) } label: { Text(L.t("find.chars.download", spec.sizeMB)).frame(maxWidth: .infinity) }.buttonStyle(FlatButton(height: 28)) }
            }
        }
    }

    private func note(_ s: String) -> some View { Text(s).font(.system(size: 11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true) }
    private var installedRow: some View {
        HStack { Tag(text: L.t("find.chars.installed"), kind: .ok, symbol: "checkmark"); Spacer(); Button(L.t("find.chars.remove")) { store.remove(spec) }.buttonStyle(FlatButton(height: 26)) }
    }
    private var running: some View {
        let p = find.voicesProgress
        return VStack(spacing: 8) {
            Text(L.t("find.voices.running", Int((p.fraction * 100).rounded()))).font(.system(size: 12.5, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { g in ZStack(alignment: .leading) { Capsule().fill(Theme.ctl); Capsule().fill(Theme.accent).frame(width: g.size.width * min(max(p.fraction, 0), 1)) } }.frame(height: 6)
            note(p.paused ? L.t("find.paused") : (find.voicesRemaining.map { L.t("find.eta", duration($0)) } ?? L.t("find.working")))
            Button { find.cancelRecognizeVoices() } label: { Text(L.t("common.cancel")).frame(minWidth: 116) }.buttonStyle(FlatButton()).frame(maxWidth: .infinity)
        }
    }
}

/// Une voix dans la liste : clic = l'ajouter aux critères (elle parle) ; clic droit = écouter, renommer, réunir, lier à un personnage, écarter.
private struct VoiceLine: View {
    let row: VoiceRow
    @ObservedObject var find: FindModel
    @State private var hover = false
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        Button { find.add(FindTerm(kind: .voice, key: String(row.id), label: row.name)) } label: {
            HStack(spacing: 8) {
                Image(systemName: "waveform").font(.system(size: 12)).foregroundStyle(Theme.text2).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title).font(.system(size: 12.5, weight: row.name == nil ? .medium : .semibold)).foregroundStyle(row.name == nil ? Theme.text2 : Theme.text).lineLimit(1).truncationMode(.tail)
                    if let p = row.person, let c = find.characters.first(where: { $0.id == p }) {
                        Text(c.title).font(.system(size: 10.5)).foregroundStyle(Theme.text2).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                Text(L.t("find.voices.stat", row.turns, Fmt.time(row.seconds, decimals: false))).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(hover ? Theme.text : Theme.text2).lineLimit(1).fixedSize().layoutPriority(1)
            }
            .padding(.horizontal, 8).frame(height: 32)
            .background(hover ? Theme.ctl : .clear, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }
        .contextMenu {
            Button(L.t("find.voices.listen")) { listen() }
            Button(L.t("find.chars.rename")) { draft = row.name ?? ""; editing = true }
            Menu(L.t("find.chars.merge")) {
                ForEach(find.voiceRows.filter { $0.id != row.id }) { other in
                    Button(other.title) {
                        let (keep, drop) = row.seconds >= other.seconds ? (row.id, other.id) : (other.id, row.id)
                        find.mergeVoice(drop, into: keep)
                    }
                }
            }.disabled(find.voiceRows.count < 2)
            Menu(L.t("find.voices.link")) {
                ForEach(find.characters) { c in Button(c.title) { find.linkVoice(row.id, to: c.id) } }
            }.disabled(find.characters.isEmpty)
            if row.person != nil { Button(L.t("find.voices.unlink")) { find.linkVoice(row.id, to: nil) } }
            Divider()
            Button(L.t("find.voices.hide")) { find.hideVoice(row.id) }
        }
        .popover(isPresented: $editing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L.t("find.voices.name.title")).font(.system(size: 12, weight: .semibold))
                TextField(L.t("find.chars.name.ph"), text: $draft).textFieldStyle(.roundedBorder).frame(width: 190).onSubmit(save)
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Button(L.t("common.cancel")) { editing = false }.buttonStyle(FlatButton(height: 26))
                    Button(L.t("find.chars.name.save"), action: save).buttonStyle(FlatButton(kind: .primary, height: 26))
                }
            }.padding(12)
        }
    }

    private func save() { find.renameVoice(row.id, to: draft); editing = false }
    private func listen() { find.listen(at: row.sample) }
}

// MARK: - À vérifier : personnages qui se ressemblent

private struct SuggestionRow: View {
    let s: MergeSuggestion
    @ObservedObject var find: FindModel
    @State private var imageA: NSImage?
    @State private var imageB: NSImage?

    var body: some View {
        let a = find.characters.first { $0.id == s.a }, b = find.characters.first { $0.id == s.b }
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: -8) { face(imageA); face(imageB) }
                Text(L.t("find.sug.text", a?.title ?? "", b?.title ?? "")).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Button { find.accept(s) } label: { Text(L.t("find.sug.merge")).frame(minWidth: 70) }.buttonStyle(FlatButton(kind: .primary, height: 26))
                Button { find.dismiss(s) } label: { Text(L.t("find.sug.no")).frame(minWidth: 44) }.buttonStyle(FlatButton(height: 26))
            }
        }
        .task(id: s.id) { imageA = await find.avatar(s.a); imageB = await find.avatar(s.b) }
    }

    private func face(_ i: NSImage?) -> some View {
        ZStack { Circle().fill(Theme.ctl); if let i { Image(nsImage: i).resizable().scaledToFill() } else { Image(systemName: "person.fill").font(.system(size: 11)).foregroundStyle(Theme.text2) } }
            .frame(width: 30, height: 30).clipShape(Circle()).overlay(Circle().stroke(Theme.card, lineWidth: 2))
    }
}

private struct SuggestionsCard: View {
    @ObservedObject var find: FindModel
    var body: some View {
        Card(spacing: 10) {
            HStack { SectionTitle(L.t("find.sug.title")); Spacer(minLength: 4); Tag(text: "\(find.suggestions.count)") }
            ForEach(find.suggestions) { SuggestionRow(s: $0, find: find) }
        }
    }
}

// MARK: - Protagonistes : choisir, isoler, exporter

private struct ProtagonistLine: View {
    let p: Protagonist
    @ObservedObject var find: FindModel
    @State private var image: NSImage?
    @State private var hover = false
    @State private var editing = false
    @State private var draft = ""

    private var on: Bool { find.protoSel.contains(p.id) }

    var body: some View {
        Button { find.toggleProto(p.id) } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Theme.ctl)
                    if let image { Image(nsImage: image).resizable().scaledToFill() } else { Image(systemName: p.person == nil ? "waveform" : "person.fill").font(.system(size: 15)).foregroundStyle(Theme.text2) }
                }.frame(width: 40, height: 40).clipShape(Circle()).overlay(Circle().stroke(on ? Theme.accent : Theme.line, lineWidth: on ? 2 : 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.title).font(.system(size: 12.5, weight: p.name == nil ? .medium : .semibold)).foregroundStyle(p.name == nil ? Theme.text2 : Theme.text).lineLimit(1).truncationMode(.tail)
                    Text(stat).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 4)
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(on ? Theme.accent : .clear)
                    if !on { RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.text2, lineWidth: 1.5) }
                    if on { Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(Theme.onAccent) }
                }.frame(width: 14, height: 14)
            }
            .padding(.horizontal, 6).padding(.vertical, 5)
            .background(hover || on ? Theme.ctl : .clear, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }
        .task(id: p.best) { image = await find.avatar(of: p) }
        .contextMenu {
            Button(L.t("find.chars.rename")) { draft = p.name ?? ""; editing = true }
            if p.sample != nil { Button(L.t("find.voices.listen")) { find.listen(at: p.sample) } }
            if let person = p.person {
                Menu(L.t("find.chars.merge")) {
                    ForEach(find.characters.filter { $0.id != person }) { other in
                        Button(other.title) {
                            let mine = find.characters.first { $0.id == person }?.seconds ?? 0
                            let (keep, drop) = mine >= other.seconds ? (person, other.id) : (other.id, person)
                            find.merge(drop, into: keep)
                        }
                    }
                }.disabled(find.characters.count < 2)
                Button(L.t("find.chars.split")) { find.split(person) }.disabled(!find.canSplit(person))
            }
            if let v = p.voice {
                Menu(L.t("find.voices.merge")) {
                    ForEach(find.voiceRows.filter { $0.id != v }) { other in
                        Button(other.title) {
                            let mine = find.voiceRows.first { $0.id == v }?.seconds ?? 0
                            let (keep, drop) = mine >= other.seconds ? (v, other.id) : (other.id, v)
                            find.mergeVoice(drop, into: keep)
                        }
                    }
                }.disabled(find.voiceRows.count < 2)
                if p.person == nil {
                    Menu(L.t("find.voices.link")) { ForEach(find.characters) { c in Button(c.title) { find.linkVoice(v, to: c.id) } } }.disabled(find.characters.isEmpty)
                } else { Button(L.t("find.voices.unlink")) { find.linkVoice(v, to: nil) } }
            }
            Divider()
            if let person = p.person { Button(L.t("find.chars.hide")) { find.hide(person) } }
            if let v = p.voice { Button(L.t("find.voices.hide")) { find.hideVoice(v) } }
        }
        .popover(isPresented: $editing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L.t("find.chars.name.title")).font(.system(size: 12, weight: .semibold))
                TextField(L.t("find.chars.name.ph"), text: $draft).textFieldStyle(.roundedBorder).frame(width: 190).onSubmit(save)
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Button(L.t("common.cancel")) { editing = false }.buttonStyle(FlatButton(height: 26))
                    Button(L.t("find.chars.name.save"), action: save).buttonStyle(FlatButton(kind: .primary, height: 26))
                }
            }.padding(12)
        }
    }

    private var stat: String {
        let f = Fmt.time(p.faceSeconds, decimals: false), v = Fmt.time(p.voiceSeconds, decimals: false)
        if p.person != nil, p.voice != nil { return L.t("find.proto.stat", f, v) }
        if p.person != nil { return L.t("find.proto.stat.face", f) }
        return p.appearances == 1 ? L.t("find.proto.stat.voice1", v) : L.t("find.proto.stat.voice", v, p.appearances)
    }

    private func save() {
        if let person = p.person { find.rename(person, to: draft) } else if let v = p.voice { find.renameVoice(v, to: draft) }
        editing = false
    }
}

private struct ProtagonistsCard: View {
    @ObservedObject var model: AppModel
    let doc: Doc
    @ObservedObject var find: FindModel

    var body: some View {
        Card(spacing: 6) {
            HStack(spacing: 8) {
                SectionTitle("\(L.t("people.title")) · \(find.protagonists.count)")
                Spacer(minLength: 4)
                if !find.protoSel.isEmpty { Button { find.clearProtos() } label: { Text(L.t("people.clear")).font(.system(size: 11.5)).foregroundStyle(Theme.text2) }.buttonStyle(.plain) }
            }
            VStack(spacing: 2) { ForEach(find.protagonists.prefix(24)) { ProtagonistLine(p: $0, find: find) } }
            if find.protoSel.isEmpty { Text(L.t("people.hint")).font(.system(size: 11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true).padding(.top, 2) }
        }
    }
}

/// « Plans entiers » : garder le plan complet plutôt que l'instant exact où la personne apparaît ou parle.
private struct WholeShotsRow: View {
    @ObservedObject var find: FindModel
    var body: some View {
        Card(spacing: 4) {
            HStack(spacing: 8) { Text(L.t("find.proto.whole")).font(.system(size: 12)); Spacer(minLength: 6); FlatSwitch(isOn: $find.protoWhole) }
            Text(L.t("people.whole.help")).font(.system(size: 11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Barre du bas de l'onglet : le résumé de ce qui est choisi, puis ajouter aux morceaux ou exporter (même feuille d'options que l'onglet Couper).
private struct PeopleBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var find: FindModel

    var body: some View {
        let each = find.protoOut == .each
        let pieces = find.protoPieces
        let union = find.protoUnion
        let nFiles = each ? pieces.filter { !$0.segments.isEmpty }.count : (union.isEmpty ? 0 : 1)
        let nPieces = each ? pieces.reduce(0) { $0 + $1.segments.count } : union.count
        let names = find.protagonists.filter { find.protoSel.contains($0.id) }.map(\.title)
        VStack(spacing: 8) {
            Rectangle().fill(Theme.line).frame(height: 0.5)
            SectionTitle(L.t("people.keep")).frame(maxWidth: .infinity, alignment: .leading)
            Segmented(options: find.availableModes.map { ($0, L.t("people.mode." + $0.rawValue)) }, selection: $find.protoMode)
            HStack(alignment: .firstTextBaseline) {
                Text(L.t("people.sum", nPieces)).font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 6)
                Text(names.joined(separator: ", ")).font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.tail)
            }
            HStack(spacing: 8) {
                Button { find.addProtosToPieces() } label: { Text(L.t("people.add")).frame(maxWidth: .infinity) }
                    .buttonStyle(FlatButton(height: 40)).opacity(nPieces == 0 ? 0.4 : 1).disabled(nPieces == 0)
                Button { model.requestExport(ExportRequest(kind: .people(find), count: nFiles, run: { [weak find] in
                    guard let find else { return }
                    model.exportGroups(find.exportGroups(each: find.protoOut == .each))
                })) } label: { Text(L.t("people.export")).frame(maxWidth: .infinity) }
                    .buttonStyle(FlatButton(kind: .sand, height: 40)).opacity(nFiles == 0 ? 0.4 : 1).disabled(nFiles == 0)
            }
        }
    }
}

// MARK: - Sélection et passages

private struct Pill: View {
    let term: FindTerm
    var find: FindModel? = nil
    var remove: () -> Void
    @State private var face: NSImage?
    var body: some View {
        HStack(spacing: 6) {
            if term.kind == .person || term.kind == .alone || term.kind == .speaks, let face { Image(nsImage: face).resizable().scaledToFill().frame(width: 18, height: 18).clipShape(Circle()).padding(.leading, -3) }
            else { Image(systemName: term.symbol).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.text2) }
            Text(term.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Button(action: remove) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.text2).frame(width: 16, height: 16) }.buttonStyle(.plain)
        }
        .padding(.leading, 9).padding(.trailing, 3).frame(height: 26).background(Theme.ctl, in: Capsule())
        .task(id: term.key) { if term.kind == .person || term.kind == .alone || term.kind == .speaks, let id = Int32(term.key) { face = await find?.avatar(id) } }
    }
}

private struct SelectionView: View {
    @ObservedObject var model: AppModel
    let doc: Doc
    @ObservedObject var find: FindModel

    var body: some View {
        VStack(spacing: 10) {
            selectionCard
            passagesCard
            footer
        }
    }

    private var selectionCard: some View {
        Card(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionTitle(L.t("find.selection"))
                Spacer(minLength: 4)
                Text(find.keptCount == 1 ? L.t("find.selection.count1", find.result.passages.count) : L.t("find.selection.count", find.keptCount, find.result.passages.count)).font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(1)
            }
            FlowLayout(spacing: 6) {
                ForEach(Array(find.ordered.enumerated()), id: \.element.token) { n, t in
                    HStack(spacing: 4) {
                        if n > 0 {
                            Button { find.flip(t) } label: { Text(L.t(t.exclude ? "find.except" : "find.and")).font(.system(size: 10.5, weight: .bold)).tracking(0.4).foregroundStyle(Theme.text2).padding(.horizontal, 3).frame(height: 26) }
                                .buttonStyle(.plain).help(L.t("find.flip.help"))
                        }
                        Pill(term: t, find: find) { find.remove(t) }
                    }
                }
                addMenu
            }
            if doc.info.video != nil {
                HStack(spacing: 8) {
                    Text(L.t("find.whole")).font(.system(size: 12))
                    Spacer(minLength: 6)
                    FlatSwitch(isOn: $find.wholeShots)
                }.help(L.t("find.whole.help"))
            }
        }
    }

    private var addMenu: some View {
        Menu {
            Menu(L.t("find.menu.and")) { entries(exclude: false) }
            Menu(L.t("find.menu.except")) { entries(exclude: true) }
            Divider()
            Button(L.t("find.back")) { find.clear() }
        } label: {
            HStack(spacing: 4) { Image(systemName: "plus").font(.system(size: 9.5, weight: .bold)); Text(L.t("find.add")).font(.system(size: 12, weight: .semibold)) }
                .foregroundStyle(Theme.text).padding(.horizontal, 10)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(height: 26)
        .overlay(Capsule().strokeBorder(Theme.text2.opacity(0.4), lineWidth: 1).allowsHitTesting(false))
    }

    @ViewBuilder private func entries(exclude: Bool) -> some View {
        let taken = Set(find.terms.map(\.token))
        let scenes = find.summary.scenes.filter { !taken.contains($0.term.token) }, sounds = find.summary.sounds.filter { !taken.contains($0.term.token) }
        if !scenes.isEmpty { Menu(L.t("find.scenes")) { ForEach(scenes) { r in Button(r.term.name) { var t = r.term; t.exclude = exclude; find.add(t) } } } }
        if !sounds.isEmpty { Menu(L.t("find.sounds")) { ForEach(sounds) { r in Button(r.term.name) { var t = r.term; t.exclude = exclude; find.add(t) } } } }
        let people = find.characters.filter { !taken.contains(find.personTerm($0.id).token) }
        if !people.isEmpty { Menu(L.t("find.chars.title")) { ForEach(people) { c in Button(c.title) { var t = find.personTerm(c.id); t.exclude = exclude; find.add(t) } } } }
        let voiceMenu = find.voiceRows.filter { !taken.contains("voice:\($0.id)") }
        if !voiceMenu.isEmpty { Menu(L.t("find.voices.title")) { ForEach(voiceMenu) { v in Button(v.title) { var t = FindTerm(kind: .voice, key: String(v.id), label: v.name); t.exclude = exclude; find.add(t) } } } }
    }

    private var passagesCard: some View {
        Card(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(L.t("find.passages"))
                Spacer(minLength: 4)
                if !find.result.passages.isEmpty {
                    Button { find.setAll(!find.allChecked) } label: { Text(L.t(find.allChecked ? "find.uncheckall" : "find.checkall")).font(.system(size: 11.5)).foregroundStyle(Theme.text2) }.buttonStyle(.plain)
                }
            }
            if find.result.passages.isEmpty {
                Text(L.t(find.positives.isEmpty ? "find.noterms" : "find.empty.result")).font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true).padding(.vertical, 6)
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) { ForEach(find.result.passages) { p in PassageRow(model: model, doc: doc, find: find, passage: p) } }
                }
            }
        }.frame(maxHeight: .infinity)
    }

    private var footer: some View {
        let n = find.pieces.count, total = find.pieces.reduce(0.0) { $0 + ($1.end - $1.start) }
        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(L.t("find.sum")).font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text("\(n) · \(Fmt.time(total, decimals: false))").font(.system(size: 12, weight: .semibold).monospacedDigit()).lineLimit(1).fixedSize()
            }
            Button { find.addToPieces() } label: { Text(n == 0 ? L.t("find.addnone") : L.t(n == 1 ? "find.add1" : "find.addn", n)).frame(maxWidth: .infinity) }
                .buttonStyle(FlatButton(kind: .primary, height: 36)).opacity(n == 0 ? 0.4 : 1).disabled(n == 0)
        }
    }
}

private struct PassageRow: View {
    @ObservedObject var model: AppModel
    let doc: Doc
    @ObservedObject var find: FindModel
    let passage: Passage
    @State private var image: NSImage?

    var body: some View {
        let on = find.isChecked(passage)
        HStack(spacing: 8) {
            Button { find.toggle(passage) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(on ? Theme.accent : .clear)
                    if !on { RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.text2, lineWidth: 1.5) }
                    if on { Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(Theme.onAccent) }
                }.frame(width: 14, height: 14).frame(width: 18, height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(passage.excludedBy != nil)
            Button {
                model.player.pause(); model.player.seek(passage.start); doc.ensureVisible(passage.start)
            } label: {
                HStack(spacing: 8) {
                    if doc.hasVideo {
                        ZStack {
                            Theme.ctl
                            if let image { Image(nsImage: image).resizable().scaledToFill() }
                        }.frame(width: 64, height: 36).clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(Fmt.time(passage.start, decimals: false)) → \(Fmt.time(passage.end, decimals: false))").font(.system(size: 12, weight: .semibold).monospacedDigit()).lineLimit(1)
                        Text(passage.excludedBy.map { L.t("find.excluded", $0) } ?? L.t("find.dur.s", max(Int(passage.duration.rounded()), 1))).font(.system(size: 11)).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 2).padding(.trailing, 4).opacity(passage.excludedBy != nil ? 0.5 : 1)
        .task(id: passage.id) { if doc.hasVideo { image = await find.thumbs.image(passage.start + min(0.4, passage.duration / 2), of: doc.info) } }
    }
}
