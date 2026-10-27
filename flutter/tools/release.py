#!/usr/bin/env python3
"""扫书新典 Flutter 版标准化发布脚本。

用法：
    python tools/release.py <版本号> [commit 消息]
    例：python tools/release.py 4.5.2 "feat: xxx"

流程（任一步失败即中止）：
    1. 校验版本号格式（X.Y.Z）且高于当前版本
    2. tag 查重（区分 404 与网络错误；错误重试后仍失败即中止）
    3. 校验 pubspec.lock 无镜像源污染（flutter-io.cn）
    4. bump pubspec version（正则替换，build 号 +1；read_bytes 按原始
       字节原位写回，换行符不可能被规范化——read_text 会把 CRLF 抹成
       LF 令事后检测恒失效，是 v4.6.3 code review 点名的反面教材）
    5. git add flutter/ + commit + push
    6. dispatch 前复查 tag，再 gh workflow run flutter-release.yml

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


def check_tag(tag):
    """tag 查重分型：'exists'=已存在 / 'free'=不存在(404) / 'error'=查询失败。

    gh api 的 TLS 抖动、未登录、rate-limit 与 404 都返回非零码，只凭
    returncode 会把一次网络抖动当成「tag 不存在」放行（v4.5.1 撞 tag
    事故的机制面），因此按输出内容分型，错误重试一次后拒绝猜测。
    """
    last = ''
    for _ in range(2):
        r = run(['gh', 'api', f'repos/{REPO}/releases/tags/{tag}'])
        if r.returncode == 0:
            return 'exists'
        blob = (r.stderr or '') + (r.stdout or '')
        if 'Not Found' in blob or '"404"' in blob or 'HTTP 404' in blob:
            return 'free'
        last = blob[:160]
    print(f'WARN: tag check failed: {last}')
    return 'error'


def main():
    if len(sys.argv) < 2:
        fail('usage: python tools/release.py <version> [commit message]')
    version = sys.argv[1].strip()
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        fail(f'version format should be X.Y.Z, got: {version}')

    # 1) 当前版本对比（read_bytes：原始内容直读，换行与磁盘一致）
    pubspec = PUBSPEC.read_bytes().decode('utf-8')
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
    state = check_tag(tag)
    if state == 'exists':
        fail(f'release with tag {tag} already exists - use a higher version')
    if state == 'error':
        fail('cannot verify tag availability (gh api errors) - '
             'check network/proxy and rerun')
    print(f'tag {tag} available')

    # 3) lock 镜像检查
    lock = LOCK.read_text(encoding='utf-8')
    if 'flutter-io.cn' in lock:
        fail('pubspec.lock contains mirror flutter-io.cn - restore it first: '
             'git checkout -- flutter/pubspec.lock')

    # 4) bump：原始字符串上替换版本行，字节级写回，换行符原样保留
    build_match = re.search(r'\+(\d+)', m.group(1))
    build = (int(build_match.group(1)) + 1) if build_match else 1
    new_version_line = f'version: {version}+{build}'
    new_pubspec = re.sub(r'version: [^\s]+', new_version_line,
                         pubspec, count=1)
    PUBSPEC.write_bytes(new_pubspec.encode('utf-8'))
    ok(f'version bumped: {m.group(1)} -> {new_version_line}')

    # 5) 提交（仅限 main：在别的分支上跑会出现 commit 进分支、
    # push main 却 "up-to-date"、CI 构建到旧版本的静默错位）
    branch = run(['git', 'rev-parse', '--abbrev-ref', 'HEAD'])
    if branch.stdout.strip() != 'main':
        fail(f'current branch is {branch.stdout.strip()!r}, release.py must '
             'run on main')
    message = sys.argv[2] if len(sys.argv) > 2 else f'release: v{version}'
    add = run(['git', 'add', 'flutter/'])
    if add.returncode != 0:
        fail(f'git add failed: {add.stderr[:200]}')
    status = run(['git', 'status', '--short', '--', 'flutter/'])
    if not status.stdout.strip():
        fail('no changes to commit under flutter/')
    # 发布 commit 会吞并 flutter/ 下全部未提交改动——列出来让操作者
    # 在 push 前看见到底带了什么上车。
    print('files in this release commit:')
    print(status.stdout.rstrip())
    commit = run(['git', 'commit', '-m', f'{message} (v{version})'])
    if commit.returncode != 0:
        fail(f'commit failed: {commit.stderr[:200]}')
    ok('committed')
    push = run(['git', 'push', 'origin', 'main'])
    if push.returncode != 0:
        fail(f'push failed: {push.stderr[:200]}')
    ok('pushed')

    # 6) dispatch 前复查 tag（bump→push 窗口期可能已撞车）
    state = check_tag(tag)
    if state != 'free':
        fail(f'tag {tag} re-check before dispatch failed ({state}) - '
             'commit is already pushed, do NOT re-run the script blindly')
    dispatch = run(['gh', 'workflow', 'run', 'flutter-release.yml',
                    '--repo', REPO, '--ref', 'main'])
    if dispatch.returncode != 0:
        fail(f'dispatch failed: {dispatch.stderr[:120]}')
    ok('flutter-release.yml dispatched')
    print(f'\nDone. CI will publish tag {tag} (prerelease).')


if __name__ == '__main__':
    main()
