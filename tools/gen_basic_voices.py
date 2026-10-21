#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成音色目录的数据文件与本地化词条。

产出：
  1. basic_voices.json（v4）—— 只含语义数据与稳定 key，不含任何文案、不含冗余 id
  2. 每个 .lproj 目录一份 VoiceCatalog.strings（zh-Hans / en / zh-HK …，自动扫描）

设计要点：
  - 数据与文案彻底分离：JSON 零文案、零冗余字段
  - 本地化 key 统一为「短标识 stem」= 从 key 去掉模型前缀 qwen-audio-3.0-tts-plus- 得到
    （与 audio 文件名去扩展名一致），如 longcanzhuyue
  - 名字与特质都按 stem 取：voice.<stem>.name / voice.<stem>.feature
  - 加新语言只需新增一个 .lproj/VoiceCatalog.strings，JSON 与数据库都不用动

idx 规则：
  旗舰音色 idx = 1, 2；基础音色从 3 起顺序编号。idx 是便捷整数 id（DB 主键）。

幂等：重复执行产出一致结果（文案来自已提交的 VoiceCatalog.strings，不重新分配）。
用法：python3 tools/gen_basic_voices.py
"""

import json
import os
import re
import sys

# ---------------------------------------------------------------------------
# 路径
# ---------------------------------------------------------------------------

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
LOCALE_ROOT = os.path.join(PROJECT_ROOT, "EmotionVoice", "EmotionVoice")
SRC_JSON = os.path.join(LOCALE_ROOT, "Voices", "basic_voices.json")

# 基准语种：JSON 之外的所有文案都以它为回退源（新增语种缺词条时先用简体顶上）
BASE_LOCALE = "zh-Hans"

# TTS 参数 key 的模型前缀，剥掉后得到短标识 stem
MODEL_PREFIX = "qwen-audio-3.0-tts-plus-"


def strings_path(locale):
    return os.path.join(LOCALE_ROOT, "%s.lproj" % locale, "VoiceCatalog.strings")


def discover_locales():
    """扫描所有 .lproj（Base 除外）——加新语言只需新增一个目录，本脚本不用改"""
    return sorted(
        d[:-len(".lproj")]
        for d in os.listdir(LOCALE_ROOT)
        if d.endswith(".lproj") and d != "Base.lproj"
        and os.path.isdir(os.path.join(LOCALE_ROOT, d))
    )

# ---------------------------------------------------------------------------
# 合法值（用于校验）
# ---------------------------------------------------------------------------

VALID_GENDER = {"female", "male", "unknown"}
VALID_LANG = {"zh", "en"}
VALID_TIER = {"premium", "basic"}
VALID_SCENE = {
    "daily", "companion", "reading", "customer_service", "social", "anime",
    "news", "live_stream", "classic_audiobook", "sports", "audiobook", "radio",
    "knowledge", "comedy", "business", "assistant", "speech",
}


# ---------------------------------------------------------------------------
# stem 计算
# ---------------------------------------------------------------------------

def strip_prefix(key):
    return key[len(MODEL_PREFIX):] if key.startswith(MODEL_PREFIX) else key


def audio_stem(audio):
    return os.path.splitext(audio)[0]


def stem_of(v):
    """短标识：优先 audio 去扩展名（与 key 去前缀等价），缺失时退回 key 去前缀"""
    return audio_stem(v.get("audio", "")) or strip_prefix(v.get("key", ""))


# ---------------------------------------------------------------------------
# .strings 解析（用于回读已提交的文案）
# ---------------------------------------------------------------------------

_STRINGS_LINE = re.compile(r'^\s*"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;\s*$')


def unescape(text):
    return text.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")


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


def escape_strings(text):
    """.strings 文件里需要转义的字符"""
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


# ---------------------------------------------------------------------------
# 读取源数据（basic_voices.json 只含数据字段）
# ---------------------------------------------------------------------------

def load_data():
    with open(SRC_JSON, encoding="utf-8") as f:
        raw = json.load(f)

    entries = raw["voices"] if isinstance(raw, dict) else raw

    out = []
    for e in entries:
        out.append({
            "idx": int(e.get("idx", 0)),
            "key": e["key"],
            "tier": e.get("tier", "basic"),
            "lang": e.get("lang", "zh"),
            "gender": e.get("gender", "unknown"),
            "age": int(e.get("age", 0)),
            "scene": e.get("scene", "daily"),
            "audio": e.get("audio", ""),
            # 迁移期回读用：旧 JSON 可能带 featureKey；新 schema 不再写出此字段
            "featureKey": e.get("featureKey"),
        })
    return out


# ---------------------------------------------------------------------------
# idx 分配：旗舰 1, 2；基础从 3 起顺序编号（保持基础原有相对顺序）
# ---------------------------------------------------------------------------

def assign_idx(items):
    premium = [v for v in items if v["tier"] == "premium"]
    basic = sorted((v for v in items if v["tier"] != "premium"), key=lambda x: x["idx"])

    n = 1
    for v in premium:
        v["idx"] = n
        n += 1
    for v in basic:
        v["idx"] = n
        n += 1

    # 顺序：旗舰在前，基础在后；这样 JSON 数组顺序与 idx 顺序一致
    return premium + basic


# ---------------------------------------------------------------------------
# 生成
# ---------------------------------------------------------------------------

def build():
    items = load_data()
    locales = discover_locales()
    tables = {loc: parse_strings(strings_path(loc)) for loc in locales}

    ordered = assign_idx(items)

    voices = []
    entries = {loc: [] for loc in locales}

    for v in ordered:
        stem = stem_of(v)
        slug = v["featureKey"]

        base = tables.get(BASE_LOCALE, {})
        name_base = base.get("voice.%s.name" % stem, stem)
        # 特质：优先新的 per-voice key，回退到旧的共享 slug key（迁移兼容）
        feat_base = base.get("voice.%s.feature" % stem) or base.get("voice.feature.%s" % slug, stem)

        voices.append({
            "idx": v["idx"],
            "key": v["key"],
            "tier": v["tier"],
            "lang": v["lang"],
            "gender": v["gender"],
            "age": v["age"],
            "scene": v["scene"],
            "audio": v["audio"],
        })

        for loc in locales:
            t = tables[loc]
            if loc == BASE_LOCALE:
                name, feat = name_base, feat_base
            else:
                name = t.get("voice.%s.name" % stem) or name_base
                feat = (t.get("voice.%s.feature" % stem)
                        or t.get("voice.feature.%s" % slug)
                        or feat_base)
            entries[loc].append(("voice.%s.name" % stem, name))
            entries[loc].append(("voice.%s.feature" % stem, feat))

    payload = {
        "version": 4,
        "generatedBy": "tools/gen_basic_voices.py",
        "voices": voices,
    }
    return payload, entries


# ---------------------------------------------------------------------------
# 校验
# ---------------------------------------------------------------------------

def validate(payload, entries):
    errors = []
    voices = payload["voices"]

    seen_idx, seen_key = set(), set()
    for v in voices:
        if v["idx"] in seen_idx:
            errors.append("重复 idx: %d" % v["idx"])
        seen_idx.add(v["idx"])
        if v["key"] in seen_key:
            errors.append("重复 key: %s" % v["key"])
        seen_key.add(v["key"])

        if v["gender"] not in VALID_GENDER:
            errors.append("非法 gender: %s (%s)" % (v["gender"], v["key"]))
        if v["lang"] not in VALID_LANG:
            errors.append("非法 lang: %s (%s)" % (v["lang"], v["key"]))
        if v["tier"] not in VALID_TIER:
            errors.append("非法 tier: %s (%s)" % (v["tier"], v["key"]))
        if v["scene"] not in VALID_SCENE:
            errors.append("非法 scene: %s (%s)" % (v["scene"], v["key"]))
        if not (0 < v["age"] < 120):
            errors.append("非法 age: %s (%s)" % (v["age"], v["key"]))

    # idx 连续 1..N
    if sorted(seen_idx) != list(range(1, len(voices) + 1)):
        errors.append("idx 不连续（应为 1..%d）: %s..." % (len(voices), sorted(seen_idx)[:10]))

    # 音频文件存在性
    voices_dir = os.path.dirname(SRC_JSON)
    missing = [
        v["audio"] for v in voices
        if v["audio"] and not os.path.exists(os.path.join(voices_dir, v["audio"]))
    ]
    if missing:
        errors.append("缺失预览音频 %d 个: %s..." % (len(missing), missing[:5]))

    # 各语种词条数一致
    counts = {loc: len(e) for loc, e in entries.items()}
    if len(set(counts.values())) > 1:
        errors.append("各语种词条数不一致: %s" % counts)

    return errors


# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------

def write_json(payload):
    with open(SRC_JSON, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write("\n")


def write_strings(path, entries):
    lines = [
        "/* Voice catalog — 由 tools/gen_basic_voices.py 生成，请勿手动编辑 */",
        "/* 音色名与特质文案，按 voice.<stem>.name / voice.<stem>.feature 取值 */",
        "/* stem = 从 key 去掉 qwen-audio-3.0-tts-plus- 前缀（与音频文件名去扩展名一致） */",
        "",
    ]
    lines += ['"%s" = "%s";' % (k, escape_strings(v)) for k, v in entries]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main():
    payload, entries = build()
    errors = validate(payload, entries)
    if errors:
        print("[error] 校验失败:")
        for e in errors:
            print("  - %s" % e)
        return 1

    write_json(payload)
    for loc, e in entries.items():
        write_strings(strings_path(loc), e)

    voices = payload["voices"]
    premium = [v for v in voices if v["tier"] == "premium"]
    size = os.path.getsize(SRC_JSON)
    print("[ok] %s" % SRC_JSON)
    print("     %d 条（旗舰 %d / 基础 %d），%.1f KB" % (
        len(voices), len(premium), len(voices) - len(premium), size / 1024))
    for loc in sorted(entries):
        print("[ok] %s  (%d 条)" % (strings_path(loc), len(entries[loc])))
    print("     词条构成: 音色名 %d + 特质 %d" % (len(voices), len(voices)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
