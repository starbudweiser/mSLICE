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

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                if let a = find.added { AddedCard(info: a, openEdit: openEdit) }
                headerCard
                CharactersCard()
                if doc.info.video != nil { listCard(title: "find.scenes", rows: find.summary.scenes, all: $allScenes, sound: false) }
                if doc.info.audio != nil { listCard(title: "find.sounds", rows: find.summary.sounds, all: $allSounds, sound: true) }
            }
        }
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

// MARK: - Modèle optionnel pour les personnages

private struct CharactersCard: View {
    @ObservedObject private var store = ModelStore.shared
    private let spec = ModelCatalog.characters
    var body: some View {
        Card(spacing: 8) {
            HStack(spacing: 8) {
                SectionTitle(L.t("find.chars.title"))
                Spacer(minLength: 4)
                Tag(text: L.t("find.chars.tag"))
            }
            Text(L.t("find.chars.body", spec.sizeMB)).font(.system(size: 11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            switch spec.available ? store.state(spec) : .notInstalled {
            case .installed:
                HStack { Tag(text: L.t("find.chars.installed"), kind: .ok, symbol: "checkmark"); Spacer(); Button(L.t("find.chars.remove")) { store.remove(spec) }.buttonStyle(FlatButton(height: 26)) }
            case .downloading(let p):
                HStack { Text(L.t("find.chars.downloading", Int(p * 100))).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2); Spacer(); Button(L.t("common.cancel")) { store.cancel(spec) }.buttonStyle(FlatButton(height: 26)) }
            case .failed(let e):
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.t("find.chars.failed", e)).font(.system(size: 11)).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true)
                    Button { store.install(spec) } label: { Text(L.t("find.retry")) }.buttonStyle(FlatButton(height: 26))
                }
            case .notInstalled:
                if spec.available {
                    Button { store.install(spec) } label: { Text(L.t("find.chars.download", spec.sizeMB)).frame(maxWidth: .infinity) }.buttonStyle(FlatButton(height: 28))
                } else {
                    Text(L.t("find.chars.unavailable")).font(.system(size: 11)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Sélection et passages

private struct Pill: View {
    let term: FindTerm
    var remove: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: term.symbol).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.text2)
            Text(term.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Button(action: remove) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.text2).frame(width: 16, height: 16) }.buttonStyle(.plain)
        }
        .padding(.leading, 9).padding(.trailing, 3).frame(height: 26).background(Theme.ctl, in: Capsule())
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
                Text(L.t("find.selection.count", find.keptCount, find.result.passages.count)).font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(1)
            }
            FlowLayout(spacing: 6) {
                ForEach(Array(find.ordered.enumerated()), id: \.element.token) { n, t in
                    HStack(spacing: 4) {
                        if n > 0 {
                            Button { find.flip(t) } label: { Text(L.t(t.exclude ? "find.except" : "find.and")).font(.system(size: 10.5, weight: .bold)).tracking(0.4).foregroundStyle(Theme.text2).padding(.horizontal, 3).frame(height: 26) }
                                .buttonStyle(.plain).help(L.t("find.flip.help"))
                        }
                        Pill(term: t) { find.remove(t) }
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
