import SwiftUI
import UIKit
import SwiftData
import Charts
import PhotosUI
import LocalAuthentication
import LifeResetCore

/// Peso (gráfico e tendência), medidas corporais e fotos de progresso privadas.
struct BodyView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var measures: [BodyMeasurement]
    @State private var newKg = ""
    @State private var measureKind = "Braço"
    @State private var measureCm = ""

    static let kinds = ["Braço", "Peito", "Cintura", "Ombros", "Coxa", "Antebraço", "Pescoço"]

    var body: some View {
        let store = DataStore(ctx: ctx)
        let p = store.profile()
        let values = weights.map(\.kg)
        let avg = WeightMath.movingAverage(values)
        let trend = WeightMath.weeklyTrend(weights.map { ($0.date, $0.kg) })
        return List {
            Section {
                if weights.count >= 2 {
                    Chart {
                        ForEach(Array(weights.enumerated()), id: \.offset) { i, w in
                            PointMark(x: .value("Data", w.date), y: .value("kg", w.kg)).foregroundStyle(Theme.textTertiary).symbolSize(20)
                            LineMark(x: .value("Data", w.date), y: .value("Média", avg[i])).foregroundStyle(Theme.accent)
                        }
                        RuleMark(y: .value("Meta", p.targetWeightKg)).foregroundStyle(Theme.positive.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 180)
                }
                if let last = weights.last {
                    KeyValueRow(key: "Atual", value: "\(Fmt.number(last.kg, decimals: 1)) kg")
                    KeyValueRow(key: "Meta", value: "\(Fmt.number(p.targetWeightKg, decimals: 1)) kg (faltam \(Fmt.number(max(0, p.targetWeightKg - last.kg), decimals: 1)))")
                }
                if let t = trend { KeyValueRow(key: "Tendência", value: "\(t >= 0 ? "+" : "")\(Fmt.number(t, decimals: 2)) kg/semana") }
                HStack {
                    TextField("Peso de hoje (kg)", text: $newKg).keyboardType(.decimalPad)
                    Button("Registar") {
                        if let v = Double(newKg.replacingOccurrences(of: ",", with: ".")), v > 20, v < 300 {
                            ctx.insert(WeightEntry(date: Date(), kg: v))
                            Progression(store: store).award(5, area: .health, source: "Registo de peso", key: "weight:\(LRCalendar.dayKey(Date()))")
                            store.save(); newKg = ""
                        }
                    }
                }
            } header: { Text("Peso") }

            Section("Medidas") {
                Picker("Medida", selection: $measureKind) { ForEach(Self.kinds, id: \.self) { Text($0) } }
                HStack {
                    TextField("cm", text: $measureCm).keyboardType(.decimalPad)
                    Button("Registar") {
                        if let v = Double(measureCm.replacingOccurrences(of: ",", with: ".")), v > 0 {
                            ctx.insert(BodyMeasurement(date: Date(), kind: measureKind, cm: v)); store.save(); measureCm = ""
                        }
                    }
                }
                ForEach(Self.kinds, id: \.self) { k in
                    let list = measures.filter { $0.kind == k }
                    if let last = list.first {
                        let diff = list.count > 1 ? last.cm - list[list.count - 1].cm : 0
                        KeyValueRow(key: k, value: "\(Fmt.number(last.cm, decimals: 1)) cm\(list.count > 1 ? " (\(diff >= 0 ? "+" : "")\(Fmt.number(diff, decimals: 1)))" : "")")
                    }
                }
            }

            Section("Histórico de peso") {
                ForEach(weights.reversed()) { w in
                    KeyValueRow(key: Fmt.shortDate(w.date), value: "\(Fmt.number(w.kg, decimals: 1)) kg")
                }
                .onDelete { idx in let r = Array(weights.reversed()); for i in idx { ctx.delete(r[i]) }; store.save() }
            }

            Section {
                NavigationLink("Fotos de progresso") { ProgressPhotosView() }
            } footer: { Text("As fotos ficam só no iPhone, protegidas por Face ID/código.") }
        }
        .scrollContentBackground(.hidden).lrScreenBackground()
        .navigationTitle("Peso e corpo")
    }
}

/// Fotos guardadas na pasta privada da app (proteção de ficheiros completa), atrás de Face ID.
struct ProgressPhotosView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
    @State private var unlocked = false
    @State private var picked: PhotosPickerItem?
    @State private var viewing: ProgressPhoto?

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    var body: some View {
        Group {
            if unlocked {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], spacing: 6) {
                        ForEach(photos) { p in
                            if let img = UIImage(contentsOfFile: Self.folder.appendingPathComponent(p.fileName).path) {
                                Image(uiImage: img).resizable().scaledToFill().frame(height: 140).clipped()
                                    .overlay(alignment: .bottomLeading) {
                                        Text(Fmt.shortDate(p.date)).font(.lrCaption).padding(4).background(.black.opacity(0.5))
                                    }
                                    .onTapGesture { viewing = p }
                            }
                        }
                    }.padding(Theme.pagePadding)
                }
            } else {
                ContentUnavailableView {
                    Label("Fotos protegidas", systemImage: "lock")
                } actions: {
                    Button("Desbloquear") { unlock() }.buttonStyle(.borderedProminent)
                }
            }
        }
        .lrScreenBackground()
        .navigationTitle("Fotos de progresso")
        .toolbar {
            if unlocked {
                PhotosPicker(selection: $picked, matching: .images) { Image(systemName: "plus") }
            }
        }
        .onAppear(perform: unlock)
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data), let jpg = img.jpegData(compressionQuality: 0.8) {
                    let name = UUID().uuidString + ".jpg"
                    try? jpg.write(to: Self.folder.appendingPathComponent(name), options: [.completeFileProtection])
                    ctx.insert(ProgressPhoto(date: Date(), fileName: name))
                    DataStore(ctx: ctx).save()
                }
                picked = nil
            }
        }
        .sheet(item: $viewing) { p in
            NavigationStack {
                VStack {
                    if let img = UIImage(contentsOfFile: Self.folder.appendingPathComponent(p.fileName).path) {
                        Image(uiImage: img).resizable().scaledToFit()
                    }
                    Text(Fmt.longDate(p.date)).font(.lrCaption)
                }
                .lrScreenBackground()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Fechar") { viewing = nil } }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Apagar", role: .destructive) {
                            try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(p.fileName))
                            ctx.delete(p); DataStore(ctx: ctx).save(); viewing = nil
                        }
                    }
                }
            }
        }
    }

    private func unlock() {
        guard !unlocked else { return }
        let la = LAContext()
        var err: NSError?
        guard la.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { unlocked = true; return }
        la.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Ver as fotos de progresso") { ok, _ in
            DispatchQueue.main.async { if ok { unlocked = true } }
        }
    }
}
