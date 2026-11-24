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
                Capsule().fill(Theme.ctl).frame(height: 5)
                Capsule().fill(Theme.accent).frame(width: g.size.width * value, height: 5)
                Circle().fill(.white).frame(width: 13, height: 13).shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                    .offset(x: g.size.width * value - 6.5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value = min(max($0.location.x / g.size.width, 0), 1) })
        }.frame(height: 18)
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
                    .background(Theme.accent, in: Capsule()).padding(.bottom, 18) }.transition(.opacity)
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
    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 78)      // emplacement des trois boutons de fenêtre
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                (Text("m").foregroundColor(Theme.brand) + Text("SLICE")).font(.system(size: 15, weight: .bold))
                if let d = model.current {
                    HStack(spacing: 0) {
                        Text(d.name).fontWeight(.semibold).foregroundStyle(Theme.text)
                        Text(" · " + d.info.summary).foregroundStyle(Theme.text2)
                    }.font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Button { model.showShortcuts.toggle() } label: { HStack(spacing: 8) { Text(L.t("bar.shortcuts")); Key("⌘/") } }.buttonStyle(FlatButton())
                Button { AppDelegate.shared?.openSettings() } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .medium)).frame(width: 6) }.buttonStyle(FlatButton())
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
            SectionTitle(L.t("files.title", model.docs.count)).padding(.horizontal, 4).padding(.bottom, 4)
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
                Text(doc.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text("\(Fmt.time(doc.duration, decimals: false)) · \(Fmt.size(doc.info.size))").font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(1)
                if doc.exported { HStack { Spacer(); Tag(text: L.t("files.extracted"), kind: .ok, symbol: "checkmark") }.padding(.top, 2) }
                else if !doc.segments.isEmpty { HStack { Spacer(); Tag(text: L.t(doc.segments.count == 1 ? "files.piece" : "files.pieces", doc.segments.count), kind: selected ? .accent : .plain) }.padding(.top, 2) }
            }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Theme.ctl : .clear, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
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
            if doc.hasVideo { PlayerSurface(player: player.player) } else {
                VStack(spacing: 8) { Image(systemName: "waveform").font(.system(size: 40, weight: .light)); Text(doc.name).font(.system(size: 13)) }.foregroundStyle(.white.opacity(0.7))
            }
            if let p = player.preparing { Text(p).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white).padding(.horizontal, 12).frame(height: 28).background(.black.opacity(0.6), in: Capsule()) }
            VStack {
                HStack {
                    OverlayChip(text: doc.name)
                    Spacer()
                    if let i = segmentIndex { OverlayChip(text: L.t("player.inPiece", i + 1), fill: Theme.seg, bold: true) }
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
            .foregroundStyle(.white).lineLimit(1).padding(.horizontal, 10).frame(height: 22).background(fill, in: Capsule())
    }
}

struct TransportBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var doc: Doc
    @ObservedObject var player: PlayerModel
    var body: some View {
        HStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Fmt.time(player.time)).font(.system(size: 22, weight: .semibold).monospacedDigit())
                Text("/ " + Fmt.time(doc.duration)).font(.system(size: 12)).foregroundStyle(Theme.text2)
            }.padding(.trailing, 6)
            roundButton("backward.end.fill") { player.pause(); player.seek(doc.segments.last(where: { $0.start < player.time - 0.05 })?.start ?? 0) }
            roundButton("backward.fill") { player.pause(); player.seek(player.time - 1) }
            Button { player.togglePlay() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 14, weight: .semibold)).frame(width: 42, height: 34)
                .foregroundStyle(Theme.onAccent).background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous)) }.buttonStyle(.plain)
            roundButton("forward.fill") { player.pause(); player.seek(player.time + 1) }
            roundButton("forward.end.fill") { player.pause(); player.seek(doc.segments.first(where: { $0.start > player.time + 0.05 })?.start ?? doc.duration) }
            Spacer(minLength: 8)
            scalpelButton("I", L.t("tr.in")) { doc.markIn(at: player.time, snap: model.snap && model.opts.passthrough) }
            scalpelButton("O", L.t("tr.out")) { doc.markOut(at: player.time) }
        }.frame(height: 42)
    }
    private func roundButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).frame(width: 34, height: 34).foregroundStyle(Theme.text)
            .background(Theme.ctl, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous)) }.buttonStyle(.plain)
    }
    private func scalpelButton(_ key: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ScalpelShape().stroke(Theme.text, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)).frame(width: 16, height: 16)
                Key(key); Text(label)
            }
        }.buttonStyle(FlatButton(height: 34))
    }
}

struct TimelineCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var doc: Doc
    let player: PlayerModel          // pas observé : la tête de lecture est un calque qui se met à jour seul
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(L.t("tl.zoom")).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                FlatSlider(value: zoomBinding).frame(width: 90)
                Text(String(format: "%.0f×", max(doc.duration / max(doc.viewSpan, 0.1), 1))).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2).frame(minWidth: 26, alignment: .leading)
                Button { model.snap.toggle() } label: { Chip(text: L.t("tl.snap"), on: model.snap && model.opts.passthrough, enabled: model.opts.passthrough && doc.hasVideo) }.buttonStyle(.plain)
                    .help(L.t("tl.snap.help"))
                Button { Task { await autoTrim() } } label: { Chip(text: L.t("tl.auto"), enabled: doc.info.audio != nil) }.buttonStyle(.plain)
                Spacer(minLength: 0)
            }.frame(height: 26).padding(.bottom, 4)
            TimelineRepresentable(doc: doc, player: player, snap: model.snap && model.opts.passthrough).frame(height: TimelineView.totalH)
            HStack(spacing: 10) {
                legend("I", L.t("key.in")); legend("O", L.t("key.out")); legend("Espace", L.t("key.play")); legend("J K L", L.t("key.speed"))
                legend("← →", L.t("key.frame")); legend("↑ ↓", L.t("key.keyframe")); legend("⌫", L.t("key.delete"))
                Spacer(minLength: 0)
            }.padding(.top, 8).overlay(alignment: .top) { Rectangle().fill(Theme.text2.opacity(0.18)).frame(height: 0.5) }.padding(.top, 8)
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
    var body: some View {
        VStack(spacing: 10) {
            PiecesCard(model: model, doc: doc)
            ExportCard(model: model, doc: doc)
            Spacer(minLength: 0)
            Button { model.exportNow() } label: {
                Text(model.opts.merge ? L.t("export.go.merged") : L.t(doc.segments.count == 1 ? "export.go.one" : "export.go.n", doc.segments.count)).frame(maxWidth: .infinity)
            }.buttonStyle(FlatButton(kind: .sand, height: 42)).opacity(doc.segments.isEmpty ? 0.4 : 1).disabled(doc.segments.isEmpty)
        }
        .padding(.top, 14).padding(.bottom, 14).padding(.trailing, 14)
    }
}

struct PiecesCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var doc: Doc
    var body: some View {
        let outs = Planner.outputs(info: doc.info, segments: doc.segments, opts: effectiveOpts, keyframes: doc.keyframes)
        let shifts = Planner.shifts(info: doc.info, segments: doc.segments, opts: effectiveOpts, keyframes: doc.keyframes)
        Card {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(L.t("pieces.title", doc.segments.count))
                Spacer()
                if !doc.segments.isEmpty { Text(L.t("pieces.kept", Fmt.time(doc.kept), Fmt.time(doc.duration))).font(.system(size: 11.5)).foregroundStyle(Theme.text2) }
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
            if let first = shifts.first {
                (Text(L.t("pieces.shift.lead")).foregroundColor(Theme.warn).fontWeight(.semibold) + Text(" " + L.t("pieces.shift", first.0, Fmt.time(first.2), Fmt.dec(first.1 - first.2))))
                    .font(.system(size: 11)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
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
            Text("\(index + 1)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white).frame(width: 20, height: 20).background(Theme.seg, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text("\(Fmt.time(segment.start)) → \(Fmt.time(segment.end))").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(Fmt.time(segment.duration)).font(.system(size: 12.5, weight: .semibold).monospacedDigit())
            Button { doc.delete(segment.id) } label: { Image(systemName: "xmark").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.text2).frame(width: 14, height: 20) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(sel ? Theme.ctl : .clear, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous).strokeBorder(sel ? Theme.seg : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { doc.selected = segment.id; player.pause(); player.seek(segment.start); doc.ensureVisible(segment.start) }
    }
}

struct ExportCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var doc: Doc
    var body: some View {
        let info = doc.info
        let est = Planner.estimate(info: info, segments: doc.segments, opts: eff)
        Card {
            Segmented(options: [(false, L.t("export.separate")), (true, L.t("export.merge"))], selection: $model.opts.merge)
            names
            Segmented(options: [(true, L.t("export.passthrough")), (false, L.t("export.recompress"))], selection: passthroughBinding)
            FlowLayout(spacing: 5) {
                if model.opts.passthrough { fmtChip(.same) }
                ForEach(OutFormat.video + OutFormat.audio, id: \.self) { fmtChip($0) }
            }
            if !model.opts.passthrough, !eff.resolvedFormat(for: info).isAudio, !info.isAudioOnly {
                row(L.t("export.codec")) {
                    Menu {
                        ForEach(VideoCodec.allCases.filter { c in Planner.codecFor(eff.resolvedFormat(for: info), c) == c }, id: \.self) { c in Button(c.title) { model.opts.codec = c } }
                        Divider()
                        ForEach(Quality.allCases, id: \.self) { q in Button(q.title) { model.opts.quality = q } }
                    } label: { Text("\(Planner.codecFor(eff.resolvedFormat(for: info), model.opts.codec).title) · \(model.opts.quality.title) ▾").font(.system(size: 12, weight: .semibold)) }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
            row(L.t("export.folder")) {
                Button { chooseFolder() } label: { Text((model.opts.folder.map { ($0 as NSString).lastPathComponent } ?? L.t("export.sameFolder")) + " ▾").font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle) }.buttonStyle(.plain)
            }
            HStack(alignment: .firstTextBaseline) { Text(L.t("export.estSize")).font(.system(size: 11.5)).foregroundStyle(Theme.text2); Spacer()
                Text(doc.segments.isEmpty ? "—" : "≈ \(Fmt.size(est.bytes)) · −\(Fmt.size(max(info.size - est.bytes, 0)))").font(.system(size: 12, weight: .semibold).monospacedDigit()) }
            HStack(alignment: .firstTextBaseline) { Text(L.t("export.estTime")).font(.system(size: 11.5)).foregroundStyle(Theme.text2); Spacer()
                Text(doc.segments.isEmpty ? "—" : "≈ " + (est.seconds < 60 ? "\(Int(est.seconds.rounded(.up))) s" : Fmt.time(est.seconds, decimals: false))).font(.system(size: 12, weight: .semibold).monospacedDigit()) }
        }
    }
    private var eff: ExportOptions { var o = model.opts; if !o.passthrough, o.format == .same { o.format = doc.info.isAudioOnly ? .m4a : .mp4 }; return o }
    private var passthroughBinding: Binding<Bool> {
        Binding(get: { model.opts.passthrough }, set: { v in
            model.opts.passthrough = v
            if v { if !Planner.canCopy(info: doc.info, to: model.opts.format) { model.opts.format = .same } }
            else if model.opts.format == .same { model.opts.format = doc.info.isAudioOnly ? .m4a : .mp4 }
        })
    }
    private var names: some View {
        let outs = Planner.outputs(info: doc.info, segments: doc.segments, opts: eff, keyframes: doc.keyframes)
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(outs.prefix(4).enumerated()), id: \.offset) { _, o in Text(o.url.lastPathComponent).font(.system(size: 11.5, design: .monospaced)).lineLimit(1).truncationMode(.middle) }
            if outs.count > 4 { Text("… +\(outs.count - 4)").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.text2) }
            if model.opts.merge { Text(L.t("export.mergeNote", doc.segments.count)).font(.system(size: 11)).foregroundStyle(Theme.text2) }
        }
        .padding(.horizontal, 9).padding(.vertical, outs.isEmpty ? 0 : 7).frame(maxWidth: .infinity, alignment: .leading)
        .background(outs.isEmpty ? .clear : Theme.text.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
    }
    private func fmtChip(_ f: OutFormat) -> some View {
        let info = doc.info
        var ok = true
        if info.isAudioOnly && !f.isAudio && f != .same { ok = false }
        if model.opts.passthrough, ok { ok = Planner.canCopy(info: info, to: f) }
        let on = model.opts.format == f || (!model.opts.passthrough && model.opts.format == .same && f == (info.isAudioOnly ? .m4a : .mp4))
        return Button { if ok { model.opts.format = f } } label: {
            Text(f.title).font(.system(size: 11.5, weight: on ? .semibold : .regular)).lineLimit(1).padding(.horizontal, 9).frame(height: 24)
                .foregroundStyle(on ? Theme.onAccent : Theme.text).background(on ? Theme.accent : Theme.ctl, in: Capsule()).opacity(ok ? 1 : 0.4)
        }.buttonStyle(.plain)
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
            Color.black.opacity(0.36).ignoresSafeArea()
            if let run = model.run {
                if model.sheet == .export { ExportProgressSheet(model: model, run: run) } else { DoneSheet(model: model, run: run) }
            }
        }
    }
}

struct SheetBox<Content: View>: View {
    var width: CGFloat = 520
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(20).frame(width: width)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous).strokeBorder(Theme.line, lineWidth: 0.5))
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
                        HStack { Text(it.name).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle); Spacer(minLength: 8); Text(status(it)).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2) }
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
        return "\(d.name) → \(L.t("export.files", run.items.count))" + (model.opts.passthrough ? " · " + L.t("export.passthrough") : "") + " · " + (model.opts.folder == nil ? L.t("export.sameFolder") : (model.opts.folder! as NSString).lastPathComponent)
    }
    private func status(_ it: ExportRun.Item) -> String {
        switch it.state { case .waiting: L.t("export.waiting"); case .running: "\(Int(it.fraction * 100)) %"; case .done: "✓ " + Fmt.size(it.bytes); case .failed: L.t("export.failed"); case .cancelled: L.t("export.cancelled") }
    }
}

struct ProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in ZStack(alignment: .leading) { Capsule().fill(Theme.ctl); Capsule().fill(Theme.seg).frame(width: g.size.width * min(max(value, 0), 1)) } }.frame(height: 6)
    }
}

struct DoneSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var run: ExportRun
    var body: some View {
        SheetBox {
            HStack(spacing: 14) {
                Image(systemName: "checkmark").font(.system(size: 22, weight: .bold)).foregroundStyle(.white).frame(width: 44, height: 44).background(Theme.ok, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("done.title", run.items.count)).font(.system(size: 16, weight: .bold))
                    Text(L.t("done.sub", Fmt.size(run.totalBytes), Fmt.dec(run.elapsed))).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                }
            }
            VStack(spacing: 6) {
                ForEach(run.items) { it in
                    HStack { Text(it.name).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle); Spacer(minLength: 8)
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
