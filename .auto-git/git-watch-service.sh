#!/bin/bash
# 研究报告 git 自动提交监听服务

REPO_DIR="/Users/bokaichen/researchStuido"
COMMIT_SCRIPT="$REPO_DIR/.auto-git/git-auto-commit.sh"
LOG_FILE="$REPO_DIR/.auto-git/git-auto-commit.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') - 自动提交服务启动" >> "$LOG_FILE"

# fswatch 监听文件变更，5秒延迟合并事件
/opt/homebrew/bin/fswatch -o \
    --event Created \
    --event Updated \
    --event Removed \
    --latency 5 \
    --exclude ".auto-git" \
    --exclude ".git" \
    "$REPO_DIR" | while read event; do
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 检测到变更，触发提交..." >> "$LOG_FILE"
        "$COMMIT_SCRIPT"
    done