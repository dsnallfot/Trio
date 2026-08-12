import SwiftUI

struct LoopStatusView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var state: Home.StateModel

    @State private var sheetContentHeight = CGFloat.zero
    // Help Sheet
    @State var isHelpSheetPresented: Bool = false
    @State var helpSheetDetent = PresentationDetent.fraction(0.9)

    @State private var statusTitle: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Senaste Loop").bold()

                        Text(statusTitle)
                            .font(.headline)
                            .bold()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundColor(statusBadgeTextColor)
                            .background(statusBadgeColor)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Button(
                        action: {
                            isHelpSheetPresented.toggle()
                        },
                        label: {
                            Image(systemName: "questionmark.circle")
                        }
                    )
                }.padding(.top, 20)
//                Text("Current Loop Status").bold().padding(.top, 20)
//
//                Text(statusTitle)
//                    .font(.headline)
//                    .bold()
//                    .padding(.horizontal, 12)
//                    .padding(.vertical, 6)
//                    .foregroundColor(statusBadgeTextColor)
//                    .background(statusBadgeColor)
//                    .clipShape(Capsule())

                if let errorMessage = state.errorMessage, let date = state.errorDate {
                    Group {
                        Text("Fel vid senaste loop \(Formatter.dateFormatter.string(from: date))").font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(errorMessage).font(.caption).fixedSize(horizontal: false, vertical: true)
                    }.foregroundColor(.loopRed)
                }

                if let determination = state.determinationsFromPersistence.first {
                    if determination.glucose == 400 {
                        Text("Ogiltigt CGM-värde (HÖG).")
                            .bold()
                            .padding(.top)
                            .foregroundStyle(Color.loopRed)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("SMB och Temp basal inaktiverade.")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)

                    } else {
                        Text("Senaste beräkningar")
                            .bold()
                            .padding(.top)

                        Text(
                            "Trio använder dessa värden som beräknats av oref algoritmen:"
                        )
                        .font(.subheadline)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                        let tags = !state.isSmoothingEnabled ? determination.reasonParts : determination
                            .reasonParts + ["Smoothing: On"]
                        TagCloudView(
                            tags: tags,
                            shouldParseToMmolL: state.units == .mmolL
                        )

                        Text("Algoritmens slutsats").bold().padding(.top)

                        Text(
                            self
                                .parseReasonConclusion(
                                    determination.reasonConclusion,
                                    isMmolL: state.units == .mmolL
                                )
                        )
                        .font(.subheadline)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Ingen aktuell oref algoritm slutsats.")
                }

                Spacer()

                Button {
                    state.isLoopStatusPresented.toggle()
                } label: {
                    Text("Got it!").bold().frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
                }
                .buttonStyle(.bordered)
                .padding(.top)
            }
            .padding(.vertical)
            .padding(.horizontal, 20)
            .ignoresSafeArea(edges: .top)
            .background {
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ContentSizeKey.self, value: geo.size)
                }
            }
            .onAppear {
                setStatusTitle()
            }
            .sheet(isPresented: $isHelpSheetPresented) {
                LoopStatusHelpView(state: state, helpSheetDetent: $helpSheetDetent, isHelpSheetPresented: $isHelpSheetPresented)
            }
        }
        .presentationDetents([sheetContentHeight > 0 ? .height(sheetContentHeight) : .fraction(0.9), .large])
        .presentationDragIndicator(.visible)
        .onPreferenceChange(ContentSizeKey.self) { newSize in
            sheetContentHeight = newSize.height
        }
        .background(appState.trioBackgroundColor(for: colorScheme))
        .scrollContentBackground(.hidden)
    }

    private var statusBadgeColor: Color {
        guard let determination = state.determinationsFromPersistence.first, determination.timestamp != nil
        else {
            // previously the .timestamp property was used here because this only gets updated when the reportenacted function in the aps manager gets called
            return .secondary
        }

        let delta = state.timerDate.timeIntervalSince(state.lastLoopDate) - 30

        if delta <= 5.minutes.timeInterval {
            guard determination.timestamp != nil else {
                return .loopYellow
            }
            return .loopGreen
        } else if delta <= 10.minutes.timeInterval {
            return .loopYellow
        } else {
            return .loopRed
        }
    }

    private var statusBadgeTextColor: Color {
        if statusBadgeColor == .secondary {
            .black
        } else {
            colorScheme == .dark ? Color(red: 25.0 / 255.0, green: 39.0 / 255.0, blue: 53.0 / 255.0, opacity: 1.0) : .white
        }
    }

    private func setStatusTitle() {
        if let determination = state.determinationsFromPersistence.first {
            statusTitle =
                "Utförd \(Formatter.dateFormatter.string(from: determination.deliverAt ?? Date()))"
        } else {
            statusTitle = "Ej utförd."
        }
    }

    // TODO: Consolidate all mmol parsing methods (in TagCloudView, NightscoutManager and HomeRootView) to one central func
    private func parseReasonConclusion(_ reasonConclusion: String, isMmolL: Bool) -> String {
        // Normalize HTML entities to standard comparison symbols
        let normalizedReason = reasonConclusion
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        let patterns = [
            "minGuardBG\\s*-?\\d+\\.?\\d*<-?\\d+\\.?\\d*", // minGuardBG x<y
            "Eventual BG\\s*-?\\d+\\.?\\d*\\s*≥\\s*-?\\d+\\.?\\d*", // Eventual BG x ≥ target
            "Eventual BG\\s*-?\\d+\\.?\\d*\\s*<\\s*-?\\d+\\.?\\d*", // Eventual BG x < target
            "(\\S+)\\s+(-?\\d+\\.?\\d*)\\s*>\\s*(\\d+)%\\s+of\\s+BG\\s+(-?\\d+\\.?\\d*)", // maxDelta x > y% of BG z
            "Eventual BG\\s*-?\\d+\\.?\\d*\\s*>&\\s*-?\\d+\\.?\\d*\\s*but\\s*Min\\.\\s*Delta\\s*-?\\d+\\.?\\d*\\s*<\\s*Exp\\.\\s*Delta\\s*-?\\d+\\.?\\d*",
            // Eventual BG X > Y but Min. Delta A < Exp. Delta B
            "-?\\d+\\.?\\d*-\\d+\\.?\\d* in range" // New pattern: "105-80 in range"
        ]
        let pattern = patterns.joined(separator: "|")
        let regex = try! NSRegularExpression(pattern: pattern)

        func convertToMmolL(_ value: String) -> String {
            if let glucoseValue = Double(value.replacingOccurrences(of: "[^\\d.-]", with: "", options: .regularExpression)) {
                let mmolValue = Decimal(glucoseValue).asMmolL
                return mmolValue.description
            }
            return value
        }

        let matches = regex.matches(
            in: normalizedReason,
            range: NSRange(normalizedReason.startIndex..., in: normalizedReason)
        )
        var updatedConclusion = normalizedReason

        for match in matches.reversed() {
            guard let range = Range(match.range, in: normalizedReason) else { continue }
            let matchedString = String(normalizedReason[range])

            if isMmolL {
                if matchedString.contains(" in range") {
                    // Handle "105-80 in range: no temp required"
                    let values = matchedString.components(separatedBy: "-")
                    if values.count == 2 {
                        let firstValue = values[0].trimmingCharacters(in: .whitespaces)
                        let secondPart = values[1].components(separatedBy: " in range")[0]
                            .trimmingCharacters(in: .whitespaces)
                        let formattedFirstValue = convertToMmolL(firstValue)
                        let formattedSecondValue = convertToMmolL(secondPart)
                        let formattedString = "\(formattedFirstValue)-\(formattedSecondValue) in range"
                        updatedConclusion.replaceSubrange(range, with: formattedString)
                    }
                } else if matchedString.contains("Eventual BG"), matchedString.contains(">"),
                          matchedString.contains("but Min. Delta")
                {
                    // Handle "Eventual BG X > Y but Min. Delta A < Exp. Delta B"
                    let regexSubPattern =
                        "Eventual BG\\s*(-?\\d+\\.?\\d*)\\s*>&\\s*(-?\\d+\\.?\\d*)\\s*but\\s*Min\\.\\s*Delta\\s*(-?\\d+\\.?\\d*)\\s*<\\s*Exp\\.\\s*Delta\\s*(-?\\d+\\.?\\d*)"
                    let subRegex = try! NSRegularExpression(pattern: regexSubPattern)

                    if let subMatch = subRegex.firstMatch(
                        in: matchedString,
                        range: NSRange(matchedString.startIndex..., in: matchedString)
                    ) {
                        let bg1 = String(matchedString[Range(subMatch.range(at: 1), in: matchedString)!])
                        let bg2 = String(matchedString[Range(subMatch.range(at: 2), in: matchedString)!])
                        let minDelta = String(matchedString[Range(subMatch.range(at: 3), in: matchedString)!])
                        let expDelta = String(matchedString[Range(subMatch.range(at: 4), in: matchedString)!])

                        let formattedBG1 = convertToMmolL(bg1)
                        let formattedBG2 = convertToMmolL(bg2)
                        let formattedMinDelta = convertToMmolL(minDelta)
                        let formattedExpDelta = convertToMmolL(expDelta)

                        let formattedString =
                            "Prognos BG: \(formattedBG1)>\(formattedBG2) min min. Delta \(formattedMinDelta)<exp. Delta \(formattedExpDelta)"
                        updatedConclusion.replaceSubrange(range, with: formattedString)
                    }
                } else if matchedString.contains("<"), matchedString.contains("Eventual BG"), !matchedString.contains("=") {
                    // Handle "Eventual BG x < target" pattern
                    let parts = matchedString.components(separatedBy: "<")
                    if parts.count == 2 {
                        let bgPart = parts[0].replacingOccurrences(of: "Eventual BG", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        let targetValue = parts[1].trimmingCharacters(in: .whitespaces)
                        let formattedBGPart = convertToMmolL(bgPart)
                        let formattedTargetValue = convertToMmolL(targetValue)
                        let formattedString = "Prognos BG: \(formattedBGPart)<\(formattedTargetValue)"
                        updatedConclusion.replaceSubrange(range, with: formattedString)
                    }
                } else if matchedString.contains("<"), matchedString.contains("minGuardBG") {
                    // Handle "minGuardBG x<y" pattern
                    let parts = matchedString.components(separatedBy: "<")
                    if parts.count == 2 {
                        let firstValue = parts[0].trimmingCharacters(in: .whitespaces)
                        let secondValue = parts[1].trimmingCharacters(in: .whitespaces)
                        let formattedFirstValue = convertToMmolL(firstValue)
                        let formattedSecondValue = convertToMmolL(secondValue)
                        let formattedString = "minGuardBG \(formattedFirstValue)<\(formattedSecondValue)"
                        updatedConclusion.replaceSubrange(range, with: formattedString)
                    }
                } else if matchedString.contains("≥") {
                    // Handle "Eventual BG X ≥ Y"
                    let eventBGPattern = "Eventual BG\\s*(-?\\d+\\.?\\d*)\\s*≥\\s*(-?\\d+\\.?\\d*)"

                    let eventBGRegex = try! NSRegularExpression(pattern: eventBGPattern)
                    if let eventBGMatch = eventBGRegex.firstMatch(
                        in: matchedString,
                        range: NSRange(matchedString.startIndex..., in: matchedString)
                    ) {
                        let bgValue = String(matchedString[Range(eventBGMatch.range(at: 1), in: matchedString)!])
                        let targetValue = String(matchedString[Range(eventBGMatch.range(at: 2), in: matchedString)!])

                        let formattedBG = convertToMmolL(bgValue)
                        let formattedTarget = convertToMmolL(targetValue)

                        let formattedString = "Prognos BG: \(formattedBG)≥\(formattedTarget)"
                        updatedConclusion.replaceSubrange(range, with: formattedString)
                    }
                } else if let localMatch = regex.firstMatch(
                    in: matchedString,
                    range: NSRange(matchedString.startIndex..., in: matchedString)
                ) {
                    // Handle "maxDelta 37 > 20% of BG 95" style
                    if match.numberOfRanges == 5 {
                        let metric = String(matchedString[Range(localMatch.range(at: 1), in: matchedString)!])
                        let firstValue = String(matchedString[Range(localMatch.range(at: 2), in: matchedString)!])
                        let percentage = String(matchedString[Range(localMatch.range(at: 3), in: matchedString)!])
                        let bgValue = String(matchedString[Range(localMatch.range(at: 4), in: matchedString)!])

                        let formattedFirstValue = convertToMmolL(firstValue)
                        let formattedBGValue = convertToMmolL(bgValue)

                        let formattedString = "\(metric) \(formattedFirstValue)>\(percentage)% av BG \(formattedBGValue)"
                        updatedConclusion.replaceSubrange(range, with: formattedString)
                    }
                }
            } else {
                // When isMmolL is false, ensure the original value is retained without duplication
                updatedConclusion.replaceSubrange(range, with: matchedString)
            }
        }

        return updatedConclusion.capitalizingFirstLetter()
    }
}

struct ContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        // If multiple views report sizes, pick whichever logic you prefer:
        // - The largest height
        // - The sum
        // For a single child, just use nextValue() directly if you like.
        let next = nextValue()
        if next.height > value.height {
            value = next
        }
    }
}
