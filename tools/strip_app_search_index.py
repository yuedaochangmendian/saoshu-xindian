import json
import sqlite3
from pathlib import Path


DB_PATH = Path(__file__).resolve().parents[1] / "app" / "src" / "main" / "assets" / "saoshu.db"


def main():
    db = sqlite3.connect(DB_PATH)
    db.executescript(
        """
        DROP TABLE IF EXISTS search_idx;
        VACUUM;
        PRAGMA optimize;
        """
    )
    integrity = db.execute("PRAGMA integrity_check").fetchone()[0]
    documents = db.execute("SELECT count(*) FROM documents").fetchone()[0]
    books = db.execute("SELECT count(*) FROM books").fetchone()[0]
    sources = db.execute("SELECT count(*) FROM document_sources").fetchone()[0]
    db.close()
    print(json.dumps({
        "bytes": DB_PATH.stat().st_size,
        "documents": documents,
        "books": books,
        "sources": sources,
        "integrity": integrity,
        "search_index": "created locally on first launch",
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
