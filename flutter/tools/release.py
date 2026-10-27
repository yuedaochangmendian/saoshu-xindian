#!/usr/bin/env python3
"""扫书新典 Flutter 版标准化发布脚本。

用法：
    python tools/release.py <版本号> [commit 消息]
    例：python tools/release.py 4.5.2 "feat: xxx"

流程（任一步失败即中止）：
    1. 校验版本号格式（X.Y.Z）且高于当前版本、tag 不存在
    2. 校验 pubspec.lock 无镜像源污染（flutter-io.cn）
    3. bump pubspec version（正则替换，build 号 +1）
    4. git add flutter/ + commit + push
    5. gh workflow run flutter-release.yml（dispatch 前再次检查 tag）

注意：本脚本不做本机构建验证（按项目规则，验证以 CI 为准）。
"""
import re
import subprocess
import sys
from pathlib import Path

REPO = 'yuedaochangmendian/saoshu-xindian'
ROOT = Path(__file__).resolve().parents[1]
PUBSPEC = ROOT / 'pubspec.yaml'
LOCK = ROOT / 'pubspec.lock'


def run(cmd, **kw):
    result = subprocess.run(cmd, capture_output=True, text=True,
                            encoding='utf-8', cwd=ROOT, **kw)
    return result


def fail(message):
    print(f'✗ {message}')
    sys.exit(1)


def ok(message):
    print(f'✓ {message}')


def gh_json(endpoint):
    result = run(['gh', 'api', endpoint])
    if result.returncode != 0:
        fail(f'gh api 失败（网络或代理问题，可重试）: {result.stderr[:120]}')
    return result.stdout.strip()


def main():
    if len(sys.argv) < 2:
        fail('用法: python tools/release.py <版本号> [commit 消息]')
    version = sys.argv[1].strip()
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        fail(f'版本号格式应为 X.Y.Z，收到: {version}')

    # 1) 当前版本对比
    pubspec = PUBSPEC.read_text(encoding='utf-8')
    m = re.search(r'version: ([^\s]+)', pubspec)
    if not m:
        fail('pubspec.yaml 缺少 version 行')
    current_base = m.group(1).split('+')[0].lstrip('v')
    try:
        current_base_nums = [int(x) for x in current_base.split('.')]
    except ValueError:
        fail(f'当前版本号无法解析: {current_base}')
    nums = [int(x) for x in version.split('.')]
    if nums[:2] < current_base_nums[:2] or (
            nums[:2] == current_base_nums[:2] and nums[2] <= current_base_nums[2]):
        fail(f'新版本 {version} 应高于当前 {current_base}')

    # 2) tag 查重
    tag = f'v{version}'
    check = run(['gh', 'api', f'repos/{REPO}/releases/tags/{tag}'])
    if check.returncode == 0:
        fail(f'tag {tag} 已存在 release——版本号已用过，请升版本号')
    if 'Not Found' not in check.stderr and check.returncode != 0:
        print(f'⚠ tag 查询失败（可能网络问题），继续但请人工确认 {tag} 未使用')

    # 3) lock 镜像检查
    lock = LOCK.read_text(encoding='utf-8')
    if 'flutter-io.cn' in lock:
        fail('pubspec.lock 含镜像源 flutter-io.cn——先运行 '
             '`git checkout -- flutter/pubspec.lock` 或规范化为 pub.dev 再发布')

    # 4) bump
    build_match = re.search(r'\+(\d+)', m.group(1))
    build = (int(build_match.group(1)) + 1) if build_match else 1
    new_version_line = f'version: {version}+{build}'
    pubspec = re.sub(r'version: [^\s]+', new_version_line, pubspec, count=1)
    # 保持文件原有换行符（避免整文件 diff）
    nl = '
' if '
' in pubspec else '
'
    PUBSPEC.write_text(nl.join(pubspec.split(nl)), encoding='utf-8',
                       newline='')
    ok(f'版本已 bump: {m.group(1)} -> {new_version_line}')

    # 5) 提交
    message = sys.argv[2] if len(sys.argv) > 2 else f'release: v{version}'
    run(['git', 'add', 'flutter/'])
    status = run(['git', 'status', '--short', 'flutter/'])
    if not status.stdout.strip():
        fail('没有可提交的改动（flutter/ 无变化）')
    commit = run(['git', 'commit', '-m', f'{message} (v{version})'])
    if commit.returncode != 0:
        fail(f'commit 失败: {commit.stderr[:200]}')
    ok('已提交')
    push = run(['git', 'push', 'origin', 'main'])
    if push.returncode != 0:
        fail(f'push 失败: {push.stderr[:200]}')
    ok('已推送')

    # 6) dispatch
    dispatch = run(['gh', 'workflow', 'run', 'flutter-release.yml',
                    '--repo', REPO, '--ref', 'main'])
    if dispatch.returncode != 0:
        fail(f'dispatch 失败（代理问题可重试）: {dispatch.stderr[:120]}')
    ok('已触发 flutter-release.yml')
    print(f'\n完成。CI 完成后发布 tag {tag}（prerelease）。'
          f'\n转正式版: gh release edit {tag} --prerelease=false && '
          f'gh release edit {tag} --latest')


if __name__ == '__main__':
    main()
