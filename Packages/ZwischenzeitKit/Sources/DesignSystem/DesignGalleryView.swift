import SwiftUI

/// Every primitive in every state, with fake data. Open it as an Xcode preview,
/// or render it to PNG with `swift run DesignGallery`.
public struct DesignGalleryView: View {
    public init() {}

    static let cards: [EventCardModel] = [
        .init(id: "1", time: "08:40", title: "Muster, Erika", session: "6/6", treatment: "Krankengymnastik", style: .kg, status: .arrived, isSeries: true, room: "Raum 2", isLastSession: true, isPast: true),
        .init(id: "2", time: "09:40", title: "Beispiel, Max", session: "9/10", treatment: "Lymphdrainage Teil 30 Minuten", note: "MLD 30 durchgeführt", style: .mld, status: .arrived),
        .init(id: "3", time: "12:50", title: "Test, Paula", session: "1/10", treatment: "Lymphdrainage Groß 45 Minuten", style: .mldLong),
        .init(id: "4", time: "11:00", title: "Probe, Jan", session: "4/6", treatment: "KG-Gerät", note: "Geräteplan", shortCode: "KGG", style: .device),
        .init(id: "5", time: "11:30", title: "Demo, Cem", session: "5/6", treatment: "Wärmetherapie/Heißluft", style: .heat, status: .arrived),
        .init(id: "6", time: "08:50", title: "Fiktiv, Lea", session: "3/6", treatment: "Kälte", style: .cold),
        .init(id: "7", time: "11:10", title: "Platzhalter, Tom", session: "1/3", treatment: "Massage", style: .other),
        .init(id: "8", time: "10:00", title: "Freie Zeit", treatment: "Teambesprechung", style: .blocker),
        .init(id: "9", time: "08:50", title: "Absage, Kim", session: "3/6", treatment: "Krankengymnastik", style: .kg, status: .cancelled),
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s24) {
            section("Week strip, badges, progress") {
                HStack(alignment: .top, spacing: DS.Space.s24) {
                    HStack(spacing: DS.Space.s4) {
                        DSDayPill(weekday: "Mo", day: "12", isSelected: false, isToday: false, hasAppointments: true, accessibilityText: "") {}
                        DSDayPill(weekday: "Di", day: "13", isSelected: false, isToday: false, hasAppointments: false, accessibilityText: "") {}
                        DSDayPill(weekday: "Mi", day: "14", isSelected: false, isToday: true, hasAppointments: true, accessibilityText: "") {}
                        DSDayPill(weekday: "Do", day: "15", isSelected: true, isToday: false, hasAppointments: true, accessibilityText: "") {}
                        DSDayPill(weekday: "Fr", day: "16", isSelected: false, isToday: false, hasAppointments: true, accessibilityText: "") {}
                    }
                    .frame(width: 320)
                    VStack(alignment: .leading, spacing: DS.Space.s8) {
                        HStack(spacing: DS.Space.s4) {
                            DSBadge("Raum 2", systemImage: "door.left.hand.open")
                            DSBadge("6/6")
                            DSBadge("Letzte", systemImage: "flag.checkered", tone: .warning)
                            DSBadge("Erste", systemImage: "sparkles", tone: .accent)
                            DSBadge("Abgesagt", systemImage: "xmark", tone: .danger)
                        }
                        HStack(spacing: DS.Space.s8) {
                            DSCheckInBadge(.waiting)
                            DSCheckInBadge(.arrived)
                            DSCheckInBadge(.overdue)
                        }
                        DSProgressSegments(current: 4, total: 10).frame(width: 260)
                        DSProgressSegments(current: 6, total: 6, tint: DS.Color.warning).frame(width: 260)
                        ZStack { DS.Color.unavailable; DSHatch(color: DS.Color.gridLineStrong, spacing: 10, lineWidth: 1).opacity(0.5) }
                            .frame(width: 260, height: 28)
                    }
                }
            }
            section("Event cards — full") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: DS.Space.s8)], spacing: DS.Space.s8) {
                    ForEach(Self.cards) { EventCard($0).frame(height: 58) }
                }
            }
            section("Event cards — compact") {
                HStack(spacing: DS.Layout.eventGap) {
                    EventCard(Self.cards[3], density: .compact).frame(width: 90, height: 24)
                    EventCard(Self.cards[0], density: .compact).frame(width: 160, height: 24)
                    EventCard(Self.cards[1], density: .compact).frame(width: 300, height: 24)
                }
            }
            section("Month chips") {
                VStack(spacing: DS.Space.s2) {
                    MonthChip(time: "07:00", treatment: "Lymphdrainage Teil 30 Minuten", style: .mld)
                    MonthChip(time: "08:00", treatment: "Krankengymnastik", style: .kg)
                    MonthChip(time: "11:00", treatment: "KG-Gerät", style: .device)
                    MonthChip(time: "14:40", treatment: "Wärmetherapie/Heißluft", style: .heat)
                }
                .frame(width: 220)
            }
            section("Buttons") {
                HStack(spacing: DS.Space.s8) {
                    DSButton("Anmelden") {}
                    DSButton("Erneut", variant: .plain) {}
                }
            }
            section("Status, banners, empty") {
                HStack(alignment: .top, spacing: DS.Space.s16) {
                    VStack(alignment: .leading, spacing: DS.Space.s8) {
                        HStack { DSStatusPill(.open); DSStatusPill(.completed); DSStatusPill(.cancelled) }
                        DSBanner("Serverfehler (500). Bitte später erneut versuchen.", kind: .error)
                        DSBanner("Keine Verbindung. Angezeigt wird der letzte Stand.", kind: .offline)
                    }
                    .frame(width: 360)
                    DSEmptyState().frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
        .padding(DS.Space.s24)
        .frame(width: 900, alignment: .topLeading)
        .background(DS.Color.bg)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            Text(title).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(DS.Color.textMuted)
            content()
        }
    }
}

// PreviewProvider instead of #Preview: the macro plugin only ships with Xcode,
// and this package must also build with the command line tools.
struct DesignGalleryView_Previews: PreviewProvider {
    static var previews: some View {
        DesignGalleryView().previewDisplayName("Light")
        DesignGalleryView().preferredColorScheme(.dark).previewDisplayName("Dark")
    }
}
