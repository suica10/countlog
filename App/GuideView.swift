import SwiftUI

/// 撮影プロトコル（ガイド）タブ。
/// このアプリの目的は「数えること」ではなく「エビデンスを残すこと」。
struct GuideView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    purposeCard
                    rulesSection
                    flowSection
                }
                .padding()
            }
            .navigationTitle("ガイド")
        }
    }

    private var purposeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("このアプリの目的", systemImage: "doc.text")
                .font(.headline)
            Text("数量検査の目的は「数えること」ではなく、「エビデンスを残すこと」です。")
                .font(.title3)
                .fontWeight(.bold)
            Text("出荷した後になって「数が足りない」と言われたとき、言い争いを終わらせるのは記憶ではなく記録です。品物と伝票が一緒に写った写真、確認した個数、その日時。この3点が残っていれば、それが証拠になります。")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("撮影の決まりごと")
                .font(.headline)

            ruleRow(icon: "doc.text",
                    title: "出荷伝票・識別札を必ず一緒に写す",
                    detail: "数量検査の写真を撮るときは、出荷伝票や識別のための札を、必ず品物と同じ写真の中に写してください。札が写っていない写真は、後から見ても「何の・いつの出荷か」が分からず、証拠になりません。")
            ruleRow(icon: "rectangle.stack",
                    title: "品物は広げて一層にし、重ねない",
                    detail: "重なった物は人間にも正確に数えられません。品物は広げて一層に並べ、重ならない状態で撮ってください。")
            ruleRow(icon: "tag",
                    title: "1枚の写真に1品種だけ",
                    detail: "品種が混ざると、数える対象を取り違えます。品種ごとに分けて撮ってください。")
            ruleRow(icon: "sun.max",
                    title: "明るい場所で、真上から撮る",
                    detail: "暗い場所や斜めからの撮影は、影やゆがみで誤判定のもとになります。明るい場所で、できるだけ真上から撮ってください。")
            ruleRow(icon: "eye",
                    title: "機械の数値は下書き。必ず目視で確認する",
                    detail: "このアプリが出す個数は下書きです。マーカーを見て、漏れや数え過ぎを直し、必ず人が目視で確認してから「確定」してください。確定した人の確認こそが記録の価値です。")
        }
    }

    private var flowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("操作の流れ")
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                flowRow("1", "撮影タブで写真を撮る／選ぶ（伝票・札も一緒に）")
                flowRow("2", "数えたい品物を1つ、四角で囲む")
                flowRow("3", "「この対象で数える」を押す")
                flowRow("4", "マーカーを確認し、タップで追加・削除して直す")
                flowRow("5", "伝票番号をメモ欄に入れて「確定して保存」")
                flowRow("6", "記録は自動でサーバーにアップロードされる")
            }
            .font(.body)
        }
    }

    private func ruleRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func flowRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.subheadline)
                .fontWeight(.bold)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
        }
    }
}
