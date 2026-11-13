#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 fr / de / ja / ko / ru 五份 VoiceCatalog.strings。

数据来源：
  - Shared/Voices/basic_voices.json      —— 音色顺序、stem、gender
  - zh-Hans.lproj/VoiceCatalog.strings  —— 中文特质（决定语义族）
  - voice_catalog_data.py               —— 语义族词根 + 人名化后缀
  - voice_translations/<loc>.tsv        —— 180 条特质译文（中文特质 <TAB> 译文）

设计：
  - 名字 = 语义族意象词根 + 该语种人名化后缀，同语种 599 个全唯一；
    按 (语义族, 性别) 分组、按音色 idx 顺序确定性分配，重跑幂等。
  - 词根按族隔离，跨族天然不撞名；分配时仍做全局去重兜底。
  - 只写五份新语种；zh-Hans / zh-HK / en 由 tools/gen_basic_voices.py 维护。

用法：
  python3 tools/localization/gen_voice_catalog.py --export-features   # 导出待译清单
  python3 tools/localization/gen_voice_catalog.py --check             # 只校验不写盘
  python3 tools/localization/gen_voice_catalog.py                     # 生成五份 .strings
"""

import argparse
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from voice_catalog_data import (  # noqa: E402
    LOCALES, FEATURE_FAMILY, FAMILY_ROOTS, SUFFIXES, GENDER_POOL,
)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
APP_ROOT = os.path.join(PROJECT_ROOT, "EmotionVoice", "EmotionVoice")
SRC_JSON = os.path.join(APP_ROOT, "Shared", "Voices", "basic_voices.json")
TRANS_DIR = os.path.join(SCRIPT_DIR, "voice_translations")

_STRINGS_LINE = re.compile(r'^\s*"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;\s*$')

# ⚠️ 与 tools/gen_basic_voices.py::write_strings() 的 header 必须逐字一致，
# 否则两个生成器会互相把对方的注释改掉，产生无意义的 diff。
HEADER = [
    "/* Voice catalog — 由 tools/gen_basic_voices.py 与 tools/localization/gen_voice_catalog.py 共同生成，请勿手动编辑 */",
    "/* 音色名按语种重新命名（非翻译）：zh / en 为既有两套，fr / de / ja / ko / ru 按特质意象生成 */",
    "/* 词条：voice.<stem>.name / voice.<stem>.feature，stem 与音频文件名去扩展名一致 */",
    "",
]


def unescape(text):
    return text.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")


def escape_strings(text):
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def strings_path(locale):
    return os.path.join(APP_ROOT, "%s.lproj" % locale, "VoiceCatalog.strings")


def parse_strings(path):
    d = {}
    if not os.path.exists(path):
        return d
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = _STRINGS_LINE.match(line)
            if m:
                d[m.group(1)] = unescape(m.group(2))
    return d


def load_voices():
    with open(SRC_JSON, encoding="utf-8") as f:
        raw = json.load(f)
    entries = raw["voices"] if isinstance(raw, dict) else raw
    return sorted(entries, key=lambda v: int(v["idx"]))


def load_translations(locale):
    path = os.path.join(TRANS_DIR, "%s.tsv" % locale)
    out = {}
    if not os.path.exists(path):
        return out
    # utf-8-sig：编辑器可能给译文文件加 BOM，避免首行 key 带上 U+FEFF
    with open(path, encoding="utf-8-sig") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if "\t" not in line:
                raise ValueError("%s 行缺少 TAB: %r" % (path, line))
            key, value = line.split("\t", 1)
            key, value = key.strip(), value.strip()
            if key in out:
                raise ValueError("%s 重复特质: %r" % (path, key))
            if not value:
                raise ValueError("%s 空译文: %r" % (path, key))
            out[key] = value
    return out


_VOWELS_LATIN = set("aeiouyàâäéèêëïîôöùûüœ")
_VOWELS_CYR = set("аеёиоуыэюя")


def join_name(locale, root, suffix, gender):
    """按各语种的构词习惯把意象词根与名尾接起来，避免生硬的元音叠字。

    - fr：词根以元音收尾且名尾以元音起首时，剥掉词根末尾的元音串
      （Douce + ée -> Doucée，Sucre + ée -> Sucrée，而不是 Douceée / Sucreée）。
    - ru 男声：词根以辅音收尾时插入斯拉夫复合名的连接元音 о
      （Нежн + мир -> Нежномир），避免 Пылей 这类不成词的拼接。
    - ja / ko / de 直接拼接（和风汉字名、韩文固有词、日耳曼复合名本就如此）。
    """
    if locale == "fr" and root[-1] in _VOWELS_LATIN and suffix[0] in _VOWELS_LATIN:
        stem = root.rstrip("".join(_VOWELS_LATIN)) or root
        return stem + suffix
    if locale == "ru" and gender == "m" and root[-1] not in _VOWELS_CYR:
        return root + "о" + suffix
    return root + suffix


def build(errors):
    voices = load_voices()
    zh = parse_strings(strings_path("zh-Hans"))
    en = parse_strings(strings_path("en"))

    # ---- 音色顺序 / stem -------------------------------------------------
    rows = []
    for v in voices:
        stem = os.path.splitext(v["audio"])[0]
        nk = "voice.%s.name" % stem
        fk = "voice.%s.feature" % stem
        if nk not in zh or fk not in zh:
            errors.append("zh-Hans 缺词条: %s" % stem)
            continue
        rows.append({
            "stem": stem,
            "feature_zh": zh[fk],
            "feature_en": en.get(fk, ""),
            "gender": v.get("gender", "unknown"),
        })
    if len(rows) != len(voices):
        errors.append("音色条目不齐: %d / %d" % (len(rows), len(voices)))

    # ---- 特质覆盖 -------------------------------------------------------
    feats = sorted({r["feature_zh"] for r in rows})
    missing_family = [f for f in feats if f not in FEATURE_FAMILY]
    extra_family = sorted(set(FEATURE_FAMILY) - set(feats))
    if missing_family:
        errors.append("FEATURE_FAMILY 缺 %d 条: %s" % (len(missing_family), missing_family[:8]))
    if extra_family:
        errors.append("FEATURE_FAMILY 多出 %d 条: %s" % (len(extra_family), extra_family[:8]))
    bad_family = sorted({FEATURE_FAMILY[f] for f in feats
                         if f in FEATURE_FAMILY and FEATURE_FAMILY[f] not in FAMILY_ROOTS})
    if bad_family:
        errors.append("语义族缺词根: %s" % bad_family)

    # ---- 译文 -----------------------------------------------------------
    trans = {}
    for loc in LOCALES:
        t = load_translations(loc)
        miss = [f for f in feats if f not in t]
        extra = sorted(set(t) - set(feats))
        if miss:
            errors.append("%s 译文缺 %d 条: %s" % (loc, len(miss), miss[:5]))
        if extra:
            errors.append("%s 译文多出 %d 条: %s" % (loc, len(extra), extra[:5]))
        trans[loc] = t

    # ---- 分组 -----------------------------------------------------------
    groups = collections.OrderedDict()
    for r in rows:
        fam = FEATURE_FAMILY.get(r["feature_zh"])
        if fam not in FAMILY_ROOTS:
            continue
        g = GENDER_POOL.get(r["gender"], "f")
        groups.setdefault((fam, g), []).append(r["stem"])

    # ---- 分配名字 -------------------------------------------------------
    names = {}
    stats = {}
    for loc in LOCALES:
        used = set()
        per_loc = {}
        for (fam, g), stems in groups.items():
            roots = FAMILY_ROOTS[fam][loc]
            sufs = list(dict.fromkeys(SUFFIXES[loc][g]))  # 去重、保序
            # suffix-major：先换词根，保证同一族前几个名字不都长一个样
            combos = [join_name(loc, r, s, g) for s in sufs for r in roots]
            pool = iter(combos)
            for stem in stems:
                try:
                    name = next(c for c in pool if c not in used)
                except StopIteration:
                    errors.append("%s / %s / %s 名字池耗尽（需要 %d，可用 %d）"
                                  % (loc, fam, g, len(stems), len(combos)))
                    break
                if '"' in name or "\\" in name:
                    errors.append("%s 名字含非法字符: %r" % (loc, name))
                used.add(name)
                per_loc[stem] = name
        names[loc] = per_loc
        stats[loc] = (len(per_loc), len(used), max((len(n) for n in used), default=0))
        if len(per_loc) != len(rows):
            errors.append("%s 名字数 %d != 音色数 %d" % (loc, len(per_loc), len(rows)))
        if len(used) != len(per_loc):
            errors.append("%s 出现重名" % loc)

    return rows, trans, names, stats, feats


def write_strings(path, rows, locale, trans, names):
    lines = list(HEADER)
    for r in rows:
        stem = r["stem"]
        lines.append('"voice.%s.name" = "%s";'
                     % (stem, escape_strings(names[locale][stem])))
        lines.append('"voice.%s.feature" = "%s";'
                     % (stem, escape_strings(trans[locale][r["feature_zh"]])))
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def export_features(feats, rows):
    os.makedirs(TRANS_DIR, exist_ok=True)
    en_by_zh = {r["feature_zh"]: r["feature_en"] for r in rows}
    path = os.path.join(TRANS_DIR, "_features.tsv")
    with open(path, "w", encoding="utf-8") as f:
        f.write("# 中文特质<TAB>英文特质<TAB>语义族 —— 供 5 份译文按中文 key 对齐\n")
        for feat in feats:
            f.write("%s\t%s\t%s\n" % (feat, en_by_zh.get(feat, ""),
                                      FEATURE_FAMILY.get(feat, "?")))
    print("[ok] %s  (%d 条)" % (path, len(feats)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只校验，不写盘")
    ap.add_argument("--export-features", action="store_true", help="导出待译特质清单")
    args = ap.parse_args()

    errors = []
    rows, trans, names, stats, feats = build(errors)

    if args.export_features:
        export_features(feats, rows)

    if errors:
        print("[error] 校验失败 (%d):" % len(errors))
        for e in errors:
            print("  - %s" % e)
        return 1

    if args.check or args.export_features:
        print("[ok] 校验通过：%d 音色 / %d 特质 / %d 语种" % (len(rows), len(feats), len(LOCALES)))
        for loc in LOCALES:
            print("     %s: %d 名字，%d 唯一，最长 %d 字符" % ((loc,) + stats[loc]))
        return 0

    for loc in LOCALES:
        p = strings_path(loc)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        write_strings(p, rows, loc, trans, names)
        print("[ok] %s  (%d 词条)" % (p, len(rows) * 2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
