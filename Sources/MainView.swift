// mSLICE — fenêtre principale (design Flat Mat) : barre, fichiers, lecteur, bistouri, timeline, morceaux, export.
import SwiftUI
import AppKit

// MARK: - Utilitaires de mise en page

/// Répartition en lignes qui passent à la ligne (choix de formats).
struct FlowLayout: Layout {
    var spacing: CGFloat = 5
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? 300, subviews).size
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(b.width, subviews)
        for (i, f) in r.frames.enumerated() { subviews[i].place(at: CGPoint(x: b.minX + f.minX, y: b.minY + f.minY), proposal: .unspecified) }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, frames: [CGRect] = [], maxW: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxW = max(maxW, x - spacing)
        }
        return (CGSize(width: maxW, height: y + rowH), frames)
    }
}

/// Curseur plat : piste en capsule, pouce blanc.
struct FlatSlider: View {
    @Binding var value: Double      // 0…1
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Theme.rChip, style: .continuous).fill(Theme.ctl).frame(height: 5)
                RoundedRectangle(cornerRadius: Theme.rChip, style: .continuous).fill(Theme.accent).frame(width: g.size.width * value, height: 5)
                Circle().fill(.white).frame(width: 13, height: 13).shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                    .offset(x: g.size.width * value - 6.5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value = min(max($0.location.x / g.size.width, 0), 1) })
        }.frame(height: 18)
    }
}

/// Barre de progression de la recherche des blancs : elle pulse tant que la mesure court (immobile si l'utilisateur a réduit les animations).
struct SilenceProgress: View {
    @ObservedObject var doc: Doc
    @State private var pulse = false
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Theme.rChip, style: .continuous).fill(Theme.ctl)
                    RoundedRectangle(cornerRadius: Theme.rChip, style: .continuous).fill(Theme.accent).frame(width: max(g.size.width * doc.silenceProgress, 8))
                        .opacity(pulse ? 1 : 0.45)
                }
            }.frame(height: 5)
            Text(L.t("sil.searching", Int((doc.silenceProgress * 100).rounded()))).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2)
        }
        .onAppear { if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true } } else { pulse = true } }
    }
}

/// Curseur « Intensité » des blancs retirés : de Doux (silences longs seulement, respiration large) à Serré (toutes les pauses, respiration courte). Mémorisé.
struct IntensitySlider: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 8) {
            Text(L.t("sil.intensity")).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.text2).lineLimit(1)
            Text(L.t("sil.soft")).font(.system(size: 11)).foregroundStyle(Theme.text2).lineLimit(1)
            FlatSlider(value: $model.opts.trimIntensity)
            Text(L.t("sil.tight")).font(.system(size: 11)).foregroundStyle(Theme.text2).lineLimit(1)
        }
    }
}

// MARK: - Fenêtre

struct MainView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TitleBar(model: model)
                Rectangle().fill(Theme.line).frame(height: 0.5)
                HStack(spacing: 0) {
                    Sidebar(model: model).frame(width: Theme.sidebarWidth)
                    Rectangle().fill(Theme.line).frame(width: 0.5)
                    if let d = model.current {
                        EditorCenter(model: model, doc: d, player: model.player).id(d.id)
                        RightPanel(model: model, doc: d).frame(width: Theme.rightWidth).id(d.id)
                    } else {
                        EmptyState(model: model)
                    }
                }
            }
            if model.sheet != .none { SheetLayer(model: model) }
            if model.showShortcuts { ShortcutsLayer(model: model) }
            if let t = model.toast {
                VStack { Spacer(); Text(t).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.onAccent).padding(.horizontal, 14).frame(height: 32)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.rChip, style: .continuous)).padding(.bottom, 18) }.transition(.opacity)
            }
        }
        .background(Theme.bg)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for p in providers { _ = p.loadObject(ofClass: URL.self) { url, _ in if let url { DispatchQueue.main.async { AppModel.shared.open([url]) } } } }
            return true
        }
        .animation(.easeOut(duration: 0.15), value: model.toast)
    }
}

// MARK: - Barre de titre

struct TitleBar: View {
    @ObservedObject var model: AppModel
    @AppStorage("rightTab") private var tab = 0
    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 78)      // emplacement des trois boutons de fenêtre
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                (Text("m").foregroundColor(Theme.brand) + Text("SLICE")).font(.system(size: 15, weight: .bold))
                if let d = model.current {
                    HStack(spacing: 0) {
                        Text(d.name).fontWeight(.semibold).foregroundStyle(Theme.text)
                        Text(" · " + d.info.summary).foregroundStyle(Theme.text2)
                    }.font(.system(size: 12)).lineLimit(1).truncationMode(.middle).help(d.name)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                if model.current != nil {
                    Button { tab = tab == 1 ? 0 : 1 } label: { Image(systemName: "sparkles").font(.system(size: 13, weight: .medium)).foregroundStyle(tab == 1 ? Theme.onAccent : Theme.text).frame(width: 6) }
                        .buttonStyle(FlatButton(kind: tab == 1 ? .primary : .normal)).help(L.t("agent.title"))
                }
                Button { model.showShortcuts.toggle() } label: { HStack(spacing: 8) { Text(L.t("bar.shortcuts")); Key("⌘/") } }.buttonStyle(FlatButton())
                Button { AppDelegate.shared?.openSettings() } label: { GearGlyph().stroke(Theme.text, style: StrokeStyle(lineWidth: 1.6, lineCap: .round)).frame(width: 15, height: 15).frame(width: 6) }.buttonStyle(FlatButton())
            }
        }
        .frame(height: Theme.barHeight).padding(.trailing, 16)
    }
}

// MARK: - Fichiers ouverts

struct Sidebar: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(L.t("files.title", model.docs.count)).numberTicker(model.docs.count).padding(.horizontal, 4).padding(.bottom, 4)
            if model.docs.isEmpty { Text(L.t("files.none")).font(.system(size: 11.5)).foregroundStyle(Theme.text2).padding(4) }
            ScrollView { VStack(spacing: 4) { ForEach(model.docs) { d in FileRow(model: model, doc: d, selected: model.current === d) } } }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                Text(L.t("files.drop")).font(.system(size: 12.5, weight: .semibold))
                Text(L.t("files.dropHint")).font(.system(size: 11.5)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
                Text("MOV · MP4 · MKV · AVI · WebM · MXF · MTS · ProRes · WAV · MP3 · FLAC · AAC · AIFF · OGG · Opus…").font(.system(size: 10.5)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
            }
            .padding(.vertical, 14).padding(.horizontal, 12).frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous).strokeBorder(Theme.text2.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .onTapGesture { model.chooseFiles() }
        }
        .padding(.horizontal, 12).padding(.vertical, 14)
    }
}

struct FileRow: View {
    @ObservedObject var model: AppModel
    @ObservedObject var doc: Doc
    let selected: Bool
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(doc.info.ext.uppercased()).font(.system(size: 9.5, weight: .bold)).foregroundStyle(Theme.text)
                .frame(width: 34, height: 34).background(Theme.ctl, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.middle).help(doc.name)
                Text("\(Fmt.time(doc.duration, decimals: false)) · \(Fmt.size(doc.info.size))").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2).lineLimit(1)
                if doc.exported { HStack { Spacer(); Tag(text: L.t("files.extracted"), kind: .ok, symbol: "checkmark") }.padding(.top, 2) }
                else if !doc.segments.isEmpty { HStack { Spacer(); Tag(text: L.n("files.pieces", doc.segments.count), kind: selected ? .accent : .plain).numberTicker(doc.segments.count) }.padding(.top, 2) }
            }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .selectableSurface(selected: selected)
        .contentShape(Rectangle()).onTapGesture { model.select(doc) }
        .contextMenu { Button(L.t("files.close")) { model.close(doc) } }
    }
}

// MARK: - État vide

struct EmptyState: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.to.line").font(.system(size: 28, weight: .medium)).foregroundStyle(Theme.text2)
                .frame(width: 64, height: 64).background(Theme.ctl, in: RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
            Text(L.t("empty.title")).font(.system(size: 18, weight: .bold))
            Text(L.t("empty.sub")).font(.system(size: 12.5)).foregroundStyle(Theme.text2)
            Button { model.chooseFiles() } label: { HStack(spacing: 8) { Text(L.t("empty.choose")); Key("⌘O") } }.buttonStyle(FlatButton(kind: .primary))
            Text(L.t("empty.formats")).font(.system(size: 11.5)).foregroundStyle(Theme.text2).multilineTextAlignment(.center).frame(maxWidth: 460)
        }
        .padding(40).frame(maxWidth: 560)
        .overlay(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous).strokeBorder(Theme.text2.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Centre : lecteur, transport, timeline

struct EditorCenter: View {
    @ObservedObject var model: AppModel
    @ObservedObject var doc: Doc
    let player: PlayerModel
    var body: some View {
        VStack(spacing: 10) {
            PlayerCard(doc: doc, player: player)
            TransportBar(model: model, doc: doc, player: player)
            TimelineCard(model: model, doc: doc, player: player)
        }
        .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlayerCard: View {
    @ObservedObject var doc: Doc
    @ObservedObject var player: PlayerModel
    var body: some View {
        ZStack {
            Theme.media
            if doc.hasVideo { PlayerSurface(player: player.player, overlay: player.scrubber.layer) } else {
                VStack(spacing: 8) { Image(systemName: "waveform").font(.system(size: 40, weight: .light)); Text(doc.name).font(.system(size: 13)).lineLimit(1).truncationMode(.middle).help(doc.name) }.padding(.horizontal, 24).foregroundStyle(.white.opacity(0.7))
            }
            if let p = player.preparing { Text(p).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white).padding(.horizontal, 12).frame(height: 28).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.rChip, style: .continuous)) }
            VStack {
                HStack {
                    OverlayChip(text: doc.name)
                    Spacer()
                    if let i = segmentIndex { OverlayChip(text: L.t("player.inPiece", i + 1), fill: doc.segments.indices.contains(i) ? doc.color(of: doc.segments[i]) : Theme.seg, bold: true) }
                }
                Spacer()
                HStack {
                    OverlayChip(text: Fmt.time(player.time).replacingOccurrences(of: "^", with: "", options: .regularExpression), mono: true)
                    Spacer()
                    if doc.hasVideo { OverlayChip(text: L.t("player.frame", Int(player.time * (doc.info.video?.fps ?? 25) + 0.5), Fmt.fps(doc.info.video?.fps ?? 25))) }
                }
            }.padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
        .frame(maxHeight: .infinity)
    }
    private var segmentIndex: Int? { doc.segments.firstIndex { player.time >= $0.start - 0.0005 && player.time <= $0.end + 0.0005 } }
}

struct OverlayChip: View {
    let text: String; var fill: Color = .black.opacity(0.58); var bold = false; var mono = false
    var body: some View {
        Text(text).font(mono ? .system(size: 13, weight: .semibold, design: .monospaced) : .system(size: 11.5, weight: bold ? .semibold : .regular))
            .foregroundStyle(.white).lineLimit(1).padding(.horizontal, 10).frame(height: 22).background(fill, in: RoundedRectangle(cornerRadius: Theme.rChip, style: .continuous))
    }
}

struct TransportBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var doc: Doc
    @ObservedObject var player: PlayerModel
    var body: some View {
        HStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Fmt.time(player.time)).font(.system(size: 22, weight: .semibold).monospacedDigit()).lineLimit(1).fixedSize()
                Text("/ " + Fmt.time(doc.duration)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.text2).lineLimit(1).fixedSize()
            }.padding(.trailing, 6).layoutPriority(1)
            roundButton("backward.end.fill") { player.pause(); player.seek(doc.segments.last(where: { $0.start < player.time - 0.05 })?.start ?? 0) }
            roundButton("backward.fill") { player.pause(); player.seek(player.time - 1) }
            Button { player.togglePlay() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 14, weight: .semibold)).frame(width: 42, height: 34)
                .foregroundStyle(Theme.onAccent).background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous)) }.buttonStyle(.plain)
            roundButton("forward.fill") { player.pause(); player.seek(player.time + 1) }
            roundButton("forward.end.fill") { player.pause(); player.seek(doc.segments.first(where: { $0.start > player.time + 0.05 })?.start ?? doc.duration) }
            if doc.canClean { voiceButton }
            Spacer(minLength: 8)
            scalpelButton("I", L.t("tr.in")) { doc.markIn(at: player.time, snap: model.snap && model.opts.passthrough) }
            scalpelButton("O", L.t("tr.out")) { doc.markOut(at: player.time) }
        }.frame(height: 42)
    }
    /// Écoute la voix seule (musique et bruits retirés) : un bouton du lecteur, qui se remplit pendant le calcul de la piste.
    private var voiceButton: some View {
        let building: Double? = { if case .building(let p) = doc.clean { return p }; return nil }()
        return Button { if building != nil { doc.cancelClean() } else { model.setVoiceOnly(!doc.voiceOnly, for: doc) } } label: {
            ZStack {
                if let p = building {
                    Circle().stroke(Theme.text2.opacity(0.35), lineWidth: 2).frame(width: 16, height: 16)
                    Circle().trim(from: 0, to: max(p, 0.04)).stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 16, height: 16)
                } else { Image(systemName: "waveform").font(.system(size: 12, weight: .semibold)) }
            }
            .frame(width: 34, height: 34).foregroundStyle(doc.voiceOnly ? Theme.onAccent : Theme.text)
            .background(doc.voiceOnly ? Theme.accent : Theme.ctl, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
        }.buttonStyle(.plain).help(L.t("clean.help"))
    }
    private func roundButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).frame(width: 34, height: 34).foregroundStyle(Theme.text)
            .background(Theme.ctl, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous)) }.buttonStyle(.plain)
    }
    private func scalpelButton(_ key: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) { Text(label); Key(key) }
        }.buttonStyle(FlatButton(height: 34))
    }
}

struct TimelineCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var doc: Doc
    @ObservedObject private var find: FindModel      // la piste de résultats ajoute sa hauteur à la timeline
    @ObservedObject private var dialogues: DialogueModel      // la piste « Dialogues » aussi
    let player: PlayerModel          // pas observé : la tête de lecture est un calque qui se met à jour seul
    @AppStorage("showLegend") private var showLegend = true
    init(model: AppModel, doc: Doc, player: PlayerModel) { self.model = model; self.doc = doc; self.player = player; self.find = doc.find; self.dialogues = doc.dialogues }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(L.t("tl.zoom")).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                FlatSlider(value: zoomBinding).frame(width: 90)
                Text(String(format: "%.0f×", max(doc.duration / max(doc.viewSpan, 0.1), 1))).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2).frame(minWidth: 26, alignment: .leading)
                Spacer(minLength: 0)
                Button { model.snap.toggle() } label: { Chip(text: L.t("tl.snap"), on: model.snap && model.opts.passthrough, enabled: model.opts.passthrough && doc.hasVideo) }.buttonStyle(.plain)
                    .help(L.t("tl.snap.help"))
                Menu {
                    Button(L.t("tl.auto")) { Task { await autoTrim() } }.disabled(doc.info.audio == nil)
                    if dialogues.hasLines { Toggle(L.t("dlg.lane.chip"), isOn: $dialogues.showLane) }
                    Toggle(L.t("tl.legend"), isOn: $showLegend)
                } label: { Text("⋯").font(.system(size: 13, weight: .bold)).frame(width: 30, height: 24).background(Theme.ctl, in: RoundedRectangle(cornerRadius: Theme.rChip, style: .continuous)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }.frame(height: 26).padding(.bottom, 4)
            TimelineRepresentable(doc: doc, player: player, snap: model.snap && model.opts.passthrough).frame(height: TimelineView.height(lane: !find.lane.isEmpty, dialogues: dialogues.laneVisible))
            if showLegend {
                HStack(spacing: 10) {
                    legend("I", L.t("key.in")); legend("O", L.t("key.out")); legend(L.t("key.space"), L.t("key.play")); legend("←→", L.t("key.frame")); legend("⌫", L.t("key.delete"))
                    Spacer(minLength: 0)
                }.padding(.top, 8).overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }.padding(.top, 8)
            }
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous).strokeBorder(Theme.line, lineWidth: 0.5))
    }
    /// Un morceau entre le silence d'ouverture et le silence de fin.
    private func autoTrim() async {
        guard let r = await Silence.detect(doc.info) else { model.flash(L.t("tl.auto.none")); return }
        doc.snapshot(); doc.addSegment(r.start, r.end)
        player.seek(r.start); doc.ensureVisible(r.start)
    }
    private func legend(_ key: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) { Key(key); Text(text).font(.system(size: 10.5)).foregroundStyle(Theme.text2).lineLimit(1) }.fixedSize()
    }
    /// Zoom logarithmique : 0 = tout le fichier, 1 = 2 secondes à l'écran.
    private var zoomBinding: Binding<Double> {
        Binding(
            get: { let maxZ = log(max(doc.duration / 2, 1.0001)); return maxZ > 0 ? min(max(log(max(doc.duration / max(doc.viewSpan, 0.1), 1)) / maxZ, 0), 1) : 0 },
            set: { v in
                let target = doc.duration / exp(v * log(max(doc.duration / 2, 1.0001)))
                doc.zoom(by: doc.viewSpan / max(target, 0.1), around: player.time)
            })
    }
}

// MARK: - Panneau de droite : morceaux et export

struct RightPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var doc: Doc
    @AppStorage("rightTab") private var tab = 0          // 0 : couper, 1 : agent (icône de la barre), 2 : personnes, 3 : dialogues
    var body: some View {
        VStack(spacing: 10) {
            Segmented(options: [(0, L.t("tab.cut")), (2, L.t("tab.people")), (3, L.t("dlg.title"))], selection: $tab, tabs: true)
            if tab == 3 {
                DialoguePanel(model: model, doc: doc, dialogues: doc.dialogues)
            } else if tab == 1 {
                AgentPanel(model: model, chat: AgentChat.shared)
            } else if tab == 2 {
                FindPanel(model: model, doc: doc, find: doc.find, openEdit: { tab = 0 })
            } else {
                // Les morceaux défilent s'ils sont nombreux ; la barre d'export reste en bas.
                ScrollView(.vertical, showsIndicators: false) { PiecesCard(model: model, doc: doc) }
                ExportBar(model: model, doc: doc)
            }
        }
        .padding(.top, 14).padding(.bottom, 14).padding(.trailing, 14)
    }
}

/// Barre d'export unique, en bas du panneau (maquette) : le résumé de ce qui part, le bouton « Exporter N morceaux » (export direct avec les réglages courants)
/// et le bouton réglages, qui ouvre la feuille d'options.
struct ExportBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var doc: Doc
    var body: some View {
        let o = model.opts
        let n = doc.segments.isEmpty ? 0 : Planner.outputs(info: doc.info, segments: doc.segments, opts: o, keyframes: doc.keyframes, base: doc.baseName, mergeName: doc.mergeName).count
        let est = Planner.estimate(info: doc.info, segments: doc.segments, opts: o)
        VStack(spacing: 8) {
            Rectangle().fill(Theme.line).frame(height: 0.5)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if n == 0 { Text(L.t("bar.nothing")).font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
                else {
                    (Text(L.n("export.files", n)).fontWeight(.semibold).foregroundColor(Theme.text) + Text(" · " + settingsText(o)).foregroundColor(Theme.text2))
                        .font(.system(size: 11.5)).lineLimit(1).truncationMode(.tail)
                }
                if n > 0 { Text("≈ " + Fmt.size(est.bytes)).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2).lineLimit(1).fixedSize() }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button { model.exportNow() } label: { Text(L.n("exp.bar", doc.segments.count)).numberTicker(doc.segments.count).frame(maxWidth: .infinity) }
                    .buttonStyle(FlatButton(kind: .sand, height: 40)).opacity(n == 0 ? 0.4 : 1).disabled(n == 0)
                Button { model.requestPiecesExport() } label: { SlidersGlyph().stroke(Theme.warn, style: StrokeStyle(lineWidth: 1.6, lineCap: .round)).frame(width: 15, height: 15).frame(width: 16) }
                    .buttonStyle(FlatButton(height: 40)).opacity(n == 0 ? 0.4 : 1).disabled(n == 0).help(L.t("exp.settings"))
            }
            if doc.canClean && doc.segments.isEmpty {
                Button { model.exportWholeClean() } label: {
                    if case .building(let p) = doc.clean { Text(L.t("clean.building", Int((p * 100).rounded()))).frame(maxWidth: .infinity) }
                    else { Text(L.t("clean.exportWhole")).frame(maxWidth: .infinity) }
                }.buttonStyle(FlatButton(height: 34))
            }
        }
    }
    /// Ce qui change par rapport à l'original, en peu de mots : « mêmes réglages que l'original » tant qu'on ne touche à rien.
    private func settingsText(_ o: ExportOptions) -> String {
        func lower(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }
        if o.passthrough, o.format == .same, !o.voiceOnly { return L.t("exp.bar.same") }
        let f = o.resolvedFormat(for: doc.info).title
        var s = o.passthrough ? (o.format == .same ? L.t("exp.bar.fmt.same") : L.t("exp.format.copyto", f)) : lower(L.t("exp.format.reto", f))
        if o.voiceOnly, doc.info.audio != nil { s += " · " + lower(L.t("clean.export")) }
        return s
    }
}

struct PiecesCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var doc: Doc
    var body: some View {
        let outs = Planner.outputs(info: doc.info, segments: doc.segments, opts: effectiveOpts, keyframes: doc.keyframes, base: doc.baseName, mergeName: doc.mergeName)
        let shifts = Planner.shifts(info: doc.info, segments: doc.segments, opts: effectiveOpts, keyframes: doc.keyframes)
        Card {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(L.t("pieces.title", doc.segments.count)).numberTicker(doc.segments.count)
                Spacer()
                if !doc.segments.isEmpty { Text(L.t("pieces.kept", Fmt.time(doc.kept), Fmt.time(doc.duration))).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2) }
            }
            if doc.segments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("pieces.empty")).font(.system(size: 12)).foregroundStyle(Theme.text2)
                    HStack(spacing: 6) { Key("I"); Text(L.t("key.in")).font(.system(size: 11.5)).foregroundStyle(Theme.text2); Key("O"); Text(L.t("key.out")).font(.system(size: 11.5)).foregroundStyle(Theme.text2) }
                }.padding(.vertical, 6)
            }
            ForEach(Array(doc.segments.enumerated()), id: \.element.id) { i, s in
                PieceRow(doc: doc, index: i, segment: s, name: previewName(outs, i), player: model.player)
            }
            if !doc.segments.isEmpty, doc.info.audio != nil { trimBlock }
            if let first = shifts.first {
                InfoBox {
                    (Text(L.t("pieces.shift2", first.0, Fmt.time(first.2)) + " ") + Text(L.t("pieces.shift2.cta")).fontWeight(.bold) + Text(" " + L.t("pieces.shift2.tail")))
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    /// « Retirer les blancs » : l'interrupteur montre tout de suite sur la timeline ce qui serait coupé (hachuré) ; le curseur règle l'intensité en direct ;
    /// « Appliquer » resserre les morceaux (⌘Z rétablit), après quoi on ajuste à la main avec les poignées comme d'habitude.
    private var trimBlock: some View {
        let on = model.opts.trimSilence
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { model.opts.trimSilence.toggle() } label: { Chip(text: L.t("sil.trim"), on: on) }.buttonStyle(.plain)
                if !on { Text(L.t("sil.preview")).font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.tail) }
                Spacer(minLength: 0)
            }
            if on {
                IntensitySlider(model: model)
                if doc.loudness == nil { SilenceProgress(doc: doc) }
                if doc.silences != nil {
                    let gain = doc.segments.reduce(0) { $0 + $1.duration } - doc.tighten(doc.segments, inside: true).reduce(0) { $0 + $1.duration }
                    Text(L.t("sil.est", Fmt.time(max(gain, 0), decimals: true)) + " · " + Fmt.breath(model.opts.trimIntensity) + " s").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2).lineLimit(1)
                    Button {
                        Task { if let g = await doc.trimPiecesSilence() { model.flash(g > 0.05 ? L.t("sil.done", Fmt.time(g, decimals: true)) : L.t("sil.none")) } }
                    } label: { Text(L.t("sil.apply")).frame(maxWidth: .infinity) }.buttonStyle(FlatButton(height: 32))
                }
            }
        }
        .task(id: on) { if on { await doc.ensureSilences() } }
    }
    private var effectiveOpts: ExportOptions { var o = model.opts; if !o.passthrough, o.format == .same { o.format = doc.info.isAudioOnly ? .m4a : .mp4 }; return o }
    private func previewName(_ outs: [OutputItem], _ i: Int) -> String {
        if model.opts.merge { return "…" }
        guard outs.indices.contains(i) else { return "" }
        return outs[i].url.deletingPathExtension().lastPathComponent
    }
}

struct PieceRow: View {
    @ObservedObject var doc: Doc
    let index: Int
    let segment: Segment
    let name: String
    let player: PlayerModel
    var body: some View {
        let sel = doc.selected == segment.id
        HStack(spacing: 9) {
            Text("\(index + 1)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white).frame(width: 20, height: 20).background(doc.color(of: segment), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle).help(name)
                Text("\(Fmt.time(segment.start)) → \(Fmt.time(segment.end))").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(Fmt.time(segment.duration)).font(.system(size: 12.5, weight: .semibold).monospacedDigit())
            Button { doc.delete(segment.id) } label: { Image(systemName: "xmark").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.text2).frame(width: 14, height: 20) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .selectableSurface(selected: sel)
        .contentShape(Rectangle())
        .onTapGesture { doc.selected = segment.id; player.pause(); player.seek(segment.start); doc.ensureVisible(segment.start) }
    }
}

struct ChoiceCard: View {
    let on: Bool, title: String, sub: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                ZStack { Circle().strokeBorder(on ? Theme.accent : Theme.text2, lineWidth: on ? 5 : 1.5) }.frame(width: 16, height: 16).padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(sub).font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            .selectableSurface(selected: on, rest: Theme.ctl)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// Un fichier par personne ou tout dans un seul : observe le choix pour se mettre à jour.
struct PeopleFiles: View {
    @ObservedObject var find: FindModel
    let changed: () -> Void
    var body: some View {
        ChoiceCard(on: find.protoOut == .each, title: L.t("exp.files.people.each"), sub: L.t("exp.files.people.each.sub")) { find.protoOut = .each; changed() }
        ChoiceCard(on: find.protoOut == .merged, title: L.t("exp.files.merged"), sub: L.t("exp.files.people.merged.sub")) { find.protoOut = .merged; changed() }
    }
}

/// Feuille d'options d'export : trois questions (combien de fichiers, quel format, quel son), le dossier, puis un pli « Plus d'options » (noms, codec, qualité).
/// Même feuille pour les morceaux de la timeline et pour les personnes choisies dans l'onglet Personnes.
struct ExportOptionsSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var doc: Doc
    let request: ExportRequest
    var maxHeight: CGFloat = 10_000                     // hauteur disponible dans la fenêtre : au-delà, les questions défilent (titre et boutons restent visibles)
    @State private var more = UserDefaults.standard.bool(forKey: "capture.more")          // ouvert d'office pour les captures (--more)
    @State private var bodyHeight: CGFloat = 0

    private var people: FindModel? { if case .people(let f) = request.kind { return f }; return nil }
    private var eff: ExportOptions { var o = model.opts; if !o.passthrough, o.format == .same { o.format = doc.info.isAudioOnly ? .m4a : .mp4 }; return o }
    private var silenceWait: Bool { model.opts.trimSilence && doc.info.audio != nil && doc.silences == nil }          // la recherche des blancs n'est pas finie
    private var waitingClean: Bool { model.opts.voiceOnly && doc.canClean && doc.clean != .ready }

    var body: some View {
        SheetBox(width: 440, padding: 18, spacing: 14) {
            Text(title).font(.system(size: 16, weight: .bold))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    question(L.t("exp.q.files")) { filesChoice }
                    question(L.t("exp.q.format")) { formatMenu; Text(L.t(model.opts.passthrough ? "exp.format.copy.note" : "exp.format.re.note")).font(.system(size: 11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading) }
                    if doc.canClean { question(L.t("exp.q.sound")) { soundChoice } }
                    if doc.info.audio != nil { question(L.t("exp.q.silence")) { silenceChoice } }
                    question(L.t("exp.q.folder")) { folderRow }
                    Button { withAnimation(.easeOut(duration: 0.15)) { more.toggle() } } label: {
                        HStack { Text(L.t("exp.more")).font(.system(size: 11.5)).foregroundStyle(Theme.text2); Spacer(); Image(systemName: more ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.text2) }
                            .frame(height: 24).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if more { moreOptions }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { g in Color.clear.onAppear { bodyHeight = g.size.height }.onChange(of: g.size.height) { _, h in bodyHeight = h } })
            }
            .frame(height: bodyHeight > 0 ? min(bodyHeight, max(maxHeight - 130, 200)) : nil)
            HStack(spacing: 8) {
                Spacer()
                Button { model.cancelOptions() } label: { Text(L.t("common.cancel")).frame(width: 76) }.buttonStyle(FlatButton(height: 40)).keyboardShortcut(.cancelAction)
                Button { model.confirmExport() } label: { Text(waitingClean ? L.t("clean.building", Int(cleanPercent)) : goLabel).frame(width: 166) }
                    .buttonStyle(FlatButton(kind: .sand, height: 40)).opacity(waitingClean || silenceWait || request.count == 0 ? 0.5 : 1).disabled(waitingClean || silenceWait || request.count == 0)
            }
        }
    }

    private var title: String {
        if let f = people { return f.protoOut == .each && request.count > 1 ? L.n("exp.title.people", request.count) : L.t("exp.title.people.one") }
        return L.n("exp.title", doc.segments.count)
    }
    private var goLabel: String { L.n("exp.confirm", request.count) }
    private var cleanPercent: Double { if case .building(let p) = doc.clean { return (p * 100).rounded() }; return 0 }

    private func question<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) { SectionTitle(label); content() }
    }

    // 1. Combien de fichiers
    @ViewBuilder private var filesChoice: some View {
        if let f = people {
            PeopleFiles(find: f, changed: refresh)
        } else {
            choice(on: !model.opts.merge, title: L.t("exp.files.each"), sub: namesPreview(merge: false)) { model.opts.merge = false; refresh() }
            choice(on: model.opts.merge, title: L.t("exp.files.merged"), sub: namesPreview(merge: true)) { model.opts.merge = true; refresh() }
        }
    }
    /// Le nombre de fichiers annoncé suit le choix : on relance le calcul depuis la demande d'origine.
    private func refresh() {
        guard let f = people else { model.request?.count = Planner.outputs(info: doc.info, segments: doc.segments, opts: model.opts, keyframes: doc.keyframes, base: doc.baseName, mergeName: doc.mergeName).count; return }
        let each = f.protoOut == .each
        model.request?.count = each ? f.exportGroups(each: true).filter { !$0.segments.isEmpty }.count : (f.protoUnion.isEmpty ? 0 : 1)
    }
    private func namesPreview(merge: Bool) -> String {
        var o = eff; o.merge = merge
        let outs = Planner.outputs(info: doc.info, segments: doc.segments, opts: o, keyframes: doc.keyframes, base: doc.baseName, mergeName: doc.mergeName)
        let names = outs.map { $0.url.deletingPathExtension().lastPathComponent }
        guard names.count > 1, let first = names.first else { return names.first ?? "" }
        // noms numérotés : on n'affiche que la partie qui change (« …_01, …_02, …_03 »)
        var common = first.count
        for n in names { common = min(common, zip(first, n).prefix { $0 == $1 }.count) }
        let tails = names.map { "…" + String($0.dropFirst(max(common - 1, 0))) }
        return tails.count > 3 ? tails.prefix(2).joined(separator: ", ") + ", … " + (tails.last ?? "") : tails.joined(separator: ", ")
    }
    private func choice(on: Bool, title: String, sub: String, _ action: @escaping () -> Void) -> some View { ChoiceCard(on: on, title: title, sub: sub, action: action) }

    // 2. Format
    private var formatMenu: some View {
        let info = doc.info
        let copyable = (OutFormat.video + OutFormat.audio).filter { f in (!info.isAudioOnly || f.isAudio) && Planner.canCopy(info: info, to: f) }
        let all = (OutFormat.video + OutFormat.audio).filter { f in !info.isAudioOnly || f.isAudio }
        return Menu {
            Section(L.t("exp.format.copy")) {
                Button(L.t("exp.format.same")) { setFormat(.same, copy: true) }
                ForEach(copyable.filter { $0 != .same }, id: \.self) { f in Button(f.title) { setFormat(f, copy: true) } }
            }
            Section(L.t("exp.format.re")) { ForEach(all, id: \.self) { f in Button(f.title) { setFormat(f, copy: false) } } }
        } label: {
            Text(formatTitle).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .padding(.horizontal, 12).frame(height: 34).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ctl, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
        .overlay(alignment: .trailing) { Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.text2).padding(.trailing, 12).allowsHitTesting(false) }
    }
    private var formatTitle: String {
        let f = eff.resolvedFormat(for: doc.info)
        if model.opts.passthrough { return model.opts.format == .same ? L.t("exp.format.same") : L.t("exp.format.copyto", f.title) }
        return L.t("exp.format.reto", f.title)
    }
    private func setFormat(_ f: OutFormat, copy: Bool) {
        model.opts.passthrough = copy
        model.opts.format = (!copy && f == .same) ? (doc.info.isAudioOnly ? .m4a : .mp4) : f
    }

    // 3. Son
    private var soundChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Segmented(options: [(false, L.t("exp.sound.original")), (true, L.t("clean.export"))], selection: voiceBinding)
            switch doc.clean {
            case .building(let p) where model.opts.voiceOnly: Text(L.t("clean.building", Int((p * 100).rounded()))).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2)
            case .ready where model.opts.voiceOnly: Text(L.t("exp.sound.ready")).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
            default: if model.opts.voiceOnly { Text(L.t("exp.sound.note")).font(.system(size: 11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
    private var voiceBinding: Binding<Bool> {
        Binding(get: { model.opts.voiceOnly }, set: { v in model.opts.voiceOnly = v; if v, doc.clean == .none || doc.clean == .failed { doc.buildClean() } })
    }

    // 4. Blancs
    private var silenceChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Segmented(options: [(false, L.t("exp.silence.keep")), (true, L.t("exp.silence.remove"))], selection: Binding(
                get: { model.opts.trimSilence },
                set: { v in
                    model.opts.trimSilence = v
                    if v { if !doc.info.isAudioOnly { model.opts.passthrough = false }; Task { await doc.ensureSilences() } }       // couper dans les blancs demande une recompression
                }))
            if model.opts.trimSilence {
                IntensitySlider(model: model)
                if doc.loudness == nil { SilenceProgress(doc: doc) }
                let note: String = {
                    guard let sil = doc.silences else { return "" }
                    if let f = people {
                        let segs = f.protoUnion.map { Segment(start: $0.start, end: $0.end) }
                        _ = sil; let gain = segs.reduce(0) { $0 + $1.duration } - doc.tighten(segs, inside: true).reduce(0) { $0 + $1.duration }
                        return L.t("exp.silence.result.merge", Fmt.time(max(gain, 0), decimals: true), Fmt.breath(model.opts.trimIntensity))
                    }
                    let gain = doc.segments.reduce(0) { $0 + $1.duration } - doc.exportSegments(eff).reduce(0) { $0 + $1.duration }
                    return L.t(model.opts.merge ? "exp.silence.result.merge" : "exp.silence.result.edges", Fmt.time(max(gain, 0), decimals: true), Fmt.breath(model.opts.trimIntensity))
                }()
                if !note.isEmpty { Text(note + (doc.info.isAudioOnly ? "" : " " + L.t("exp.silence.recode"))).font(.system(size: 11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .task(id: model.opts.trimSilence) { if model.opts.trimSilence { await doc.ensureSilences() } }          // l'option déjà active à l'ouverture de la feuille : la mesure part toute seule
    }

    // Dossier
    private var folderRow: some View {
        HStack(spacing: 8) {
            Text(model.opts.folder.map { ($0 as NSString).lastPathComponent } ?? L.t("export.sameFolder")).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            Button { chooseFolder() } label: { Text(L.t("exp.choose")) }.buttonStyle(FlatButton(height: 26))
        }
        .padding(.horizontal, 12).frame(height: 34).background(Theme.ctl, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
    }

    // Plus d'options
    @ViewBuilder private var moreOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let f = people { peopleNames(f) } else { names }
            if !model.opts.passthrough, !eff.resolvedFormat(for: doc.info).isAudio, !doc.info.isAudioOnly {
                row(L.t("export.codec")) {
                    Menu {
                        ForEach(VideoCodec.allCases.filter { c in Planner.codecFor(eff.resolvedFormat(for: doc.info), c) == c }, id: \.self) { c in Button(c.title) { model.opts.codec = c } }
                        Divider()
                        ForEach(Quality.allCases, id: \.self) { q in Button(q.title) { model.opts.quality = q } }
                    } label: { Text("\(Planner.codecFor(eff.resolvedFormat(for: doc.info), model.opts.codec).title) · \(model.opts.quality.title) ▾").font(.system(size: 12, weight: .semibold)) }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
            if people == nil && !doc.segments.isEmpty {
                let est = Planner.estimate(info: doc.info, segments: doc.segments, opts: eff)
                HStack(alignment: .firstTextBaseline) { Text(L.t("export.estSize")).font(.system(size: 11.5)).foregroundStyle(Theme.text2); Spacer()
                    Text("≈ \(Fmt.size(est.bytes))").font(.system(size: 12, weight: .semibold).monospacedDigit()) }
                HStack(alignment: .firstTextBaseline) { Text(L.t("export.estTime")).font(.system(size: 11.5)).foregroundStyle(Theme.text2); Spacer()
                    Text("≈ " + (est.seconds < 60 ? "\(Int(est.seconds.rounded(.up))) s" : Fmt.time(est.seconds, decimals: false))).font(.system(size: 12, weight: .semibold).monospacedDigit()) }
            }
        }
    }

    /// Noms des fichiers produits, modifiables : un nom de base commun, puis un nom propre à chaque morceau (ou celui du fichier fusionné).
    private var names: some View {
        let outs = Planner.outputs(info: doc.info, segments: doc.segments, opts: eff, keyframes: doc.keyframes, base: doc.baseName, mergeName: doc.mergeName)
        let ext = outs.first?.url.pathExtension ?? eff.resolvedFormat(for: doc.info).ext(source: doc.info.ext)
        let original = doc.info.url.deletingPathExtension().lastPathComponent
        return VStack(alignment: .leading, spacing: 6) {
            if !outs.isEmpty {
                if model.opts.merge {
                    nameField(placeholder: outs[0].url.deletingPathExtension().lastPathComponent, text: $doc.mergeName, ext: ext)
                } else {
                    HStack { Text(L.t("export.baseName")).font(.system(size: 11.5)).foregroundStyle(Theme.text2); Spacer(minLength: 6) }
                    nameField(placeholder: original, text: $doc.baseName, ext: nil)
                    VStack(spacing: 4) {
                        ForEach(Array(outs.enumerated()), id: \.offset) { i, o in
                            nameField(placeholder: o.url.deletingPathExtension().lastPathComponent, text: pieceName(o.segments.first?.id), ext: ext)
                        }
                    }
                }
            }
        }
    }

    /// Noms des fichiers des personnes : un champ par fichier (un par personne, ou un seul pour les moments réunis).
    private func peopleNames(_ f: FindModel) -> some View {
        let base = Planner.sanitize(doc.baseName.isEmpty ? doc.info.url.deletingPathExtension().lastPathComponent : doc.baseName)
        let ext = eff.resolvedFormat(for: doc.info).ext(source: doc.info.ext)
        let groups = f.exportGroups(each: f.protoOut == .each).filter { !$0.segments.isEmpty }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(groups, id: \.name) { g in
                VStack(alignment: .leading, spacing: 3) {          // la personne en étiquette : un nom de fichier long la cacherait dans le champ
                    Text(g.name).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.tail)
                    nameField(placeholder: "\(base) – \(g.name)", text: Binding(get: { f.protoNames[g.name] ?? "" }, set: { f.protoNames[g.name] = $0 }), ext: ext)
                }
            }
        }
    }

    private func pieceName(_ id: UUID?) -> Binding<String> {
        Binding(get: { doc.segments.first { $0.id == id }?.name ?? "" },
                set: { v in if let i = doc.segments.firstIndex(where: { $0.id == id }) { doc.segments[i].name = v.trimmingCharacters(in: .whitespaces).isEmpty ? nil : v } })
    }

    /// Champ de nom : le nom automatique s'affiche en gris tant que rien n'est saisi ; l'extension est fixe.
    private func nameField(placeholder: String, text: Binding<String>, ext: String?) -> some View {
        HStack(spacing: 2) {
            TextField("", text: text, prompt: Text(placeholder).foregroundColor(Theme.text2)).textFieldStyle(.plain).focusEffectDisabled()
                .font(.system(size: 11.5, design: .monospaced)).lineLimit(1)
            if let ext { Text("." + ext).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.text2) }
        }
        .padding(.horizontal, 9).frame(height: 26).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.text.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
    }
    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack { Text(label).font(.system(size: 12)).foregroundStyle(Theme.text2); Spacer(minLength: 6); content() }
            .padding(.horizontal, 10).frame(height: 30).background(Theme.ctl, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
    }
    private func chooseFolder() {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true
        if p.runModal() == .OK { model.opts.folder = p.url?.path } else if model.opts.folder != nil, NSEvent.modifierFlags.contains(.option) { model.opts.folder = nil }
    }
}

// MARK: - Feuilles (export en cours / terminé) et raccourcis

struct SheetLayer: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ZStack {
            Color.black.opacity(0.36).ignoresSafeArea().onTapGesture { if model.sheet == .options { model.cancelOptions() } }
            if model.sheet == .options, let d = model.current, let r = model.request {
                GeometryReader { g in ExportOptionsSheet(model: model, doc: d, request: r, maxHeight: g.size.height - 40).frame(width: g.size.width, height: g.size.height) }
            } else if let run = model.run {
                if model.sheet == .export { ExportProgressSheet(model: model, run: run) } else { DoneSheet(model: model, run: run) }
            }
        }
    }
}

struct SheetBox<Content: View>: View {
    var width: CGFloat = 520
    var padding: CGFloat = 20
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(padding).frame(width: width)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.rSheet, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.rSheet, style: .continuous).strokeBorder(Theme.line, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
    }
}

struct ExportProgressSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var run: ExportRun
    var body: some View {
        SheetBox {
            Text(run.error == nil ? L.t("export.running") : L.t("export.failed")).font(.system(size: 16, weight: .bold))
            Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
            VStack(spacing: 10) {
                ForEach(run.items) { it in
                    VStack(spacing: 5) {
                        HStack { Text(it.name).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle).help(it.name); Spacer(minLength: 8); Text(status(it)).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2) }
                        ProgressBar(value: it.fraction)
                    }
                }
            }
            if let e = run.error { Text(e).font(.system(size: 11.5)).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Text(L.t("export.progress", Int(run.overall * 100))).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                Spacer()
                if run.error != nil { Button(L.t("common.close")) { model.closeSheet() }.buttonStyle(FlatButton(kind: .primary)) }
                else { Button { model.cancelExport() } label: { HStack(spacing: 8) { Text(L.t("common.cancel")); Key("Esc") } }.buttonStyle(FlatButton()) }
            }
        }
    }
    private var subtitle: String {
        guard let d = model.current else { return "" }
        return "\(d.name) → \(L.n("export.files", run.items.count))" + (model.opts.passthrough ? " · " + L.t("export.passthrough") : "") + " · " + (model.opts.folder == nil ? L.t("export.sameFolder") : (model.opts.folder! as NSString).lastPathComponent)
    }
    private func status(_ it: ExportRun.Item) -> String {
        switch it.state { case .waiting: L.t("export.waiting"); case .running: "\(Int(it.fraction * 100)) %"; case .done: "✓ " + Fmt.size(it.bytes); case .failed: L.t("export.failed"); case .cancelled: L.t("export.cancelled") }
    }
}

struct ProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in ZStack(alignment: .leading) { RoundedRectangle(cornerRadius: Theme.rChip, style: .continuous).fill(Theme.ctl); RoundedRectangle(cornerRadius: Theme.rChip, style: .continuous).fill(Theme.seg).frame(width: g.size.width * min(max(value, 0), 1)) } }.frame(height: 6)
    }
}

struct DoneSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var run: ExportRun
    var body: some View {
        SheetBox {
            // Encart de résumé : tout est centré (Socle).
            VStack(alignment: .center, spacing: 8) {
                Image(systemName: "checkmark").font(.system(size: 22, weight: .bold)).foregroundStyle(.white).frame(width: 44, height: 44).background(Theme.ok, in: Circle())
                Text(L.n("done.title", run.items.count)).font(.system(size: 16, weight: .bold)).contentTransition(.numericText())
                Text(L.t("done.sub", Fmt.size(run.totalBytes), Fmt.dec(run.elapsed))).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2)
            }
            .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            VStack(spacing: 6) {
                ForEach(run.items) { it in
                    HStack { Text(it.name).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle).help(it.name); Spacer(minLength: 8)
                        Text("\(Fmt.time(it.duration)) · \(Fmt.size(it.bytes))").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2) }
                        .padding(.horizontal, 10).frame(height: 30).background(Theme.ctl, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
                }
            }
            HStack(spacing: 8) {
                Spacer()
                Button(L.t("done.trash")) { model.trashOriginal() }.buttonStyle(FlatButton())
                Button(L.t("done.reveal")) { model.reveal() }.buttonStyle(FlatButton())
                Button(L.t("common.close")) { model.closeSheet() }.buttonStyle(FlatButton(kind: .primary))
            }
        }
    }
}

struct ShortcutsLayer: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ZStack {
            Color.black.opacity(0.36).ignoresSafeArea().onTapGesture { model.showShortcuts = false }
            SheetBox(width: 420) {
                Text(L.t("bar.shortcuts")).font(.system(size: 16, weight: .bold))
                ForEach([("I", "key.in.long"), ("O", "key.out.long"), ("Espace", "key.play"), ("J  K  L", "key.speed"), ("←  →", "key.frame"), ("⇧← ⇧→", "key.second"), ("↑  ↓", "key.keyframe.long"),
                         ("[  ]", "key.piece"), ("⌫", "key.delete"), ("⌘Z", "key.undo"), ("⌘↩", "key.export"), ("Home  End", "key.startend")], id: \.0) { k, t in
                    HStack { Key(k); Text(L.t(t)).font(.system(size: 12.5)); Spacer() }
                }
                HStack { Spacer(); Button(L.t("common.close")) { model.showShortcuts = false }.buttonStyle(FlatButton(kind: .primary)) }
            }
        }
    }
}
