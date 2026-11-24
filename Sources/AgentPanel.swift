// mSLICE — panneau de discussion avec l'agent (onglet « Agent » du panneau de droite).
import AppKit
import SwiftUI

struct AgentPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var chat: AgentChat
    @AppStorage("agent.enabled") private var enabled = false
    @State private var input = ""

    var body: some View {
        VStack(spacing: 10) {
            header
            if !enabled { offCard; Spacer(minLength: 0) } else { conversation; composer }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            SectionTitle(L.t("agent.title"))
            Tag(text: AgentConfig.backend.title, kind: .plain)
            Spacer()
            iconButton("arrow.counterclockwise", L.t("agent.new")) { chat.reset() }.opacity(chat.messages.isEmpty ? 0.4 : 1).disabled(chat.messages.isEmpty)
            iconButton("gearshape", L.t("agent.settings")) { AppDelegate.shared?.openSettings() }
        }.padding(.horizontal, 2)
    }

    private func iconButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.text2).frame(width: 26, height: 26)
                .background(Theme.ctl, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
        }.buttonStyle(.plain).help(help)
    }

    private var offCard: some View {
        Card {
            Text(L.t("agent.off.title")).font(.system(size: 13, weight: .semibold))
            Text(L.t("agent.off.body")).font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            Button { enabled = true } label: { Text(L.t("agent.off.enable")).frame(maxWidth: .infinity) }.buttonStyle(FlatButton(kind: .primary))
        }
    }

    private var conversation: some View {
        Card(padding: 10, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        if chat.messages.isEmpty { suggestions }
                        ForEach(chat.messages) { m in bubble(m).id(m.id) }
                        if chat.busy {
                            HStack(spacing: 6) { ProgressView().controlSize(.small).scaleEffect(0.7); Text(L.t("agent.working")).font(.system(size: 11.5)).foregroundStyle(Theme.text2) }.id("busy")
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: chat.messages.count) { _, _ in withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: chat.busy) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
        }.frame(maxHeight: .infinity)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t("agent.empty")).font(.system(size: 12.5, weight: .semibold)).padding(.bottom, 2)
            ForEach(1 ... 4, id: \.self) { i in
                Button { chat.send(L.t("agent.sug.\(i)")) } label: {
                    Text(L.t("agent.sug.\(i)")).font(.system(size: 11.5)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 7)
                        .foregroundStyle(Theme.text).background(Theme.ctl, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
                }.buttonStyle(.plain).disabled(chat.busy)
            }
        }
    }

    @ViewBuilder private func bubble(_ m: ChatMessage) -> some View {
        switch m.role {
        case .user:
            HStack(spacing: 0) {
                Spacer(minLength: 28)
                Text(m.text).font(.system(size: 12.5)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.vertical, 7).background(Theme.ctl, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        case .assistant:
            Text(Self.markdown(m.text)).font(.system(size: 12.5)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        case .tool:
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: m.done ? (m.failed ? "xmark.circle" : "checkmark.circle") : "circle.dotted").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(m.failed ? Theme.warn : Theme.text2)
                Text(m.text).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.text2).lineLimit(2).truncationMode(.middle)
            }
        case .note:
            Text(m.text).font(.system(size: 11.5)).foregroundStyle(m.failed ? Theme.warn : Theme.text2).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(L.t("agent.placeholder"), text: $input, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 12.5)).lineLimit(1 ... 5)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Theme.ctl, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
                .onSubmit(submit)
            Button(action: { chat.busy ? chat.stop() : submit() }) {
                Image(systemName: chat.busy ? "stop.fill" : "arrow.up").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.onAccent).frame(width: 34, height: 34)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
            }.buttonStyle(.plain).help(L.t(chat.busy ? "agent.stop" : "agent.send"))
                .opacity(chat.busy || !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1 : 0.4)
        }
    }

    private func submit() {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !chat.busy else { return }
        input = ""; chat.send(t)
    }

    static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
