#!/bin/bash
# 研究报告自动提交脚本

REPO_DIR="/Users/bokaichen/researchStuido"
LOG_FILE="$REPO_DIR/.git-auto-commit.log"

# 记录日志
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

cd "$REPO_DIR"

# 检查是否有变更
if git diff --quiet && git diff --staged --quiet; then
    # 检查是否有未追踪的文件
    if [ -z "$(git ls-files --others --exclude-standard)" ]; then
        log "无变更，跳过提交"
        exit 0
    fi
fi

# 添加所有文件
git add -A

# 获取变更摘要
CHANGES=$(git status --short)
CHANGE_COUNT=$(echo "$CHANGES" | wc -l | tr -d ' ')

# 生成提交信息
COMMIT_MSG="自动提交: $CHANGE_COUNT 个文件变更 ($(date '+%Y-%m-%d %H:%M:%S'))"

# 提交
git commit -m "$COMMIT_MSG"

log "已提交: $CHANGES"

# 如果有远程仓库，尝试推送
if git remote | grep -q origin; then
    git push origin HEAD 2>&1 >> "$LOG_FILE" && log "已推送到远程" || log "推送失败"
fi