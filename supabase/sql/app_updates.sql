-- ============================================================================
-- app_updates —— App「检查更新」的唯一数据源
--
-- 一个平台一行（platform 主键）：ios / macos。
-- 客户端只读（anon select），写入一律在 Dashboard 里手动改，避免被客户端篡改。
--
-- 执行方式：Supabase Dashboard → SQL Editor → 整段粘贴执行（可重复执行）。
-- ============================================================================

-- MARK: 建表
create table if not exists public.app_updates (
    -- 'ios' | 'macos'：两个平台各一行，版本号独立
    platform      text        primary key check (platform in ('ios', 'macos')),
    -- 线上已上架的版本号，只填 x.y.z（不要带 (build) 后缀，客户端按数字段比较）
    version       text        not null,
    -- true：启动即弹不可关闭的弹窗，直到用户去 App Store 更新
    force_update  boolean     not null default false,
    -- 更新内容，jsonb：{"zh-Hans": ["…"], "zh-HK": ["…"], "en": ["…"]}
    -- 也接受 ["…"]（单语言）或 {"zh-Hans": "…\n…"}（换行分段）
    release_notes jsonb       not null default '{}'::jsonb,
    updated_at    timestamptz not null default now()
);

comment on table public.app_updates is 'App 版本发布信息，客户端启动 / 手动检查更新时读取';

-- MARK: 权限（RLS：仅匿名只读，不开放 insert/update/delete）
alter table public.app_updates enable row level security;

drop policy if exists "app_updates anon select" on public.app_updates;
create policy "app_updates anon select" on public.app_updates
    for select
    to anon, authenticated
    using (true);

-- MARK: updated_at 自动维护
create or replace function public.app_updates_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists app_updates_touch on public.app_updates;
create trigger app_updates_touch
    before update on public.app_updates
    for each row
    execute function public.app_updates_touch_updated_at();

-- MARK: 初始数据
-- ⚠️ 只能填「已经上架」的版本号。
--    填了还没上架的版本，会导致所有用户都被提示更新却跳不到新版本。
insert into public.app_updates (platform, version, force_update, release_notes) values
    ('ios', '1.1.1', false, '{
        "zh-Hans": ["历史记录支持批量管理", "修复播放中断后进度不准的问题"],
        "zh-HK":   ["歷史記錄支援批量管理", "修正播放中斷後進度不準的問題"],
        "en":      ["Batch management in History", "Fixed inaccurate progress after playback was interrupted"]
    }'::jsonb),
    ('macos', '1.2.0', false, '{
        "zh-Hans": ["关闭生成弹窗后仍可在后台接收结果", "优化音色库加载速度"],
        "zh-HK":   ["關閉生成彈窗後仍可在背景接收結果", "優化音色庫載入速度"],
        "en":      ["Generation keeps running after the dialog is closed", "Faster voice library loading"]
    }'::jsonb)
on conflict (platform) do nothing;

-- ============================================================================
-- 日常发布流程（手动执行其中一条）
--
--   update public.app_updates
--      set version = '1.2.0',
--          force_update = false,
--          release_notes = '{"zh-Hans": ["…"], "zh-HK": ["…"], "en": ["…"]}'::jsonb
--    where platform = 'ios';
--
--   -- 紧急修复：强制更新
--   update public.app_updates set version = '1.2.1', force_update = true where platform = 'ios';
-- ============================================================================
