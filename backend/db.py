"""Data storage for English Pal.

All database access lives here so the rest of the app never touches SQL
directly. Today this is a local SQLite file; swapping to hosted Postgres
later means changing only this one file (mainly get_conn + the "?" markers).

Data is keyed by an anonymous device_id sent by the app.
"""

import json
import sqlite3
from pathlib import Path

DB_PATH = Path(__file__).parent / "english_pal.db"


def get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row  # rows behave like dicts
    return conn


def init_db():
    """Create the tables once, on server startup, if they don't exist yet."""
    conn = get_conn()
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS profiles (
            device_id   TEXT PRIMARY KEY,
            pal_name    TEXT,
            personality TEXT,
            hobbies     TEXT,
            topics      TEXT,
            level       TEXT
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS chats (
            device_id TEXT PRIMARY KEY,
            messages  TEXT,
            summary   TEXT
        )
        """
    )
    conn.commit()
    conn.close()


# ---------- profile (setup / settings) ----------

def save_profile(device_id, pal_name, personality, hobbies, topics, level):
    conn = get_conn()
    conn.execute(
        """
        INSERT INTO profiles (device_id, pal_name, personality, hobbies, topics, level)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(device_id) DO UPDATE SET
            pal_name    = excluded.pal_name,
            personality = excluded.personality,
            hobbies     = excluded.hobbies,
            topics      = excluded.topics,
            level       = excluded.level
        """,
        (
            device_id,
            pal_name,
            json.dumps(personality),
            json.dumps(hobbies),
            json.dumps(topics),
            level,
        ),
    )
    conn.commit()
    conn.close()


def load_profile(device_id):
    conn = get_conn()
    row = conn.execute(
        "SELECT * FROM profiles WHERE device_id = ?", (device_id,)
    ).fetchone()
    conn.close()
    if row is None:
        return None
    return {
        "palName": row["pal_name"],
        "personality": json.loads(row["personality"]),
        "hobbies": json.loads(row["hobbies"]),
        "topics": json.loads(row["topics"]),
        "level": row["level"],
    }


# ---------- chat (messages + running summary) ----------

def save_chat(device_id, messages, summary):
    conn = get_conn()
    conn.execute(
        """
        INSERT INTO chats (device_id, messages, summary)
        VALUES (?, ?, ?)
        ON CONFLICT(device_id) DO UPDATE SET
            messages = excluded.messages,
            summary  = excluded.summary
        """,
        (device_id, json.dumps(messages), summary),
    )
    conn.commit()
    conn.close()


def load_chat(device_id):
    conn = get_conn()
    row = conn.execute(
        "SELECT * FROM chats WHERE device_id = ?", (device_id,)
    ).fetchone()
    conn.close()
    if row is None:
        return None
    return {
        "messages": json.loads(row["messages"]),
        "summary": row["summary"] or "",
    }
