#!/usr/bin/env bash
#
# 部署 TTS 边缘函数并把密钥写进 Supabase function secrets。
#
# 前置：
#   1) supabase login（需对项目 dpyyhbqqmegencxekkcr 有权限）
#   2) 把 supabase/functions/bailian-tts/.env.example 复制为
#      supabase/functions/.env 并填入真实值（该文件已在 .gitignore 中）
#
set -euo pipefail

PROJECT_REF="dpyyhbqqmegencxekkcr"
FUNCTION_NAME="bailian-tts"

cd "$(dirname "$0")"

if [[ ! -f functions/.env ]]; then
  echo "❌ 缺少 functions/.env（从 functions/bailian-tts/.env.example 复制并填值）"
  exit 1
fi

echo "🔗 关联项目 $PROJECT_REF"
supabase link --project-ref "$PROJECT_REF"

echo "🔐 写入 function secrets"
supabase secrets set --project-ref "$PROJECT_REF" --env-file functions/.env

echo "🚀 部署 $FUNCTION_NAME"
supabase functions deploy "$FUNCTION_NAME" --project-ref "$PROJECT_REF"

echo "✅ 完成。端点："
echo "   wss://$PROJECT_REF.supabase.co/functions/v1/$FUNCTION_NAME?region=CN"
