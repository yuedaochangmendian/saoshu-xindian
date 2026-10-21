import argparse
import json
import re
import sqlite3
import unicodedata
from pathlib import Path

from dedupe_app_content import rebuild_books


ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "app" / "src" / "main" / "assets" / "saoshu.db"
REPORT_PATH = ROOT / "build" / "reports" / "noise_content_filter_report.json"


def noise_reason(content):
    text = unicodedata.normalize("NFKC", content or "")
    meaningful = "".join(re.findall(r"[A-Za-z0-9\u3400-\u9fff]+", text))
    normalized = re.sub(r"[\W_]+", "", text.lower(), flags=re.UNICODE)
    compact_chars = re.sub(r"\s+", "", text)
    meaningful_ratio = len(meaningful) / max(1, len(compact_chars))
    unique = len(set(meaningful.lower()))
    if not normalized:
        return "no-meaningful-characters"
    if text.count("\ufffd") >= 3:
        return "replacement-characters"
    if len(normalized) >= 6 and unique <= 2:
        return "single-character-repeat"
    if len(text) >= 30 and meaningful_ratio < 0.18:
        return "symbol-heavy"
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    db = sqlite3.connect(DB_PATH)
    before = db.execute("SELECT count(*) FROM documents").fetchone()[0]
    removed = []
    for row in db.execute(
        "SELECT id,title,content,category FROM documents ORDER BY id"
    ):
        reason = noise_reason(row[2])
        if reason:
            removed.append({
                "id": row[0],
                "title": row[1],
                "content": row[2],
                "category": row[3],
                "reason": reason,
            })
    report = {
        "removed_count": len(removed),
        "before_count": before,
        "applied": bool(args.apply),
        "removed": removed,
    }
    if args.apply:
        db.execute("BEGIN")
        try:
            for item in removed:
                db.execute(
                    "DELETE FROM document_sources WHERE document_id=?",
                    (item["id"],),
                )
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
                ("removed_noise", len(removed)),
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
        report.update({
            "remaining_count": document_count,
            "remaining_books": book_count,
            "remaining_sources": source_count,
            "integrity": integrity,
        })
    db.close()
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps({key: value for key, value in report.items() if key != "removed"},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
