// mSLICE — « Élaguer début et fin » en lot : retire X s au début et Y s à la fin de plusieurs fichiers (ou les silences d'ouverture et de fin), sans ouvrir l'éditeur.
import AppKit
import SwiftUI

@MainActor
final class BatchModel: ObservableObject {
    let urls: [URL]
    @Published var startSec = 15.0
    @Published var endSec = 20.0
    @Published var detect = false
    @Published var passthrough = true
    @Published var running = false
    @Published var finished = false
    @Published var current = ""
    @Published var overall = 0.0
    @Published var notes: [String] = []
    @Published var results: [URL] = []

    init(urls: [URL]) {
        self.urls = urls
        startSec = UserDefaults.standard.object(forKey: "batch.start") as? Double ?? 15
        endSec = UserDefaults.standard.object(forKey: "batch.end") as? Double ?? 20
        passthrough = UserDefaults.standard.object(forKey: "batch.passthrough") as? Bool ?? true
    }

    func start() async {
        UserDefaults.standard.set(startSec, forKey: "batch.start"); UserDefaults.standard.set(endSec, forKey: "batch.end"); UserDefaults.standard.set(passthrough, forKey: "batch.passthrough")
        running = true; finished = false; notes = []; results = []
        for (i, u) in urls.enumerated() {
            current = u.lastPathComponent
            guard let info = await Task.detached(operation: { Probe.read(u) }).value else { notes.append(L.t("err.unsupported", u.lastPathComponent)); continue }
            var a = startSec, b = info.duration - endSec
            if detect {
                guard let r = await Silence.detect(info) else { notes.append("\(u.lastPathComponent) : " + L.t("tl.auto.none")); continue }
                a = r.start; b = r.end
            }
            guard b - a > 0.5, a >= 0 else {
                notes.append(L.t("batch.skipped", u.lastPathComponent, String(format: "%g", startSec), String(format: "%g", endSec))); continue
            }
            var opts = ExportOptions(); opts.passthrough = passthrough; opts.merge = true; opts.suffix = "elague"
            if !passthrough { opts.format = info.isAudioOnly ? .m4a : .mp4 }
            let kf = passthrough && !info.isAudioOnly ? await Task.detached(operation: { Probe.keyframes(info) }).value : []
            let outs = Planner.outputs(info: info, segments: [Segment(start: a, end: b)], opts: opts, keyframes: kf)
            let run = ExportRun()
            run.start(info: info, outputs: outs, opts: opts, keyframes: kf)
            while !run.finished { overall = (Double(i) + run.overall) / Double(urls.count); try? await Task.sleep(nanoseconds: 100_000_000) }
            if let e = run.error { notes.append("\(u.lastPathComponent) : \(e)") } else { results.append(contentsOf: run.results) }
        }
        overall = 1; running = false; finished = true
        if !results.isEmpty, !AppModel.isSelfTest { NSWorkspace.shared.activateFileViewerSelecting(results) }
    }
}

struct BatchView: View {
    @ObservedObject var model: BatchModel
    var close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            (Text("m").foregroundColor(Theme.brand) + Text("SLICE — ") + Text(L.t("batch.title"))).font(.system(size: 15, weight: .bold))
            Text(model.urls.map(\.lastPathComponent).joined(separator: " · ")).font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(3).truncationMode(.middle).help(model.urls.map(\.lastPathComponent).joined(separator: "\n"))
            if model.running || model.finished { progress } else { form }
        }
        .padding(18).frame(width: 460).background(Theme.bg)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            field(L.t("batch.start"), $model.startSec).disabled(model.detect).opacity(model.detect ? 0.45 : 1)
            field(L.t("batch.end"), $model.endSec).disabled(model.detect).opacity(model.detect ? 0.45 : 1)
            toggle(L.t("batch.silence"), $model.detect)
            toggle(L.t("batch.passthrough"), $model.passthrough)
            Text(L.t("batch.result", resultName)).font(.system(size: 11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button(L.t("common.cancel"), action: close).buttonStyle(FlatButton())
                Button { Task { await model.start() } } label: { Text(L.n("batch.go", model.urls.count)) }.buttonStyle(FlatButton(kind: .sand))
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.running { Text(L.t("batch.running", model.current)).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle) }
            else { Text(L.n("batch.done", model.results.count)).font(.system(size: 14, weight: .bold)).multilineTextAlignment(.center).frame(maxWidth: .infinity) }
            ProgressBar(value: model.overall)
            ForEach(model.notes, id: \.self) { Text($0).font(.system(size: 11.5)).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true) }
            HStack { Spacer(); Button(L.t("common.close"), action: close).buttonStyle(FlatButton(kind: .primary)).disabled(model.running) }
        }
    }

    private var resultName: String { (model.urls.first?.deletingPathExtension().lastPathComponent ?? "") + "_elague." + (model.urls.first?.pathExtension ?? "mp4") }

    private func field(_ label: String, _ v: Binding<Double>) -> some View {
        HStack { Text(label).font(.system(size: 12.5)); Spacer()
            TextField("", value: v, format: .number).textFieldStyle(.plain).multilineTextAlignment(.trailing).frame(width: 60).font(.system(size: 12.5, weight: .semibold).monospacedDigit())
            Text(L.t("batch.seconds")).font(.system(size: 12.5)).foregroundStyle(Theme.text2) }
            .padding(.horizontal, 10).frame(height: 32).background(Theme.ctl, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
    }
    private func toggle(_ label: String, _ v: Binding<Bool>) -> some View {
        HStack { Text(label).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 8); FlatSwitch(isOn: v) }.frame(minHeight: 22)
    }
}
