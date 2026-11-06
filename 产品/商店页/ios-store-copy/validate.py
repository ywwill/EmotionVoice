# -*- coding: utf-8 -*-
"""iOS 商店页元数据校验器（6 本地化）

用法：python3 ios-store-copy/validate.py            # 校验 ios-copy.json（v1）
      python3 ios-store-copy/validate.py ios-copy-v2.json   # 校验 v2
检查：字符上限、字节数、关键词去重、格式、红线词。
返回码 0 = 无硬问题；1 = 有硬问题。
"""
import json, os, sys, re

HERE = os.path.dirname(os.path.abspath(__file__))
TARGET = sys.argv[1] if len(sys.argv) > 1 else "ios-copy.json"
DATA = json.load(open(os.path.join(HERE, TARGET), encoding="utf-8"))
print(f"校验文件：{TARGET}（{DATA.get('version', '?')}）")
LIMIT = DATA["limits"]

# 不可出现在任何元数据里的词（未实现功能 / 竞品 / 公司名 / 价格）
BANNED = ["声音复刻", "声音克隆", "voice clone", "voice cloning", "边写边听",
          "流式合成", "streaming", "免费", "阿里云", "Qwen", "通义", "ElevenLabs"]

# 名称/副标题已经覆盖的词，不应再在关键词里占位
# 中文按「完整独立词」比对，复合短语（视频配音 / 音频导出）不算重复
COVERED = {
    "zh-Hans": ["情感配音", "文字转语音", "语音合成", "方言", "朗读", "有声书",
                "播客", "短视频", "课件", "情绪", "导出"],
    "zh-Hant": ["情感配音", "文字轉語音", "語音合成", "方言", "朗讀", "有聲書",
                "播客", "短影片", "教材", "情緒", "匯出"],
}

def covered_words(name, subtitle, locale):
    if locale.startswith("en"):
        text = (name + " " + subtitle).lower()
        return set(re.findall(r"[a-z]+", text))
    return set(COVERED.get(locale, []))

def check_locale(locale, row):
    issues, warns = [], []
    for field, cap in [("name", LIMIT["name"]), ("subtitle", LIMIT["subtitle"]),
                       ("keywords", LIMIT["keywords"])]:
        val = row[field]
        n, b = len(val), len(val.encode("utf-8"))
        if n > cap:
            issues.append(f"{field} 超长 {n}/{cap}")
        if n == cap:
            warns.append(f"{field} 用满 {n}/{cap}（无余量）")
        for w in BANNED:
            if w.lower() in val.lower():
                issues.append(f"{field} 含红线词「{w}」")
        print(f"  {field:10s} {n:3d}/{cap:<3d} chars  {b:3d} bytes")

    kw = row["keywords"]
    words = kw.split(",")
    if ", " in kw or " ," in kw:
        issues.append("关键词逗号前后有空格")
    if len(words) != len(set(w.lower() for w in words)):
        dup = [w for w in words if words.count(w) > 1]
        issues.append(f"关键词内重复词：{set(dup)}")
    if any(not w.strip() for w in words):
        issues.append("关键词有空词")
    covered = covered_words(row["name"], row["subtitle"], locale)
    # 只对完全相同的独立词做重复检查；复合短语（voice over / read aloud / 视频配音）不算重复
    overlap = [w for w in words if w.lower() in {x.lower() for x in covered}]
    if overlap:
        issues.append(f"关键词与名称/副标题重复：{overlap}")

    if "keywords_bytesafe" in row:
        bs = row["keywords_bytesafe"]
        print(f"  bytesafe   {len(bs):3d} chars  {len(bs.encode()):3d} bytes")
        if len(bs.encode()) > 100:
            issues.append("bytesafe 版超过 100 字节")
    elif locale.startswith("en") and len(kw.encode()) > 100:
        issues.append("英文关键词超过 100 字节")
    return issues, warns

def main():
    all_issues, all_warns = 0, 0
    for locale, row in DATA["locales"].items():
        print(f"\n[{locale}]")
        issues, warns = check_locale(locale, row)
        for w in warns:
            print("  WARN ", w)
        for i in issues:
            print("  FAIL ", i)
        all_issues += len(issues)
        all_warns += len(warns)
    print(f"\n结果：{len(DATA['locales'])} 个本地化，{all_issues} 个硬问题，{all_warns} 条余量提示")
    return 1 if all_issues else 0

if __name__ == "__main__":
    sys.exit(main())
