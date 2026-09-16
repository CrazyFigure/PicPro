//! 证件照规格预设库。
//!
//! 数据基准为北京市《摄影行业服务规范（试行）》中的常规照片尺寸规格表，
//! 并补充了各类考试报名、签证与证件的高频规格。
//!
//! 两点必须向用户说明的事实：
//! 1. **同一名称的规格在不同机构可能不一致**。例如照相馆所说的「二寸」
//!    常指 35×53mm（严格叫大二寸），而多数报名系统要的是 35×49mm。
//! 2. **像素与毫米是同一张照片的两种表达**，换算关系为
//!    `像素 = 毫米 ÷ 25.4 × dpi`。同一物理尺寸在 350dpi 下像素更多，
//!    所以规格必须以「目标机构的要求」为准，不能套用其他 dpi 的数值。
//!
//! 因此界面在展示预设的同时给出毫米/像素/dpi 三元信息与备注，
//! 让用户能自行核对，而不是盲信预设。

/// 预设分类。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PresetCategory {
    /// 基础寸照（一寸、二寸等）
    BasicSize,
    /// 证件类（身份证、社保卡等）
    Document,
    /// 考试报名
    Exam,
    /// 签证
    Visa,
    /// 其他（简历照、职业照等）
    Other,
}

impl PresetCategory {
    /// 中文展示名。
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::BasicSize => "基础寸照",
            Self::Document => "证件类",
            Self::Exam => "考试报名",
            Self::Visa => "签证",
            Self::Other => "其他",
        }
    }

    /// 全部分类，供界面按顺序生成分组。
    pub fn all() -> &'static [PresetCategory] {
        &[
            Self::BasicSize,
            Self::Document,
            Self::Exam,
            Self::Visa,
            Self::Other,
        ]
    }
}

/// 底色类型。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PresetBackground {
    /// 标准蓝底
    Blue,
    /// 深蓝底
    DarkBlue,
    /// 浅蓝底
    LightBlue,
    /// 白底
    White,
    /// 红底
    Red,
    /// 灰底
    Grey,
}

impl PresetBackground {
    /// 该底色的 RGB 取值。
    ///
    /// 蓝底取 `#438EDB`，这是国内证件照最通用的标准蓝，
    /// 各类考试报名系统的「蓝底」默认按此色值输出。
    pub fn rgb(&self) -> [u8; 3] {
        match self {
            Self::Blue => [67, 142, 219],
            Self::DarkBlue => [0, 82, 165],
            Self::LightBlue => [156, 202, 240],
            Self::White => [255, 255, 255],
            Self::Red => [255, 0, 0],
            Self::Grey => [166, 166, 166],
        }
    }

    /// 中文展示名。
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Blue => "蓝底",
            Self::DarkBlue => "深蓝底",
            Self::LightBlue => "浅蓝底",
            Self::White => "白底",
            Self::Red => "红底",
            Self::Grey => "灰底",
        }
    }
}

/// 证件照规格。
#[derive(Debug, Clone, Copy)]
pub struct PhotoPreset {
    /// 稳定标识，用于持久化用户选择
    pub id: &'static str,
    /// 展示名
    pub name: &'static str,
    pub category: PresetCategory,
    pub width_mm: f32,
    pub height_mm: f32,
    /// 该规格的目标像素宽
    pub width_px: u32,
    /// 该规格的目标像素高
    pub height_px: u32,
    /// 像素尺寸对应的分辨率
    pub dpi: u32,
    /// 该规格允许/常用的底色
    pub backgrounds: &'static [PresetBackground],
    /// 备注：用途、额外限制（体积、格式、构图）
    pub note: &'static str,
}

impl PhotoPreset {
    /// 目标宽高比。
    pub fn aspect(&self) -> f32 {
        self.width_px as f32 / self.height_px as f32
    }

    /// 毫米尺寸文案。
    pub fn mm_label(&self) -> String {
        format!("{:.1}×{:.1}mm", self.width_mm, self.height_mm)
    }

    /// 像素尺寸文案。
    pub fn px_label(&self) -> String {
        format!("{}×{}px", self.width_px, self.height_px)
    }

    /// 是否推荐使用指定的某种底色。
    pub fn supports_background(&self, bg: PresetBackground) -> bool {
        self.backgrounds.contains(&bg)
    }
}

/// 毫米换算为像素。
///
/// `像素 = 毫米 ÷ 25.4 × dpi`。结果至少为 1，避免极小尺寸取整为 0。
pub fn mm_to_px(mm: f32, dpi: u32) -> u32 {
    ((mm / 25.4) * dpi as f32).round().max(1.0) as u32
}

// 常用底色组合的静态常量，避免在表中重复书写
const BWR: &[PresetBackground] = &[
    PresetBackground::Blue,
    PresetBackground::White,
    PresetBackground::Red,
];
const BW: &[PresetBackground] = &[PresetBackground::Blue, PresetBackground::White];
const W: &[PresetBackground] = &[PresetBackground::White];
const B: &[PresetBackground] = &[PresetBackground::Blue];

/// 全部规格预设。
pub fn all_presets() -> &'static [PhotoPreset] {
    PRESETS
}

/// 按 id 查找规格。
pub fn find_preset(id: &str) -> Option<&'static PhotoPreset> {
    PRESETS.iter().find(|p| p.id == id)
}

/// 按分类取出规格。
pub fn presets_in_category(category: PresetCategory) -> Vec<&'static PhotoPreset> {
    PRESETS.iter().filter(|p| p.category == category).collect()
}

/// 规格总表。
///
/// 表中同时保留了毫米与像素两组数值，便于界面直接展示、用户自行核对。
static PRESETS: &[PhotoPreset] = &[
    // ---------------- 基础寸照 ----------------
    PhotoPreset {
        id: "size_1cun_small",
        name: "小一寸",
        category: PresetCategory::BasicSize,
        width_mm: 22.0,
        height_mm: 32.0,
        width_px: 260,
        height_px: 378,
        dpi: 300,
        backgrounds: BWR,
        note: "驾驶证、健康证等",
    },
    PhotoPreset {
        id: "size_1cun",
        name: "一寸",
        category: PresetCategory::BasicSize,
        width_mm: 25.0,
        height_mm: 35.0,
        width_px: 295,
        height_px: 413,
        dpi: 300,
        backgrounds: BWR,
        note: "最常用规格。教师资格证、执业药师、一级建造师等多用此尺寸",
    },
    PhotoPreset {
        id: "size_1cun_large",
        name: "大一寸",
        category: PresetCategory::BasicSize,
        width_mm: 33.0,
        height_mm: 48.0,
        width_px: 390,
        height_px: 567,
        dpi: 300,
        backgrounds: BWR,
        note: "护照、港澳通行证、海外签证常用",
    },
    PhotoPreset {
        id: "size_2cun_small",
        name: "小二寸",
        category: PresetCategory::BasicSize,
        width_mm: 35.0,
        height_mm: 45.0,
        width_px: 413,
        height_px: 531,
        dpi: 300,
        backgrounds: BWR,
        note: "公务员考试、部分签证常用",
    },
    PhotoPreset {
        id: "size_2cun",
        name: "二寸",
        category: PresetCategory::BasicSize,
        width_mm: 35.0,
        height_mm: 49.0,
        width_px: 413,
        height_px: 579,
        dpi: 300,
        backgrounds: BWR,
        note: "毕业证、简历、二级建造师常用。注意与照相馆俗称的「二寸」(35×53mm) 不同",
    },
    PhotoPreset {
        id: "size_2cun_large",
        name: "大二寸",
        category: PresetCategory::BasicSize,
        width_mm: 35.0,
        height_mm: 53.0,
        width_px: 413,
        height_px: 626,
        dpi: 300,
        backgrounds: BWR,
        note: "学士照、国家司法考试等",
    },
    PhotoPreset {
        id: "size_3cun",
        name: "三寸",
        category: PresetCategory::BasicSize,
        width_mm: 55.0,
        height_mm: 84.0,
        width_px: 650,
        height_px: 992,
        dpi: 300,
        backgrounds: BWR,
        note: "用于洗印分发",
    },
    PhotoPreset {
        id: "size_5cun",
        name: "五寸",
        category: PresetCategory::BasicSize,
        width_mm: 89.0,
        height_mm: 127.0,
        width_px: 1051,
        height_px: 1500,
        dpi: 300,
        backgrounds: BWR,
        note: "冲印分发用",
    },
    // ---------------- 证件类 ----------------
    PhotoPreset {
        id: "doc_idcard",
        name: "身份证",
        category: PresetCategory::Document,
        width_mm: 26.0,
        height_mm: 32.0,
        // 身份证规格按 350dpi 定义，像素数为 358×441
        width_px: 358,
        height_px: 441,
        dpi: 350,
        backgrounds: W,
        note: "白底，公安机关统一规格。常见体积要求较小",
    },
    PhotoPreset {
        id: "doc_social_card",
        name: "社保卡",
        category: PresetCategory::Document,
        width_mm: 26.0,
        height_mm: 32.0,
        width_px: 358,
        height_px: 441,
        dpi: 350,
        backgrounds: W,
        note: "白底，各地人社/银行系统通用",
    },
    PhotoPreset {
        id: "doc_driver_license",
        name: "驾驶证",
        category: PresetCategory::Document,
        width_mm: 22.0,
        height_mm: 32.0,
        width_px: 260,
        height_px: 378,
        dpi: 300,
        backgrounds: W,
        note: "白底，与小一寸同尺寸",
    },
    PhotoPreset {
        id: "doc_passport",
        name: "护照 / 港澳通行证",
        category: PresetCategory::Document,
        width_mm: 33.0,
        height_mm: 48.0,
        width_px: 390,
        height_px: 567,
        dpi: 300,
        backgrounds: W,
        note: "白底，要求人物头部清晰、边距规范",
    },
    PhotoPreset {
        id: "doc_residence",
        name: "居住证",
        category: PresetCategory::Document,
        width_mm: 26.0,
        height_mm: 32.0,
        width_px: 358,
        height_px: 441,
        dpi: 350,
        backgrounds: W,
        note: "白底",
    },
    // ---------------- 考试报名 ----------------
    PhotoPreset {
        id: "exam_kaoyan",
        name: "考研网上确认",
        category: PresetCategory::Exam,
        // 研招网要求宽高比 3:4，未规定固定像素；480×640 是普遍采用的实现
        width_mm: 0.0,
        height_mm: 0.0,
        width_px: 480,
        height_px: 640,
        dpi: 300,
        backgrounds: BW,
        note: "仅支持 jpg/jpeg，建议不超过 10MB。要求宽高比 3:4；眼睛位于上边缘 30%~50% 处，头肩占比约 2/3。部分省份指定白底",
    },
    PhotoPreset {
        id: "exam_chsi",
        name: "学信网图像采集",
        category: PresetCategory::Exam,
        width_mm: 0.0,
        height_mm: 0.0,
        width_px: 480,
        height_px: 640,
        dpi: 300,
        backgrounds: B,
        note: "蓝底，宽高比 3:4，常见体积要求约 30~100KB",
    },
    PhotoPreset {
        id: "exam_gaokao",
        name: "高考报名",
        category: PresetCategory::Exam,
        width_mm: 35.6,
        height_mm: 47.4,
        width_px: 420,
        height_px: 560,
        dpi: 300,
        backgrounds: B,
        note: "蓝底，考生注册用。各省要求可能不同",
    },
    PhotoPreset {
        id: "exam_civil_servant",
        name: "公务员考试",
        category: PresetCategory::Exam,
        width_mm: 35.0,
        height_mm: 45.0,
        width_px: 413,
        height_px: 531,
        dpi: 300,
        backgrounds: BW,
        note: "国考及多数地方公务员考试通用",
    },
    PhotoPreset {
        id: "exam_teacher_cert",
        name: "教师资格证",
        category: PresetCategory::Exam,
        width_mm: 25.0,
        height_mm: 35.0,
        width_px: 295,
        height_px: 413,
        dpi: 300,
        backgrounds: W,
        note: "白底。另有 35×45mm 蓝底的版本，以报名公告为准",
    },
    PhotoPreset {
        id: "exam_ncre",
        name: "计算机等级考试",
        category: PresetCategory::Exam,
        width_mm: 33.0,
        height_mm: 48.0,
        width_px: 390,
        height_px: 567,
        dpi: 300,
        backgrounds: BW,
        note: "全国计算机等级考试",
    },
    PhotoPreset {
        id: "exam_cet",
        name: "英语四六级",
        category: PresetCategory::Exam,
        width_mm: 12.2,
        height_mm: 16.3,
        width_px: 144,
        height_px: 192,
        dpi: 300,
        backgrounds: BW,
        note: "另有 240×320、480×640 等版本",
    },
    PhotoPreset {
        id: "exam_self_study",
        name: "成人自考",
        category: PresetCategory::Exam,
        width_mm: 32.5,
        height_mm: 43.3,
        width_px: 384,
        height_px: 512,
        dpi: 300,
        backgrounds: BW,
        note: "另常见 480×640 / 480×720 版本",
    },
    // ---------------- 签证 ----------------
    PhotoPreset {
        id: "visa_us",
        name: "美国签证",
        category: PresetCategory::Visa,
        width_mm: 51.0,
        height_mm: 51.0,
        width_px: 602,
        height_px: 602,
        dpi: 300,
        backgrounds: W,
        note: "正方形 2×2 英寸，白底，常见体积上限约 240KB",
    },
    PhotoPreset {
        id: "visa_japan",
        name: "日本签证",
        category: PresetCategory::Visa,
        width_mm: 45.0,
        height_mm: 45.0,
        width_px: 531,
        height_px: 531,
        dpi: 300,
        backgrounds: W,
        note: "正方形，白底",
    },
    PhotoPreset {
        id: "visa_shengen",
        name: "申根签证",
        category: PresetCategory::Visa,
        width_mm: 35.0,
        height_mm: 45.0,
        width_px: 413,
        height_px: 531,
        dpi: 300,
        backgrounds: W,
        note: "白底。英国、加拿大等也多采用此规格",
    },
    PhotoPreset {
        id: "visa_korea_thai",
        name: "韩国 / 泰国 / 马来西亚签证",
        category: PresetCategory::Visa,
        width_mm: 35.0,
        height_mm: 45.0,
        width_px: 413,
        height_px: 531,
        dpi: 300,
        backgrounds: W,
        note: "白底，与申根同尺寸",
    },
    // ---------------- 其他 ----------------
    PhotoPreset {
        id: "other_resume",
        name: "简历照",
        category: PresetCategory::Other,
        width_mm: 25.0,
        height_mm: 35.0,
        width_px: 295,
        height_px: 413,
        dpi: 300,
        backgrounds: BWR,
        note: "与一寸同尺寸，多为蓝底或白底",
    },
    PhotoPreset {
        id: "other_professional",
        name: "半身职业照",
        category: PresetCategory::Other,
        width_mm: 72.0,
        height_mm: 101.6,
        width_px: 850,
        height_px: 1200,
        dpi: 300,
        backgrounds: BWR,
        note: "上半身职业照、入职照常用",
    },
    PhotoPreset {
        id: "other_hd",
        name: "高清证件照",
        category: PresetCategory::Other,
        width_mm: 84.7,
        height_mm: 118.5,
        width_px: 1000,
        height_px: 1400,
        dpi: 300,
        backgrounds: BWR,
        note: "高分辨率冲印、长期存档用",
    },
];

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn 规格id唯一() {
        let mut seen = HashSet::new();
        for p in all_presets() {
            assert!(seen.insert(p.id), "id 重复：{}", p.id);
        }
    }

    #[test]
    fn 毫米与像素换算自洽() {
        // 对给出毫米尺寸的规格，验证像素值与 毫米/dpi 换算一致（允许 1px 取整误差）
        for p in all_presets() {
            if p.width_mm <= 0.0 || p.height_mm <= 0.0 {
                continue; // 无毫米定义的规格（如研招网 3:4）跳过
            }
            let expect_w = mm_to_px(p.width_mm, p.dpi);
            let expect_h = mm_to_px(p.height_mm, p.dpi);
            assert!(
                (p.width_px as i64 - expect_w as i64).abs() <= 1,
                "{} 宽度不一致：表内 {} vs 换算 {}",
                p.name,
                p.width_px,
                expect_w
            );
            assert!(
                (p.height_px as i64 - expect_h as i64).abs() <= 1,
                "{} 高度不一致：表内 {} vs 换算 {}",
                p.name,
                p.height_px,
                expect_h
            );
        }
    }

    #[test]
    fn 关键规格数值正确() {
        let one = find_preset("size_1cun").unwrap();
        assert_eq!((one.width_px, one.height_px), (295, 413));
        let two = find_preset("size_2cun").unwrap();
        assert_eq!((two.width_px, two.height_px), (413, 579));
        let idcard = find_preset("doc_idcard").unwrap();
        // 身份证为 26×32mm @350dpi
        assert_eq!((idcard.width_px, idcard.height_px), (358, 441));
        assert_eq!(idcard.dpi, 350);
    }

    #[test]
    fn 考研规格宽高比为三比四() {
        let p = find_preset("exam_kaoyan").unwrap();
        assert!((p.aspect() - 0.75).abs() < 1e-6, "研招网要求 3:4");
        // 研招网未规定毫米尺寸，不应凭空编造
        assert_eq!(p.width_mm, 0.0);
    }

    #[test]
    fn 身份证只允许白底() {
        let p = find_preset("doc_idcard").unwrap();
        assert!(p.supports_background(PresetBackground::White));
        assert!(!p.supports_background(PresetBackground::Blue));
    }

    #[test]
    fn 标准蓝底色值正确() {
        assert_eq!(PresetBackground::Blue.rgb(), [67, 142, 219]);
        assert_eq!(PresetBackground::White.rgb(), [255, 255, 255]);
    }

    #[test]
    fn 分类查询覆盖全部规格() {
        let total: usize = PresetCategory::all()
            .iter()
            .map(|c| presets_in_category(*c).len())
            .sum();
        assert_eq!(total, all_presets().len(), "分类查询应覆盖所有预设");
    }

    #[test]
    fn 不存在的id返回None() {
        assert!(find_preset("not_exist").is_none());
    }

    #[test]
    fn 毫米换算边界安全() {
        assert_eq!(mm_to_px(0.1, 300), 1, "极小尺寸至少 1 像素");
        assert_eq!(mm_to_px(25.0, 300), 295);
    }
}
