import argparse
import json
import re
import sqlite3
import unicodedata
from pathlib import Path

from dedupe_app_content import rebuild_books


ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "app" / "src" / "main" / "assets" / "saoshu.db"
REPORT_PATH = ROOT / "build" / "reports" / "meaningless_reply_filter_report.json"

SHORT_FILLERS = {
    "不多", "好的", "我顶", "插眼", "马克", "刘明", "留名", "加油",
    "是", "强", "一样", "可以", "不错", "哈哈", "来了", "收到", "辛苦",
    "沙发", "前排", "路过", "谢谢", "感谢", "快更", "速更", "更了",
    "更啦", "顶", "支持", "确实", "cy", "dd", "ty", "cry", "mark",
    "ok", "嗯", "哦", "啊", "好", "谢排", "谢扫", "蟹排", "蟹扫",
}

MARKER_PREFIX = re.compile(
    r"^(?:cy|cry|dd|ty|mark|插眼|马克|留名|刘明|顶|我顶|也顶|"
    r"支持|点赞|打卡|签到|沙发|前排|路过)",
    re.I,
)

COURTESY_PREFIX = re.compile(
    r"^(?:感谢|谢谢|多谢|支持|顶|楼主|辛苦(?:了|大佬)?|加油|"
    r"好帖|好贴|好的|来了|收到)[，,。.!！:：\s]*",
)

GENERIC_TAIL = re.compile(
    r"^(?:分享|推荐|扫书|扫|排雷|排|楼主|大佬|好人|一生平安|"
    r"收藏了?|求别删帖|感谢|谢谢|可以+|我去?瞅瞅|去?看看|来+|"
    r"了+|啊+|呀+|呢+)$"
)

EXACT_LOW_VALUE = re.compile(
    r"^(?:在哪看|这是啥小说平台|这是啥平台|下面呢|多来点|再来点|"
    r"看高清大图打开贴吧app|好帖啊收藏了求别删帖|辛苦了|来了来了)$"
)


def normalized(value):
    text = unicodedata.normalize("NFKC", value or "").lower().strip()
    text = re.sub(r"^(?:回复|楼中楼)\s*[:：]\s*", "", text)
    text = re.sub(r"看高清大图[，,]?\s*打开贴吧app", "", text, flags=re.I)
    text = re.sub(r"https?://\S+", "", text)
    text = text.replace("\u200b", "").replace("\xa0", " ")
    return re.sub(r"[\W_]+", "", text, flags=re.UNICODE)


def is_meaningless(content):
    text = normalized(content)
    if not text or len(text) <= 1:
        return True
    if len(text) == 2:
        return text in SHORT_FILLERS or bool(re.fullmatch(r"[a-z0-9]{1,3}", text))
    if len(text) <= 12 and (EXACT_LOW_VALUE.fullmatch(text) or MARKER_PREFIX.match(text)):
        return True
    tail = COURTESY_PREFIX.sub("", text)
    if tail != text and (not tail or GENERIC_TAIL.fullmatch(tail)):
        return True
    return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    db = sqlite3.connect(DB_PATH)
    removed = []
    for row in db.execute("SELECT id,title,content,category FROM documents ORDER BY id"):
        if is_meaningless(row[2]):
            removed.append({
                "id": row[0],
                "title": row[1],
                "content": row[2],
                "category": row[3],
            })

    report = {
        "policy": "remove empty, pure marker, courtesy-only, and sub-8-character low-information replies",
        "removed_count": len(removed),
        "remaining_count": 73457 - len(removed),
        "applied": bool(args.apply),
        "removed": removed,
    }
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps({k: v for k, v in report.items() if k != "removed"},
                     ensure_ascii=False, indent=2))
    if not args.apply:
        db.close()
        return

    db.execute("BEGIN")
    try:
        for item in removed:
            db.execute("DELETE FROM document_sources WHERE document_id=?", (item["id"],))
            db.execute("DELETE FROM documents WHERE id=?", (item["id"],))
        rebuild_books(db)
        db.execute("DELETE FROM categories")
        db.executemany(
            "INSERT INTO categories(name,count) VALUES(?,?)",
            db.execute(
                "SELECT category,count(*) FROM documents GROUP BY category"
            ).fetchall(),
        )
        document_count = db.execute("SELECT count(*) FROM documents").fetchone()[0]
        book_count = db.execute("SELECT count(*) FROM books").fetchone()[0]
        source_count = db.execute("SELECT count(*) FROM document_sources").fetchone()[0]
        for key, value in (
            ("documents", document_count),
            ("books", book_count),
            ("source_rows", source_count),
            ("removed_meaningless", len(removed)),
        ):
            db.execute(
                "INSERT OR REPLACE INTO meta(key,value) VALUES(?,?)",
                (key, str(value)),
            )
        db.commit()
    except Exception:
        db.rollback()
        raise

    integrity = db.execute("PRAGMA integrity_check").fetchone()[0]
    db.execute("VACUUM")
    db.close()
    report.update({
        "remaining_count": document_count,
        "remaining_books": book_count,
        "remaining_sources": source_count,
        "integrity": integrity,
        "database_bytes": DB_PATH.stat().st_size,
    })
    REPORT_PATH.write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps({k: v for k, v in report.items() if k != "removed"},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
