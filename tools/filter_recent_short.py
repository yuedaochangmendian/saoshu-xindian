import argparse
import json
import re
import sqlite3
import unicodedata
from pathlib import Path

from dedupe_app_content import rebuild_books


ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "app" / "src" / "main" / "assets" / "saoshu.db"
REPORT_PATH = ROOT / "build" / "reports" / "recent_short_filter_report.json"
DEFAULT_CUTOFF = "2026-09-20"
DEFAULT_MIN_CHARS = 50


def effective_length(value):
    text = unicodedata.normalize("NFKC", value or "")
    text = re.sub(r"https?://\S+", "", text)
    text = re.sub(r"看高清大图[，,]?\s*打开贴吧app", "", text, flags=re.I)
    return len(re.sub(r"[\W_]+", "", text, flags=re.UNICODE))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--all-dates", action="store_true")
    parser.add_argument("--min-chars", type=int, default=DEFAULT_MIN_CHARS)
    args = parser.parse_args()
    cutoff = None if args.all_dates else DEFAULT_CUTOFF
    minimum_chars = max(1, args.min_chars)
    db = sqlite3.connect(DB_PATH)
    before = db.execute("SELECT count(*) FROM documents").fetchone()[0]
    removed = []
    query = """
        SELECT id,title,content,published_at,category
          FROM documents
    """
    params = ()
    if cutoff is not None:
        query += " WHERE published_at>=?"
        params = (cutoff,)
    query += " ORDER BY published_at DESC,id DESC"
    for row in db.execute(query, params):
        length = effective_length(row[2])
        if length < minimum_chars:
            removed.append({
                "id": row[0],
                "title": row[1],
                "content": row[2],
                "published_at": row[3],
                "category": row[4],
                "effective_characters": length,
            })
    report = {
        "cutoff": cutoff or "all-dates",
        "minimum_characters": minimum_chars,
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
            removed_key = "removed_short_all" if cutoff is None else "removed_recent_short"
            for key, value in (
                ("documents", document_count),
                ("books", book_count),
                ("source_rows", source_count),
                (removed_key, len(removed)),
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
            "database_bytes": DB_PATH.stat().st_size,
        })
    db.close()
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps({k: v for k, v in report.items() if k != "removed"},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
