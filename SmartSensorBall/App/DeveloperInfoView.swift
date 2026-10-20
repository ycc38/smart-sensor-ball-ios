import SwiftUI

/// "About Us" page with the developer details, matching the Android developer info dialog.
struct DeveloperInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let language: AppLanguage
    @State private var showingLegal: LegalDocument?

    private static let email = "zclei@vip.sina.com"
    private static let emailSubject = "Smart sensor ball APP咨询"

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(language.localized(
                        "开发者信息、联系邮箱及平台协议入口",
                        "Developer details, contact email and policy links",
                        fr: "Informations développeur, e-mail et accès aux politiques",
                        th: "ข้อมูลผู้พัฒนา อีเมลติดต่อ และลิงก์นโยบาย"
                    ))
                    .font(.callout)
                    .foregroundStyle(Color(hex: "FFD88A"))
                    .fixedSize(horizontal: false, vertical: true)

                    sectionLabel(language.localized("公司信息", "Company", fr: "Entreprise", th: "ข้อมูลบริษัท"))
                    infoCard {
                        Text(companyName)
                            .font(.title3.bold())
                            .foregroundStyle(Color(hex: "FFF8E8"))
                        Text(language.localized(
                            "专注于智能拳击产品与运动数据体验",
                            "Focused on smart sensor ball products and sports data experiences",
                            fr: "Spécialisée dans les produits de balle à capteurs intelligents et l'expérience des données sportives",
                            th: "มุ่งเน้นผลิตภัณฑ์ลูกบอลเซ็นเซอร์อัจฉริยะและประสบการณ์ข้อมูลการกีฬา"
                        ))
                        .font(.callout)
                        .foregroundStyle(Color(hex: "FFD88A"))
                    }

                    sectionLabel(language.localized("联系方式", "Contact", fr: "Contact", th: "ช่องทางติดต่อ"))
                    infoCard {
                        Text(language.localized("邮箱", "Email", fr: "E-mail", th: "อีเมล"))
                            .font(.subheadline.bold())
                            .foregroundStyle(Color(hex: "B88A54"))
                        Text(Self.email)
                            .font(.title3.bold())
                            .foregroundStyle(Color(hex: "FFB347"))
                            .textSelection(.enabled)
                        Button(language.localized("发送邮件", "Send Email", fr: "Envoyer un e-mail", th: "ส่งอีเมล")) {
                            openDeveloperEmail()
                        }
                        .buttonStyle(DeveloperInfoButtonStyle(color: Color(hex: "E07010"), fillsWidth: false))
                        .padding(.top, 4)
                    }

                    sectionLabel(language.localized("附加信息", "More Info", fr: "Informations", th: "ข้อมูลเพิ่มเติม"))
                    infoCard {
                        Text("\(language.localized("当前 APP 版本号", "App Version", fr: "Version de l'application", th: "เวอร์ชันแอป")): \(appVersionText)")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color(hex: "FFF0C9"))
                        Text(language.localized(
                            "可查看本应用当前版本对应的隐私政策与用户协议。",
                            "Review the privacy policy and user agreement for the current app version.",
                            fr: "Consultez la politique de confidentialité et l'accord utilisateur de cette version.",
                            th: "ดูนโยบายความเป็นส่วนตัวและข้อตกลงผู้ใช้ของแอปเวอร์ชันนี้"
                        ))
                        .font(.callout)
                        .foregroundStyle(Color(hex: "B88A54"))
                        Button(L10n.text("privacy_policy", language)) { showingLegal = .privacy }
                            .buttonStyle(DeveloperInfoButtonStyle(color: Color(hex: "16384A"), fillsWidth: true))
                            .padding(.top, 4)
                        Button(L10n.text("user_agreement", language)) { showingLegal = .agreement }
                            .buttonStyle(DeveloperInfoButtonStyle(color: Color(hex: "1F3B52"), fillsWidth: true))
                    }
                }
                .padding(18)
            }
            .background(Color(hex: "040C08").ignoresSafeArea())
            .navigationTitle(language.localized("关于我们", "About Us", fr: "À propos", th: "เกี่ยวกับเรา"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.text("done", language)) { dismiss() }
                }
            }
            .sheet(item: $showingLegal) { document in
                LegalDocumentView(document: document, language: language)
            }
        }
        .navigationViewStyle(.stack)
    }

    private var companyName: String {
        language.localized(
            "绍兴维脉科技有限公司",
            "Shaoxing Weimai Technology Co., Ltd.",
            fr: "Société Shaoxing Weimai Technology Co., Ltd.",
            th: "บริษัท Shaoxing Weimai Technology Co., Ltd."
        )
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "V\(version) (\(build))"
    }

    private func openDeveloperEmail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.email
        components.queryItems = [URLQueryItem(name: "subject", value: Self.emailSubject)]
        if let url = components.url {
            openURL(url)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.headline.weight(.black))
            .foregroundStyle(Color(hex: "FFF6E5"))
            .padding(.top, 4)
    }

    private func infoCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "0B1721"), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "20384A"), lineWidth: 1))
    }
}

private struct DeveloperInfoButtonStyle: ButtonStyle {
    let color: Color
    let fillsWidth: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(maxWidth: fillsWidth ? CGFloat.infinity : nil)
            .background(color.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 10))
    }
}
