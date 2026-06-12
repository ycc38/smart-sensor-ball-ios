import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh"
    case english = "en"
    case french = "fr"
    case thai = "th"

    var id: String { rawValue }

    static var current: AppLanguage {
        let stored = UserDefaults.standard.string(forKey: "app_language")
        return AppLanguage(rawValue: stored ?? "") ?? .chinese
    }

    var displayName: String {
        switch self {
        case .chinese: return "简体中文"
        case .english: return "English"
        case .french: return "Français"
        case .thai: return "ไทย"
        }
    }

    var legalSuffix: String {
        switch self {
        case .chinese: return "zh"
        case .english: return "en"
        case .french: return "fr"
        case .thai: return "th"
        }
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: "app_language")
    }
}

enum L10n {
    static func text(_ key: String, _ language: AppLanguage) -> String {
        table[language]?[key] ?? table[.english]?[key] ?? key
    }

    private static let english: [String: String] = [
        "first_use_title": "Connect Bluetooth Device",
        "first_use_message": "Before your first session, open Settings to scan and connect your Smart sensor ball device.",
        "open_settings": "Open Settings",
        "later": "Later",
        "settings": "Settings",
        "settings_title": "Settings",
        "done": "Done",
        "save": "Save",
        "cancel": "Cancel",
        "refresh": "Refresh",

        "tab_training": "Training Center",
        "tab_achievements": "Training Results",
        "tab_leaderboard": "Rankings",
        "tab_profile": "Profile Center",

        "bluetooth_connection": "Bluetooth Connection",
        "bluetooth_hint": "Scan for a SENBALL# / FFE0 BLE device first. Training is available after connection.",
        "scan": "Scan",
        "connect": "Connect",
        "disconnect": "Disconnect",
        "no_devices": "No SENBALL# devices found",
        "bluetooth_disconnected": "Disconnected",
        "connect_first": "Connect the Bluetooth device first",
        "battery": "Battery",
        "punch_count": "Punch Count",
        "peak_force": "Peak",

        "activation_title": "Activation and Cloud Account",
        "activation_hint": "Enter the serial number and activation code that came with the physical Smart sensor ball hardware. Activation verifies hardware ownership and enables companion cloud features; no digital content is sold in the app.",
        "serial_placeholder": "Serial number",
        "code_placeholder": "Activation code",
        "activate": "Activate",
        "restore": "Restore",
        "activation_required": "Activate the app before training",
        "activation_input_required": "Enter serial and code.",
        "activation_success": "Activation complete.",
        "activation_failed": "Activation failed.",
        "activation_restored": "Activation restored.",
        "activation_restore_failed": "No activation found for this device.",
        "cloud_needs_activation": "Activate to sync cloud profile, history, badges, and leaderboard.",
        "cloud_ready": "Cloud profile loaded.",
        "cloud_failed": "Cloud request failed.",
        "cloud_synced": "Training synced.",

        "language": "App Language",
        "language_helper": "Choose the app and speech cue language.",
        "privacy_policy": "Privacy Policy",
        "user_agreement": "User Agreement",
        "document_unavailable": "This document is currently unavailable.",
        "developer_info": "Developer Info",
        "developer_info_hint": "Company, contact, version, and legal documents.",

        "cloud_sound_effects": "Cloud Sound Effects",
        "cloud_sound_effects_hint": "Preview and choose the punch sound played for training hits.",
        "refresh_effects": "Refresh Effects",
        "sound_effects_ready": "Sound effects ready.",

        "ready": "Ready to train",
        "countdown": "Starting soon",
        "running": "Training live",
        "complete": "Training complete",
        "stopped": "Training stopped",
        "start": "Start",
        "end": "End",
        "mode": "Mode",
        "target": "Target",
        "streak": "Streak",
        "hits_short": "hits",

        "mode_30": "30 sec",
        "mode_60": "60 sec",
        "mode_burst10": "10 sec",
        "mode_burst15": "15 sec",
        "play_classic30": "Classic 30s",
        "play_classic60": "Endurance 60s",
        "play_burst10": "Burst 10s",
        "play_burst15": "Burst 15s",
        "play_level": "Level Challenge",
        "play_daily": "Daily Challenge",
        "play_classic30_body": "Balanced 30-second reaction training.",
        "play_classic60_body": "One-minute endurance and pace control.",
        "play_burst10_body": "Short power burst. Hit the target fast.",
        "play_burst15_body": "Longer burst window for explosive rhythm.",
        "play_level_body": "Clear the current target to advance your level.",
        "play_daily_body": "A daily rotating goal built for consistency.",

        "report_waiting_title": "Waiting for your next session",
        "report_waiting_body": "Connect the ball, choose a mode, and finish training to generate a report.",
        "training_report": "Training Report",
        "total_hits": "Total Hits",
        "avg_freq": "Avg Frequency",
        "best_burst": "Best Burst",

        "current_tier": "Current Tier",
        "badges_unlocked": "badges unlocked",
        "share_achievements": "Share Badges",
        "leaderboard_title": "Leaderboard Arena",
        "leaderboard_best30": "Best 30s",
        "leaderboard_best60": "Best 60s",
        "leaderboard_total": "Total Hits",
        "leaderboard_streak": "Streak",
        "leaderboard_ready": "Leaderboard loaded.",
        "leaderboard_empty_title": "Waiting for your first ranking",
        "leaderboard_empty": "Upload a training record to join the leaderboard.",
        "leaderboard_me": "Me",
        "share_leaderboard": "Share Ranking",
        "leaderboard_consent_title": "Share training data?",
        "leaderboard_consent_message": "To sync training history, achievements, and rankings, this app will upload your training score, mode, nickname or masked device ID, tier, and app/device service identifiers to the Smart sensor ball cloud. Your rank and score may appear on the leaderboard. You can continue local training without uploading.",
        "leaderboard_consent_accept": "Agree and Upload",
        "leaderboard_consent_decline": "Not Now",
        "leaderboard_consent_declined_status": "Training kept locally. Cloud ranking upload was not enabled.",
        "leaderboard_upload_setting": "Cloud Ranking Upload",
        "leaderboard_upload_setting_hint": "Control whether future training scores are uploaded for cloud history, achievements, and leaderboards.",
        "leaderboard_upload_toggle": "Allow leaderboard and cloud training upload",
        "leaderboard_upload_enabled": "Enabled. Future completed training sessions may sync to the cloud and appear in rankings.",
        "leaderboard_upload_disabled": "Disabled. Future training sessions stay local until you enable upload.",
        "rank": "Rank",
        "score": "Score",

        "guest_trainer": "Guest Trainer",
        "not_activated": "Not activated",
        "edit_profile": "Edit Profile",
        "nickname": "Nickname",
        "profile_saved": "Profile saved.",
        "total_sessions": "Sessions",
        "best_30": "Best 30s",
        "history_title": "Recent History",
        "history_empty": "No cloud or local training history yet.",
        "share_training": "Share Training"
    ]

    private static let chinese: [String: String] = [
        "first_use_title": "连接蓝牙设备",
        "first_use_message": "首次使用前，请进入设置界面扫描并连接 Smart sensor ball 蓝牙设备。",
        "open_settings": "去设置",
        "later": "稍后",
        "settings": "设置",
        "settings_title": "设置",
        "done": "完成",
        "save": "保存",
        "cancel": "取消",
        "refresh": "刷新",

        "tab_training": "训练中心",
        "tab_achievements": "训练成果",
        "tab_leaderboard": "榜单排名",
        "tab_profile": "个人中心",

        "bluetooth_connection": "蓝牙连接",
        "bluetooth_hint": "请先扫描 SENBALL# / FFE0 设备，连接成功后即可开始训练。",
        "scan": "扫描",
        "connect": "连接",
        "disconnect": "断开",
        "no_devices": "未扫描到 SENBALL# 设备",
        "bluetooth_disconnected": "未连接",
        "connect_first": "请先连接蓝牙设备",
        "battery": "电量",
        "punch_count": "击打次数",
        "peak_force": "峰值",

        "activation_title": "激活与云端账号",
        "activation_hint": "请输入实体 Smart sensor ball 硬件随附的序列号和激活码。激活用于验证硬件使用资格并启用配套云端功能，App 内不销售数字内容。",
        "serial_placeholder": "设备序列号",
        "code_placeholder": "激活码",
        "activate": "激活",
        "restore": "恢复",
        "activation_required": "请先激活应用后再开始训练",
        "activation_input_required": "请输入序列号和激活码。",
        "activation_success": "激活成功。",
        "activation_failed": "激活失败。",
        "activation_restored": "已恢复激活。",
        "activation_restore_failed": "当前设备未找到激活记录。",
        "cloud_needs_activation": "激活后可同步云端资料、历史、徽章和排行。",
        "cloud_ready": "云端资料已加载。",
        "cloud_failed": "云端请求失败。",
        "cloud_synced": "训练已同步。",

        "language": "APP 语言",
        "language_helper": "选择界面和语音提示语言。",
        "privacy_policy": "隐私政策",
        "user_agreement": "用户协议",
        "document_unavailable": "当前文档暂不可用，请稍后重试。",
        "developer_info": "开发者信息",
        "developer_info_hint": "公司、联系方式、版本与法律文档。",

        "cloud_sound_effects": "云端音效",
        "cloud_sound_effects_hint": "试听并选择训练击打计数时播放的拳击音效。",
        "refresh_effects": "刷新音效",
        "sound_effects_ready": "音效已就绪。",

        "ready": "准备开始训练",
        "countdown": "即将开始",
        "running": "正在训练",
        "complete": "训练完成",
        "stopped": "训练已停止",
        "start": "开始",
        "end": "结束",
        "mode": "模式",
        "target": "目标",
        "streak": "连续训练",
        "hits_short": "击",

        "mode_30": "30 秒",
        "mode_60": "60 秒",
        "mode_burst10": "10 秒",
        "mode_burst15": "15 秒",
        "play_classic30": "经典30秒",
        "play_classic60": "60秒耐力",
        "play_burst10": "10秒爆发",
        "play_burst15": "15秒爆发",
        "play_level": "闯关挑战",
        "play_daily": "每日挑战",
        "play_classic30_body": "均衡的 30 秒反应训练。",
        "play_classic60_body": "一分钟耐力与节奏控制。",
        "play_burst10_body": "短时爆发，快速命中目标。",
        "play_burst15_body": "更长爆发窗口，训练连续节奏。",
        "play_level_body": "完成当前目标即可升级。",
        "play_daily_body": "每天变化的坚持训练目标。",

        "report_waiting_title": "等待下一次训练",
        "report_waiting_body": "连接拳击球、选择模式并完成训练后，会自动生成报告。",
        "training_report": "训练报告",
        "total_hits": "总击打",
        "avg_freq": "平均频率",
        "best_burst": "最佳爆发",

        "current_tier": "当前段位",
        "badges_unlocked": "枚徽章已解锁",
        "share_achievements": "分享徽章",
        "leaderboard_title": "排行榜竞技场",
        "leaderboard_best30": "30 秒最佳",
        "leaderboard_best60": "60 秒最佳",
        "leaderboard_total": "累计击打",
        "leaderboard_streak": "连续训练",
        "leaderboard_ready": "排行榜已加载。",
        "leaderboard_empty_title": "等待第一份排名",
        "leaderboard_empty": "上传训练记录后即可加入排行榜。",
        "leaderboard_me": "我的排名",
        "share_leaderboard": "分享排名",
        "leaderboard_consent_title": "是否上传训练数据？",
        "leaderboard_consent_message": "为同步训练记录、成就和排行榜，本 App 会将训练成绩、训练模式、昵称或脱敏设备 ID、段位以及必要的 App/设备服务标识上传至 Smart sensor ball 云端。您的排名和成绩可能展示在排行榜中。不同意也可以继续进行本地训练。",
        "leaderboard_consent_accept": "同意并上传",
        "leaderboard_consent_decline": "暂不上传",
        "leaderboard_consent_declined_status": "训练已保留在本机，未开启云端排行榜上传。",
        "leaderboard_upload_setting": "云端排行榜上传",
        "leaderboard_upload_setting_hint": "控制后续训练成绩是否上传用于云端历史、成就和排行榜。",
        "leaderboard_upload_toggle": "允许上传排行榜和云端训练数据",
        "leaderboard_upload_enabled": "已开启。后续完成的训练可能同步到云端并展示在排行榜中。",
        "leaderboard_upload_disabled": "已关闭。后续训练将保留在本机，直到你重新开启上传。",
        "rank": "排名",
        "score": "成绩",

        "guest_trainer": "访客训练者",
        "not_activated": "未激活",
        "edit_profile": "编辑资料",
        "nickname": "昵称",
        "profile_saved": "资料已保存。",
        "total_sessions": "训练次数",
        "best_30": "30 秒最佳",
        "history_title": "最近记录",
        "history_empty": "还没有云端或本地训练记录。",
        "share_training": "分享训练"
    ]

    private static let table: [AppLanguage: [String: String]] = [
        .english: english,
        .chinese: chinese,
        .french: english,
        .thai: english
    ]
}
