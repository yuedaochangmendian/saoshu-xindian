import argparse
import difflib
import html
import json
import re
import sqlite3
import unicodedata
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "app" / "src" / "main" / "assets" / "saoshu.db"
REPORT_PATH = ROOT / "build" / "reports" / "content_dedupe_report.json"


def normalized(value):
    text = unicodedata.normalize("NFKC", value or "").lower()
    text = html.unescape(text)
    text = re.sub(r"看高清大图[，,]?\s*打开贴吧app", "", text, flags=re.I)
    text = re.sub(r"https?://\S+", "", text)
    text = re.sub(r"^(回复\s*[:：]\s*)+", "", text)
    return re.sub(r"[\W_]+", "", text, flags=re.UNICODE)


class DisjointSet:
    def __init__(self, values):
        self.parent = {value: value for value in values}

    def find(self, value):
        while self.parent[value] != value:
            self.parent[value] = self.parent[self.parent[value]]
            value = self.parent[value]
        return value

    def union(self, left, right):
        a = self.find(left)
        b = self.find(right)
        if a != b:
            self.parent[b] = a


def compact(value):
    return re.sub(r"[\W_]+", "", normalized(value))


def find_duplicate_groups(db, threshold):
    rows = db.execute(
        """
        SELECT d.id, d.title, d.title_norm, d.content, d.word, d.published_at, d.hot_score,
               d.source_type, d.mentioned_books_json,
               (SELECT count(*) FROM document_sources s
                 WHERE s.document_id=d.id) AS source_count
          FROM documents d
         ORDER BY d.id
        """
    ).fetchall()
    records = {}
    signature_buckets = defaultdict(set)
    literal_duplicates = []
    for row in rows:
        record = {
            "id": row[0],
            "title": row[1],
            "title_norm": row[2],
            "content": row[3],
            "word": row[4],
            "published_at": row[5] or "",
            "hot_score": row[6] or 0,
            "source_type": row[7] or "",
            "mentioned_books_json": row[8] or "[]",
            "source_count": row[9] or 0,
        }
        text = normalized(record["content"])
        record["normalized"] = text
        records[record["id"]] = record
        if len(text) >= 100:
            signature_buckets[("head", text[:160])].add(record["id"])
            signature_buckets[("title", record["title_norm"])].add(record["id"])
            if len(text) >= 300:
                signature_buckets[("tail", text[-160:])].add(record["id"])

    pairs = {}
    for members in signature_buckets.values():
        if len(members) < 2:
            continue
        ordered = sorted(members)
        for index, left_id in enumerate(ordered):
            left = records[left_id]
            for right_id in ordered[index + 1 :]:
                right = records[right_id]
                key = (left_id, right_id)
                if key in pairs:
                    continue
                a = left["normalized"]
                b = right["normalized"]
                if len(a) < len(b) * 0.50 or len(b) < len(a) * 0.50:
                    continue
                matcher = difflib.SequenceMatcher(None, a, b, autojunk=False)
                if matcher.quick_ratio() < threshold:
                    continue
                ratio = matcher.ratio()
                if ratio >= threshold:
                    pairs[key] = round(ratio, 6)

    dsu = DisjointSet(records)
    for left_id, right_id in pairs:
        dsu.union(left_id, right_id)
    grouped = defaultdict(list)
    for record_id in records:
        grouped[dsu.find(record_id)].append(record_id)
    groups = [members for members in grouped.values() if len(members) > 1]
    return records, pairs, groups


def merge_sources(db, src_id, dst_id):
    sources = db.execute(
        """
        SELECT source_kind, source_ref, source_url
          FROM document_sources WHERE document_id=?
         ORDER BY id
        """,
        (src_id,),
    ).fetchall()
    for kind, ref, url in sources:
        exists = db.execute(
            """
            SELECT 1 FROM document_sources
             WHERE document_id=? AND source_kind=?
               AND source_ref=? AND coalesce(source_url,'')=?
             LIMIT 1
            """,
            (dst_id, kind, ref, url or ""),
        ).fetchone()
        if not exists:
            db.execute(
                """
                INSERT INTO document_sources(document_id,source_kind,source_ref,source_url)
                VALUES(?,?,?,?)
                """,
                (dst_id, kind, ref, url),
            )


def rebuild_books(db):
    db.execute("DELETE FROM books")
    groups = defaultdict(list)
    excluded = re.compile(r"近期|记录|书单|推荐|求书|合集|杂谈|吐槽")
    for row in db.execute(
        """
        SELECT id,title,mentioned_books_json,word,published_at,hot_score,source_type
          FROM documents
        """
    ):
        doc_id, title, mentioned_json, word, published_at, hot_score, source_type = row
        candidates = set()
        try:
            candidates.update(json.loads(mentioned_json or "[]"))
        except Exception:
            pass
        if title not in {"无", "未命名内容"} and not excluded.search(title):
            candidates.add(title)
        for candidate in candidates:
            candidate = html.unescape(re.sub(r"<[^>]+>", "", candidate or "")).strip("《》 ")
            if 2 <= len(candidate) <= 80:
                groups[compact(candidate)].append(
                    (doc_id, candidate, word or 0, published_at or "", hot_score or 0, source_type)
                )
    for title_norm, members in groups.items():
        best = max(members, key=lambda item: (item[2], item[3], item[4]))
        db.execute(
            """
            INSERT INTO books(title_norm,title,review_count,best_document_id,latest_at,sources_json)
            VALUES(?,?,?,?,?,?)
            """,
            (
                title_norm,
                min(item[1] for item in members),
                len({item[0] for item in members}),
                best[0],
                max(item[3] for item in members),
                json.dumps(sorted({item[5] for item in members if item[5]}), ensure_ascii=False),
            ),
        )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--threshold", type=float, default=0.995)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    threshold = max(0.0, min(1.0, args.threshold))
    db = sqlite3.connect(DB_PATH)
    records, pairs, groups = find_duplicate_groups(db, threshold)
    removed = []
    has_search_index = db.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='search_idx' LIMIT 1"
    ).fetchone() is not None
    if not args.apply:
        report = {
            "similarity_threshold": threshold,
            "duplicate_groups": len(groups),
            "removed_documents": sum(len(group) - 1 for group in groups),
            "applied": False,
        }
        REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
        REPORT_PATH.write_text(
            json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(json.dumps(report, ensure_ascii=False, indent=2))
        db.close()
        return
    db.execute("BEGIN")
    try:
        for members in groups:
            eligible = [records[item] for item in members]
            keeper = max(
                eligible,
                key=lambda item: (
                    item["source_count"],
                    item["word"],
                    item["published_at"],
                    item["hot_score"],
                    -item["id"],
                ),
            )
            for duplicate in sorted(eligible, key=lambda item: item["id"]):
                if duplicate["id"] == keeper["id"]:
                    continue
                merge_sources(db, duplicate["id"], keeper["id"])
                db.execute("DELETE FROM document_sources WHERE document_id=?", (duplicate["id"],))
                if has_search_index:
                    db.execute("DELETE FROM search_idx WHERE rowid=?", (duplicate["id"],))
                db.execute("DELETE FROM documents WHERE id=?", (duplicate["id"],))
                removed.append(
                    {
                        "removed_id": duplicate["id"],
                        "kept_id": keeper["id"],
                        "title": duplicate["title"],
                        "similarity": pairs.get(
                            tuple(sorted((duplicate["id"], keeper["id"]))), 1.0
                        ),
                    }
                )
        rebuild_books(db)
        category_counts = db.execute(
            "SELECT category,count(*) FROM documents GROUP BY category"
        ).fetchall()
        db.execute("DELETE FROM categories")
        db.executemany("INSERT INTO categories(name,count) VALUES(?,?)", category_counts)
        document_count = db.execute("SELECT count(*) FROM documents").fetchone()[0]
        book_count = db.execute("SELECT count(*) FROM books").fetchone()[0]
        source_count = db.execute("SELECT count(*) FROM document_sources").fetchone()[0]
        for key, value in (
            ("documents", document_count),
            ("books", book_count),
            ("source_rows", source_count),
            ("removed_duplicates", len(removed)),
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
    report = {
        "similarity_threshold": threshold,
        "duplicate_groups": len(groups),
        "removed_documents": len(removed),
        "remaining_documents": document_count,
        "remaining_books": book_count,
        "remaining_sources": source_count,
        "integrity": integrity,
        "applied": True,
        "removed": removed,
    }
    REPORT_PATH.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items() if key != "removed"},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
