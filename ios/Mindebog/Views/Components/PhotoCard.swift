import SwiftUI

/// Billedkort (#46): billedet fylder hele kortet, og titel, dato og "+N" ligger oven på i bunden
/// med et blødt fald, så teksten altid kan læses. Uden billede bliver det et almindeligt cream-kort.
///
///   PhotoCard(photos: highlight.photos, title: highlight.text, subtitle: Fmt.long(date),
///             zoomId: id, zoomNamespace: ns, onOpen: { lightbox = $0 }) {
///       mediaButtons(highlight)      // valgfrit indhold under billedet (sted, knapper, kommentarer)
///   }
struct PhotoCard<Extra: View>: View {
    let photos: PhotoSet
    let title: String
    var subtitle: String? = nil
    /// Hvem det handler om, fx "William · Nohr". Vises under datoen.
    var about: String? = nil
    /// nil = billedets egen form, dog aldrig højere end 4:5 (stående), så et foto ikke fylder hele skærmen.
    /// Oversigter (Hjem) giver 4:3, så der er flere kort på skærmen ad gangen; billedet beskæres, fuld størrelse ved tryk.
    var aspect: CGFloat? = nil
    var zoomId: String? = nil
    var zoomNamespace: Namespace.ID? = nil
    /// Sat = vis en "Redigér"-knap på kortet (og i menuen ved langt tryk). nil = kun visning.
    var onEdit: (() -> Void)? = nil
    let onOpen: (LightboxState) -> Void
    @ViewBuilder var extra: () -> Extra

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let cover = photos.coverPhoto {
                picture(cover)
            } else {
                HStack(alignment: .top) {
                    header(onPhoto: false)
                    Spacer(minLength: 8)
                    editButton(onPhoto: false)
                }
                .padding(14)
            }
            extra()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous).stroke(Theme.sep))
        .contextMenu {
            if let onEdit { Button(action: onEdit) { Label("Redigér", systemImage: "pencil") } }
        }
    }

    /// Lille rund knap: oven på billedet (øverst til venstre, så "+N" har højre hjørne) eller i titelrækken.
    @ViewBuilder
    private func editButton(onPhoto: Bool) -> some View {
        if let onEdit {
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(onPhoto ? Color.white : Theme.muted)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(onPhoto ? Color.black.opacity(0.45) : Theme.bgDark))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Redigér")
        }
    }

    private func picture(_ cover: Data) -> some View {
        Color.clear
            .aspectRatio(aspect ?? ImageTools.displayAspect(cover).clamped(min: 0.8, max: 1.6), contentMode: .fit)
            .overlay { DataImage(data: cover) }
            .modifier(OptionalZoomSource(id: zoomId, namespace: zoomNamespace))
            .overlay(alignment: .bottom) {
                header(onPhoto: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(scrim)
            }
            .overlay(alignment: .topLeading) { editButton(onPhoto: true).padding(10) }
            .overlay(alignment: .topTrailing) {
                if photos.count > 1 {
                    Text("+\(photos.count - 1)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.5)))
                        .padding(10)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { onOpen(LightboxState.coverFirst(photos, sourceId: zoomId)) }
    }

    /// Titel og dato — hvid oven på billedet, appens egne farver på cream-kortet.
    private func header(onPhoto: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let subtitle {
                Text(subtitle).font(.caption.weight(.medium))
                    .foregroundStyle(onPhoto ? .white.opacity(0.85) : Theme.muted)
            }
            Text(title).font(.serifTitle(onPhoto ? 20 : 17))
                .foregroundStyle(onPhoto ? .white : Theme.text)
                .lineLimit(3)
            if let about {
                Text(about).font(.caption)
                    .foregroundStyle(onPhoto ? .white.opacity(0.85) : Theme.muted)
            }
        }
        .shadow(color: onPhoto ? .black.opacity(0.35) : .clear, radius: 2, y: 1)
    }

    /// Blødt fald fra gennemsigtig til mørk — tre trin, så det ikke ser ud som en stribe.
    private var scrim: some View {
        LinearGradient(stops: [.init(color: .clear, location: 0),
                               .init(color: .black.opacity(0.35), location: 0.45),
                               .init(color: .black.opacity(reduceTransparency ? 0.85 : 0.7), location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .padding(.top, -40)   // faldet begynder lidt over teksten
    }
}

extension PhotoCard where Extra == EmptyView {
    init(photos: PhotoSet, title: String, subtitle: String? = nil, about: String? = nil, aspect: CGFloat? = nil,
         zoomId: String? = nil, zoomNamespace: Namespace.ID? = nil, onEdit: (() -> Void)? = nil,
         onOpen: @escaping (LightboxState) -> Void) {
        self.init(photos: photos, title: title, subtitle: subtitle, about: about, aspect: aspect,
                  zoomId: zoomId, zoomNamespace: zoomNamespace, onEdit: onEdit, onOpen: onOpen) { EmptyView() }
    }
}

private extension CGFloat {
    func clamped(min lower: CGFloat, max upper: CGFloat) -> CGFloat { Swift.min(Swift.max(self, lower), upper) }
}
