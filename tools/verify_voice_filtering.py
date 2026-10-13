#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
数据层冒烟测试。

用 Python + sqlite3 复刻 DatabaseManager 的建表/灌库与 VoiceService 的筛选谓词，
验证「语义 code 化」之后分类与筛选仍然正确。校验的是逻辑，不是 Swift 代码本身。

用法：python3 tools/verify_voice_filtering.py
"""

import json
import os
import sqlite3
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
JSON_PATH = os.path.join(PROJECT_ROOT, "EmotionVoice", "EmotionVoice", "Voices", "basic_voices.json")

# 与 Voice.swift 中 VoiceCategory 的 rawValue 保持一致
CATEGORIES = [
    "premium", "chinese", "english",
    "scene_daily", "scene_companion", "scene_customer", "scene_reading",
    "scene_social", "scene_anime", "scene_news", "scene_live", "scene_classic",
    "scene_sports", "scene_audiobook", "scene_radio", "scene_knowledge",
    "scene_comedy", "scene_business", "scene_assistant", "scene_speech",
    "role_anime", "role_live", "role_classic", "role_radio",
    "age_child", "age_teen", "age_young", "age_middle", "age_senior",
]

# VoiceService.categoryPredicate 的等价 SQL
SCENE_PREDICATE = {
    "scene_daily": "scene_key = 'daily'",
    "scene_companion": "scene_key = 'companion'",
    "scene_customer": "scene_key = 'customer_service'",
    "scene_reading": "scene_key = 'reading'",
    "scene_social": "scene_key = 'social'",
    "scene_anime": "scene_key = 'anime'",
    "scene_news": "scene_key = 'news'",
    "scene_live": "scene_key = 'live_stream'",
    "scene_classic": "scene_key = 'classic_audiobook'",
    "scene_sports": "scene_key = 'sports'",
    "scene_audiobook": "scene_key = 'audiobook'",
    "scene_radio": "scene_key = 'radio'",
    "scene_knowledge": "scene_key = 'knowledge'",
    "scene_comedy": "scene_key = 'comedy'",
    "scene_business": "scene_key = 'business'",
    "scene_assistant": "scene_key = 'assistant'",
    "scene_speech": "scene_key = 'speech'",
    "role_anime": "scene_key = 'anime'",
    "role_live": "scene_key = 'live_stream'",
    "role_classic": "scene_key = 'classic_audiobook'",
    "role_radio": "scene_key = 'radio'",
    "age_child": "age < 13",
    "age_teen": "age >= 13 AND age < 18",
    "age_young": "age >= 18 AND age < 36",
    "age_middle": "age >= 36 AND age < 60",
    "age_senior": "age >= 60",
}


# 场景 code -> (中文名, 英文名)，与 VoiceCatalog.swift 的 VoiceSceneCode.displayName 一致
SCENE_NAMES = {
    "daily":            ("日常对话", "Daily Chat"),
    "companion":        ("情感陪伴", "Companionship"),
    "reading":          ("有声阅读", "Audiobook Reading"),
    "customer_service": ("客服", "Customer Service"),
    "social":           ("社交互动", "Social"),
    "anime":            ("动漫配音", "Anime Dubbing"),
    "news":             ("新闻播报", "News Broadcast"),
    "live_stream":      ("电商直播", "Live Commerce"),
    "classic_audiobook": ("古风有声书", "Classic Audiobook"),
    "sports":           ("体育解说", "Sports Commentary"),
    "audiobook":        ("有声书配音", "Audiobook"),
    "radio":            ("深夜电台", "Late-Night Radio"),
    "knowledge":        ("知识分享", "Knowledge Sharing"),
    "comedy":           ("娱乐搞笑", "Comedy"),
    "business":         ("商务汇报", "Business Report"),
    "assistant":        ("智能助手", "Smart Assistant"),
    "speech":           ("演讲朗诵", "Speech & Recital"),
}

LANG_NAMES = {"zh": ("中文", "Chinese"), "en": ("英文", "English")}

SEARCH_CASES = {
    "zh": [
        ("电台", "中文描述关键词"),
        ("龙安灵心", "中文旗舰名"),
        ("情感陪伴", "中文场景名"),
        ("深夜电台", "冷门场景名"),
        ("中文", "中文语种名"),
        ("Olivia", "英文音色名"),
    ],
    "en": [
        ("Radio", "英文描述关键词"),
        ("Lynn", "英文旗舰名"),
        ("Companionship", "英文场景名"),
        ("Late-Night", "冷门场景名"),
        ("Chinese", "英文语种名"),
        ("Lucas", "旗舰英文名"),
    ],
}


def predicate_for(cat):
    if cat == "premium":
        return "tier = 'premium'"
    if cat == "chinese":
        return "lang_code = 'zh'"
    if cat == "english":
        return "lang_code = 'en'"
    return SCENE_PREDICATE[cat]


def build_db():
    """按 DatabaseManager.createTables() 的当前结构建表，只含语义 code 列。"""
    conn = sqlite3.connect(":memory:")
    conn.execute("""
        CREATE TABLE voices (
            key TEXT PRIMARY KEY,
            name TEXT, name_en TEXT,
            desc TEXT, desc_en TEXT,
            tier TEXT,
            is_favorite INTEGER DEFAULT 0,
            scene_key TEXT,
            age INTEGER DEFAULT 0,
            gender_code TEXT,
            audio TEXT,
            lang_code TEXT
        )
    """)

    with open(JSON_PATH, encoding="utf-8") as f:
        payload = json.load(f)

    for v in payload["voices"]:
        conn.execute(
            "INSERT INTO voices (key, name, name_en, desc, desc_en, tier,"
            " is_favorite, scene_key, age, gender_code, audio, lang_code)"
            " VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                v["key"],
                v["zh"]["name"],
                v["en"]["name"],
                # Swift 侧 displayDesc：中文去掉结尾的"音"
                v["zh"]["feature"][:-1] if v["zh"]["feature"].endswith("音") else v["zh"]["feature"],
                v["en"]["feature"],
                v["tier"],
                1 if v["tier"] == "premium" else 0,
                v["scene"],
                v["age"],
                v["gender"],
                v["audio"],
                v["lang"],
            ),
        )
    conn.commit()
    return conn, payload["voices"]


def main():
    conn, voices = build_db()
    total = len(voices)
    failures = []

    print("音色总数: %d（旗舰 %d）" % (total, sum(1 for v in voices if v["tier"] == "premium")))

    # 1) 每个分类的命中数 + 每个分类都必须能查出数据且分页不越界
    print("\n%-18s %8s %8s %6s" % ("分类", "命中", "分页和", "状态"))
    for cat in CATEGORIES:
        pred = predicate_for(cat)
        n = conn.execute("SELECT COUNT(*) FROM voices WHERE %s" % pred).fetchone()[0]

        # 模拟分页：pageSize=16 逐页取，校验总数一致
        page_sum, page, size = 0, 0, 16
        while True:
            rows = conn.execute(
                "SELECT key FROM voices WHERE %s LIMIT ? OFFSET ?" % pred, (size, page * size)
            ).fetchall()
            if not rows:
                break
            page_sum += len(rows)
            page += 1
            if page > 200:
                failures.append("%s: 分页未终止" % cat)
                break

        ok = (n == page_sum)
        if n == 0:
            failures.append("%s: 命中 0 条" % cat)
        if not ok:
            failures.append("%s: 总数 %d != 分页和 %d" % (cat, n, page_sum))
        print("%-18s %8d %8d %6s" % (cat, n, page_sum, "OK" if ok and n > 0 else "FAIL"))

    # 2) 场景分类之和应等于总数（每个音色恰好一个场景）
    scene_sum = sum(
        conn.execute("SELECT COUNT(*) FROM voices WHERE %s" % predicate_for(c)).fetchone()[0]
        for c in CATEGORIES if c.startswith("scene_")
    )
    print("\n场景分类命中之和 %d vs 总数 %d -> %s" % (scene_sum, total, "OK" if scene_sum == total else "FAIL"))
    if scene_sum != total:
        failures.append("场景分类之和 %d != 总数 %d" % (scene_sum, total))

    # 3) 语言分类之和应等于总数
    lang_sum = conn.execute(
        "SELECT COUNT(*) FROM voices WHERE lang_code IN ('zh','en')"
    ).fetchone()[0]
    print("语言分类命中之和 %d vs 总数 %d -> %s" % (lang_sum, total, "OK" if lang_sum == total else "FAIL"))
    if lang_sum != total:
        failures.append("语言分类之和 %d != 总数 %d" % (lang_sum, total))

    # 4) 年龄分类之和
    age_sum = sum(
        conn.execute("SELECT COUNT(*) FROM voices WHERE %s" % predicate_for(c)).fetchone()[0]
        for c in CATEGORIES if c.startswith("age_")
    )
    print("年龄分类命中之和 %d vs 总数 %d -> %s" % (age_sum, total, "OK" if age_sum == total else "FAIL"))
    if age_sum != total:
        failures.append("年龄分类之和 %d != 总数 %d" % (age_sum, total))

    # 5) 双语搜索
    # 复刻 VoiceService.searchPredicate：名字/描述走 LIKE，
    # 场景/语种把「当前语言下名称命中关键词」的 code 展开成 IN。
    print("\n--- 搜索（分别模拟中文界面 / 英文界面）---")
    for ui, _label in (("zh", "中文界面"), ("en", "英文界面")):
        print("  [%s]" % _label)
        for needle, desc in SEARCH_CASES[ui]:
            like = "%%%s%%" % needle
            sql = ("SELECT COUNT(*) FROM voices WHERE name LIKE ? OR name_en LIKE ?"
                   " OR desc LIKE ? OR desc_en LIKE ?")
            args = [like, like, like, like]

            idx = {"zh": 0, "en": 1}[ui]
            scenes = [code for code, names in SCENE_NAMES.items() if needle.lower() in names[idx].lower()]
            if scenes:
                sql += " OR scene_key IN (%s)" % ",".join("?" * len(scenes))
                args += scenes
            langs = [code for code, names in LANG_NAMES.items() if needle.lower() in names[idx].lower()]
            if langs:
                sql += " OR lang_code IN (%s)" % ",".join("?" * len(langs))
                args += langs

            n = conn.execute(sql, args).fetchone()[0]
            if n == 0:
                failures.append("[%s] 搜索 %r 命中 0 条" % (_label, needle))
            print("    %-14s %-16s 命中 %3d  %s" % (needle, desc, n, "OK" if n > 0 else "FAIL"))

    # 6) 旗舰默认收藏
    fav = conn.execute("SELECT COUNT(*) FROM voices WHERE tier='premium' AND is_favorite=1").fetchone()[0]
    print("\n旗舰默认收藏 %d / 2 -> %s" % (fav, "OK" if fav == 2 else "FAIL"))
    if fav != 2:
        failures.append("旗舰默认收藏 %d != 2" % fav)

    # 7) 英文名唯一
    uniq = conn.execute("SELECT COUNT(DISTINCT name_en) FROM voices").fetchone()[0]
    print("英文名唯一数 %d / %d -> %s" % (uniq, total, "OK" if uniq == total else "FAIL"))
    if uniq != total:
        failures.append("英文名不唯一：%d / %d" % (uniq, total))

    print("\n" + ("=" * 46))
    if failures:
        print("FAILED (%d):" % len(failures))
        for f in failures:
            print("  - " + f)
        return 1
    print("ALL PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
