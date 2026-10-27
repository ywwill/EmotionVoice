#!/usr/bin/env python3
"""把 iOS/ 下的新文件 + 复用的既有逻辑文件挂进 iOSEmora target。

- 新增 iOS/*.swift：建 PBXFileReference（按目录分组）+ PBXBuildFile，加进 Sources
- 复用既有文件：直接复用 Emora target 里已有的 fileRef，新建 PBXBuildFile，加进 Sources
- SPM 依赖：SQLite / KeychainSwift / Supabase 六个 product 挂到 iOSEmora
- Resources：把 Emora 的音色资源（json / m4a / lproj）整套复制过来

幂等：重复执行不会重复添加。
"""

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBX = os.path.join(ROOT, "EmotionVoice", "EmotionVoice.xcodeproj", "project.pbxproj")
IOS_DIR = os.path.join(ROOT, "iOS")

IOS_TARGET = "6F3AE799309055CE007975DD"
IOS_SOURCES = "6F3AE796309055CE007975DD"
IOS_FRAMEWORKS = "6F3AE797309055CE007975DD"
IOS_RESOURCES = "6F3AE798309055CE007975DD"
EMORA_SOURCES = "6FEE97E7302705C600C39C26"
EMORA_RESOURCES = "6FEE97E9302705C600C39C26"
ROOT_GROUP = "6FEE97E2302705C600C39C26"

# 复用进 iOS target 的既有逻辑文件（按 basename 匹配）
REUSED = [
    "DatabaseManager.swift",
    "AudioDuration.swift",
    "Formatters.swift",
    "String+Extension.swift",
    "Const.swift",
    "Func.swift",
    "AudioItem.swift",
    "BasicVoiceTemplate.swift",
    "VoiceCatalog.swift",
    "Constants.swift",
    "ConsumptionRecord.swift",
    "PurchaseRecord.swift",
    "Voice.swift",
    "StoreKitManager.swift",
    "CreditManager.swift",
    "DeviceIdentifier.swift",
    "AudioPreviewPlayer.swift",
    "BailianTTSService.swift",
    "BasicVoiceLoader.swift",
    "CreditsService.swift",
    "ProjectService.swift",
    "AudioConcatenator.swift",
    "RegionConfig.swift",
    "TTSEndpoint.swift",
    "VoiceService.swift",
    "AppState.swift",
    "HistoryViewModel.swift",
    "VoicesLibraryViewModel.swift",
    "VoiceStudioViewModel.swift",
    "SupabaseManager.swift",
    "TTSContentItem.swift",
    "DataReceiveGridView.swift",
    "FlowLayout.swift",
    "AppColor.swift",
    "AppFont.swift",
    "AppRadius.swift",
    "View+Extension.swift",
    "TextSplitter.swift",
    "DeviceInfo.swift",
    "UserCreditsModel.swift",
]

# 要挂到 iOSEmora 的 SPM product（不含 KeyboardShortcuts —— 那是 macOS 快捷键专用）
SPM_PRODUCT_NAMES = [
    "KeychainSwift",
    "SQLite",
    "Storage",
    "Functions",
    "Supabase",
    "Realtime",
    "Auth",
    "PostgREST",
]


def spm_products(text):
    """从 Emora 的 Frameworks 阶段反查 SPM product 依赖的 ID。

    ⚠️ 坑：Frameworks 里的条目是 PBXBuildFile，它里面的 productRef 才指向
    XCSwiftPackageProductDependency。两者 ID 相邻但不同（Supabase 的 buildFile
    是 …84、product 是 …83），手写常量极易错位；一旦写错，Xcode 会在
    `PBXTarget.pifRepresentation` 里崩成
    `-[PBXBuildFile productName]: unrecognized selector sent to instance`。
    所以这里一律动态反查，不写死 ID。
    """
    refs = {}
    for m in re.finditer(r"\{isa = PBXBuildFile; productRef = ([0-9A-F]{24}) /\* (.+?) \*/; \};",
                         text):
        refs[m.group(2)] = m.group(1)
    out = []
    for name in SPM_PRODUCT_NAMES:
        pid = refs.get(name)
        if pid is None:
            sys.exit("Emora Frameworks 里找不到 SPM product：%s" % name)
        if not re.search(r"%s /\* %s \*/ = \{\s*isa = XCSwiftPackageProductDependency;" % (pid, name),
                         text):
            sys.exit("%s 的 productRef %s 不是 XCSwiftPackageProductDependency" % (name, pid))
        out.append((pid, name))
    return out

_counter = [0]


def new_id(prefix="7A10"):
    _counter[0] += 1
    return "%s%020X" % (prefix, _counter[0])


def section(text, name):
    """取出 `/* Begin <name> section */ ... /* End <name> section */` 之间的内容"""
    m = re.search(r"/\* Begin %s section \*/\n(.*?)/\* End %s section \*/\n" % (name, name),
                  text, re.S)
    if not m:
        sys.exit("找不到 %s section" % name)
    return m.group(1), m.start(1), m.end(1)


def body_sep(body):
    """phase 的 files 块末尾没有换行，追加前要补一个"""
    return "" if body.endswith("\n") else "\n"


def phase_files(text, phase_id):
    r"""取出某个 build phase 的 files 列表（返回 body + 在全文中的起止位置）。

    ⚠️ 不能只用 `files = \(\n(.*?)\n\s*\);` 全局搜索：空 phase（`files = (\n\t\t\t);`）
    根本没有第二个换行，`.*?` 会一路跨到**下一个** phase 的 `);` 上，
    把内容插到错误的 target 里。所以先把整个 phase 对象切出来，再在块内匹配。
    """
    head = re.search(r"%s /\* \w+ \*/ = \{" % phase_id, text)
    if not head:
        sys.exit("找不到 phase %s" % phase_id)
    end = text.index("\n\t\t};", head.start())
    block = text[head.start():end]
    m = re.search(r"files = \(\n?(.*?)\n?\s*\);", block, re.S)
    if not m:
        sys.exit("phase %s 里找不到 files" % phase_id)
    return m.group(1), head.start() + m.start(1), head.start() + m.end(1)


def main():
    text = open(PBX, encoding="utf-8").read()

    # ---------- 1. 既有 build file：comment(basename) -> buildFileID ----------
    bf_sec, _, _ = section(text, "PBXBuildFile")
    existing_bf = {}
    for m in re.finditer(r"^\t\t([0-9A-F]{24}) /\* (.+?) in (Sources|Resources|Frameworks) \*/ = \{isa = PBXBuildFile; fileRef = ([0-9A-F]{24})",
                         bf_sec, re.M):
        existing_bf[(m.group(2), m.group(3))] = m.group(1)

    # fileRef -> path（用于后面给新文件定位）
    fr_sec, _, _ = section(text, "PBXFileReference")
    filerefs = {}
    for m in re.finditer(r"^\t\t([0-9A-F]{24}) /\* (.+?) \*/ = \{isa = PBXFileReference;(.*?)\};",
                         fr_sec, re.M):
        filerefs[m.group(1)] = (m.group(2), m.group(3))

    # ---------- 2. Emora Sources 里挑出要复用的 buildFile ----------
    emora_src, _, _ = phase_files(text, EMORA_SOURCES)
    reuse_ids = []
    missing = []
    for line in emora_src.split("\n"):
        m = re.match(r"\s*([0-9A-F]{24}) /\* (.+?) in Sources \*/,", line)
        if not m:
            continue
        name = m.group(2)
        if name in REUSED:
            reuse_ids.append((m.group(1), name))
    have = {n for _, n in reuse_ids}
    missing = [n for n in REUSED if n not in have]
    if missing:
        sys.exit("Emora 的 Sources 里找不到这些文件：%s" % ", ".join(missing))

    # ⚠️ 新建 target 时 Xcode 已经把 TextSplitter / DatabaseManager / Func / Const
    # 四个文件加进了 iOSEmora 的 Sources（各自独立的 PBXBuildFile）。
    # 再挂一份 Emora 的 buildFile 会让同一份源码被编译两次 → duplicate symbol。
    ios_src_now, _, _ = phase_files(text, IOS_SOURCES)
    already = {n for n in re.findall(r"/\* (\S+\.swift) in Sources \*/", ios_src_now)}
    skipped = [n for n in have if n in already]
    reuse_ids = [(i, n) for i, n in reuse_ids if n not in already]
    if skipped:
        print("   （已在 iOSEmora Sources 中，跳过：%s）" % ", ".join(sorted(skipped)))

    # ---------- 3. iOS/ 下的新文件 ----------
    ios_files = []
    for dirpath, _, filenames in os.walk(IOS_DIR):
        for fn in sorted(filenames):
            if fn.endswith(".swift"):
                rel = os.path.relpath(os.path.join(dirpath, fn), IOS_DIR)
                ios_files.append(rel)
    ios_files.sort()

    # ---------- 4. 组装新增的 PBXFileReference / PBXBuildFile / Group ----------
    new_fr_lines = []
    new_bf_lines = []
    new_bf_ids = []

    # iOS 根 group
    ios_group_id = new_id()
    # 子目录 group：path -> group id
    group_ids = {"": ios_group_id}
    # group_id -> children 行
    children = {ios_group_id: []}

    def ensure_group(rel_dir):
        """按 'App' / 'Views/Studio' 这样的相对目录建好 group 链"""
        if rel_dir in group_ids:
            return group_ids[rel_dir]
        parts = rel_dir.split(os.sep)
        parent = ""
        cur = ""
        for p in parts:
            cur = p if not cur else cur + os.sep + p
            if cur not in group_ids:
                gid = new_id()
                group_ids[cur] = gid
                children[gid] = []
                children[group_ids[parent]].append((gid, p))
            parent = cur
        return group_ids[rel_dir]

    for rel in ios_files:
        name = os.path.basename(rel)
        rel_dir = os.path.dirname(rel)
        gid = ensure_group(rel_dir)
        fr_id = new_id()
        new_fr_lines.append(
            "\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = %s; sourceTree = \"<group>\"; };"
            % (fr_id, name, name)
        )
        children[gid].append((fr_id, name))
        bf_id = new_id()
        new_bf_lines.append(
            "\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
            % (bf_id, name, fr_id, name)
        )
        new_bf_ids.append((bf_id, name))

    # group 定义（叶子在前，保证可读；pbxproj 不要求顺序）
    group_lines = []
    for rel_dir, gid in sorted(group_ids.items(), key=lambda kv: kv[0]):
        if rel_dir == "":
            group_lines.append(
                "\t\t%s /* iOS */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\n\t\t\t);\n\t\t\tname = iOS;\n\t\t\tpath = ../iOS;\n\t\t\tsourceTree = \"<group>\";\n\t\t};"
                % (gid, "\n".join("\t\t\t\t%s /* %s */," % (c, n) for c, n in children[gid]))
            )
        else:
            group_lines.append(
                "\t\t%s /* %s */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\n\t\t\t);\n\t\t\tpath = %s;\n\t\t\tsourceTree = \"<group>\";\n\t\t};"
                % (gid, os.path.basename(rel_dir),
                   "\n".join("\t\t\t\t%s /* %s */," % (c, n) for c, n in children[gid]),
                   os.path.basename(rel_dir))
            )

    # ---------- 5. 写回 ----------
    # 5.1 PBXBuildFile
    start = text.index("/* Begin PBXBuildFile section */") + len("/* Begin PBXBuildFile section */\n")
    ins = "".join(l + "\n" for l in new_bf_lines)
    text = text[:start] + ins + text[start:]

    # 5.2 PBXFileReference
    start = text.index("/* Begin PBXFileReference section */") + len("/* Begin PBXFileReference section */\n")
    ins = "".join(l + "\n" for l in new_fr_lines)
    text = text[:start] + ins + text[start:]

    # 5.3 PBXGroup：追加新 group + 挂到根 group
    start = text.index("/* End PBXGroup section */")
    ins = "".join(l + "\n" for l in group_lines)
    text = text[:start] + ins + text[start:]
    # 根 group children 里加 iOS
    text = text.replace(
        "\t\t\t\t6F3AE7A8309055FE007975DD /* iOSEmora */,\n",
        "\t\t\t\t6F3AE7A8309055FE007975DD /* iOSEmora */,\n\t\t\t\t%s /* iOS */,\n" % ios_group_id,
        1,
    )

    # 5.4 iOSEmora Sources
    body, s, e = phase_files(text, IOS_SOURCES)
    add = ""
    for bf_id, name in reuse_ids + new_bf_ids:
        line = "\t\t\t\t%s /* %s in Sources */,\n" % (bf_id, name)
        if line in body:
            continue
        add += line
    text = text[:s] + body + body_sep(body) + add + text[e:]

    # 5.5 iOSEmora Frameworks（SPM product）
    #
    # ⚠️ Frameworks 里放的是 PBXBuildFile（productRef 指向 XCSwiftPackageProductDependency），
    # 不能直接用 product 依赖的 ID —— 那是 target 的 packageProductDependencies 用的。
    # 每个 target 各建自己的 PBXBuildFile。
    products = spm_products(text)
    fw_bf_lines = []
    fw_bf_ids = []
    for pid, pname in products:
        bf_id = new_id()
        fw_bf_lines.append(
            "\t\t%s /* %s in Frameworks */ = {isa = PBXBuildFile; productRef = %s /* %s */; };"
            % (bf_id, pname, pid, pname)
        )
        fw_bf_ids.append((bf_id, pname))
    start = text.index("/* Begin PBXBuildFile section */") + len("/* Begin PBXBuildFile section */\n")
    ins = "".join(l + "\n" for l in fw_bf_lines)
    text = text[:start] + ins + text[start:]

    body, s, e = phase_files(text, IOS_FRAMEWORKS)
    add = ""
    for bf_id, pname in fw_bf_ids:
        line = "\t\t\t\t%s /* %s in Frameworks */,\n" % (bf_id, pname)
        add += line
    text = text[:s] + body + body_sep(body) + add + text[e:]

    # 5.6 target 的 packageProductDependencies
    m = re.search(r"(%s /\* iOSEmora \*/ = \{.*?packageProductDependencies = \(\n)(.*?)(^\t\t\t\);)" % IOS_TARGET,
                  text, re.S | re.M)
    if not m:
        sys.exit("找不到 iOSEmora target 的 packageProductDependencies")
    block = m.group(2)
    add = ""
    for pid, pname in products:
        line = "\t\t\t\t%s /* %s */,\n" % (pid, pname)
        if line in block:
            continue
        add += line
    text = text[:m.start(2)] + block + add + text[m.start(2):]

    # 5.7 iOSEmora Resources：复制 Emora 的音色资源（除 Emora 自己的 Assets.xcassets）
    emora_res, _, _ = phase_files(text, EMORA_RESOURCES)
    copy_ids = []
    for line in emora_res.split("\n"):
        m2 = re.match(r"\s*([0-9A-F]{24}) /\* (.+?) in Resources \*/,", line)
        if not m2:
            continue
        if m2.group(2) == "Assets.xcassets":
            continue   # iOSEmora 用自己的 Assets.xcassets
        copy_ids.append((m2.group(1), m2.group(2)))
    body, s, e = phase_files(text, IOS_RESOURCES)
    add = ""
    for rid, rname in copy_ids:
        line = "\t\t\t\t%s /* %s in Resources */,\n" % (rid, rname)
        if line in body:
            continue
        add += line
    text = text[:s] + body + body_sep(body) + add + text[e:]

    open(PBX, "w", encoding="utf-8").write(text)
    print("✅ 已写入 project.pbxproj")
    print("   iOS 新增源文件：%d" % len(new_bf_ids))
    print("   复用既有文件：%d" % len(reuse_ids))
    print("   SPM product：%d" % len(products))
    print("   Resources：%d" % len(copy_ids))


if __name__ == "__main__":
    main()
