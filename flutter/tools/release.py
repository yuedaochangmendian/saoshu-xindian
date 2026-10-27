#!/usr/bin/env python3
"""扫书新典 Flutter 版标准化发布脚本。

用法：
    python tools/release.py <版本号> [commit 消息]
    例：python tools/release.py 4.5.2 "feat: xxx"

流程（任一步失败即中止）：
    1. 校验版本号格式（X.Y.Z）且高于当前版本、tag 不存在
    2. 校验 pubspec.lock 无镜像源污染（flutter-io.cn）
    3. bump pubspec version（正则替换，build 号 +1，保持原换行符）
    4. git add flutter/ + commit + push
    5. gh workflow run flutter-release.yml（dispatch 前再次检查 tag）

注意：本脚本不做本机构建验证（按项目规则，验证以 CI 为准）。
"""
import re
import subprocess
import sys
from pathlib import Path

REPO = 'yuedaochangmendian/saoshu-xindian'
ROOT = Path(__file__).resolve().parents[2]  # 仓库根 work/app
PUBSPEC = ROOT / 'flutter' / 'pubspec.yaml'
LOCK = ROOT / 'flutter' / 'pubspec.lock'


def run(cmd, **kw):
    result = subprocess.run(cmd, capture_output=True, text=True,
                            encoding='utf-8', cwd=ROOT, **kw)
    return result


def fail(message):
    print(f'FAIL: {message}')
    sys.exit(1)


def ok(message):
    print(f'OK: {message}')


def main():
    if len(sys.argv) < 2:
        fail('usage: python tools/release.py <version> [commit message]')
    version = sys.argv[1].strip()
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        fail(f'version format should be X.Y.Z, got: {version}')

    # 1) 当前版本对比
    pubspec = PUBSPEC.read_text(encoding='utf-8')
    m = re.search(r'version: ([^\s]+)', pubspec)
    if not m:
        fail('pubspec.yaml missing version line')
    current_base = m.group(1).split('+')[0].lstrip('v')
    current_nums = [int(x) for x in current_base.split('.')]
    nums = [int(x) for x in version.split('.')]
    if nums <= current_nums:
        fail(f'new version {version} must be higher than current {current_base}')

    # 2) tag 查重
    tag = f'v{version}'
    check = run(['gh', 'api', f'repos/{REPO}/releases/tags/{tag}'])
    if check.returncode == 0:
        fail(f'release with tag {tag} already exists - use a higher version')
    print(f'tag {tag} available')

    # 3) lock 镜像检查
    lock = LOCK.read_text(encoding='utf-8')
    if 'flutter-io.cn' in lock:
        fail('pubspec.lock contains mirror flutter-io.cn - restore it first: '
             'git checkout -- flutter/pubspec.lock')

    # 4) bump（保持原换行符）
    build_match = re.search(r'\+(\d+)', m.group(1))
    build = (int(build_match.group(1)) + 1) if build_match else 1
    new_version_line = f'version: {version}+{build}'
    pubspec = re.sub(r'version: [^\s]+', new_version_line, pubspec, count=1)
    nl = '\r\n' if '\r\n' in pubspec else '\n'
    PUBSPEC.write_bytes(nl.join(pubspec.split(nl)).encode('utf-8'))
    ok(f'version bumped: {m.group(1)} -> {new_version_line}')

    # 5) 提交
    message = sys.argv[2] if len(sys.argv) > 2 else f'release: v{version}'
    run(['git', 'add', 'flutter/'])
    status = run(['git', 'status', '--short', '--', 'flutter/'])
    if not status.stdout.strip():
        fail('no changes to commit under flutter/')
    commit = run(['git', 'commit', '-m', f'{message} (v{version})'])
    if commit.returncode != 0:
        fail(f'commit failed: {commit.stderr[:200]}')
    ok('committed')
    push = run(['git', 'push', 'origin', 'main'])
    if push.returncode != 0:
        fail(f'push failed: {push.stderr[:200]}')
    ok('pushed')

    # 6) dispatch
    dispatch = run(['gh', 'workflow', 'run', 'flutter-release.yml',
                    '--repo', REPO, '--ref', 'main'])
    if dispatch.returncode != 0:
        fail(f'dispatch failed: {dispatch.stderr[:120]}')
    ok('flutter-release.yml dispatched')
    print(f'\nDone. CI will publish tag {tag} (prerelease).')


if __name__ == '__main__':
    main()
