"""Data storage for English Pal.

All database access lives here so the rest of the app never touches SQL
directly. Today this is a local SQLite file; swapping to hosted Postgres
later means changing only this one file (mainly get_conn + the "?" markers).

Data is keyed by an anonymous device_id sent by the app.
"""

import json
import secrets
import sqlite3
from datetime import datetime
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
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS users (
            user_id           INTEGER PRIMARY KEY AUTOINCREMENT,
            email             TEXT UNIQUE NOT NULL,
            password_hash     TEXT NOT NULL,
            username          TEXT UNIQUE NOT NULL,
            display_name      TEXT,
            partner_view_pref INTEGER DEFAULT 1,
            created_at        TEXT
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS sessions (
            token      TEXT PRIMARY KEY,
            user_id    INTEGER NOT NULL,
            created_at TEXT
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS friendships (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            requester_id INTEGER NOT NULL,
            addressee_id INTEGER NOT NULL,
            status       TEXT NOT NULL,   -- 'pending' or 'accepted'
            created_at   TEXT
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS conversations (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            user_low   INTEGER NOT NULL,   -- the smaller user_id of the pair
            user_high  INTEGER NOT NULL,   -- the larger user_id of the pair
            created_at TEXT
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS messages (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            conversation_id INTEGER NOT NULL,
            sender_id       INTEGER NOT NULL,
            text            TEXT NOT NULL,
            created_at      TEXT
        )
        """
    )
    # Add the correction columns to messages (works for both fresh and older
    # databases — ALTER TABLE only runs for columns that don't exist yet).
    msg_cols = [r["name"]
                for r in conn.execute("PRAGMA table_info(messages)").fetchall()]
    for col, ddl in (("corrected", "TEXT DEFAULT ''"),
                     ("why", "TEXT DEFAULT ''"),
                     ("understood", "INTEGER DEFAULT 1"),
                     ("sender_pref", "INTEGER DEFAULT 1")):
        if col not in msg_cols:
            conn.execute(f"ALTER TABLE messages ADD COLUMN {col} {ddl}")
    # ---- group chat ----
    # A group has 3+ participants and at most one AI robot. The robot's persona
    # (name + personality/hobbies/topics/level) is snapshotted onto the group as
    # JSON so it doesn't depend on any one device's profile.
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS groups (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            name         TEXT NOT NULL,
            owner_id     INTEGER NOT NULL,
            has_robot    INTEGER DEFAULT 0,
            robot_name   TEXT DEFAULT '',
            robot_config TEXT DEFAULT '',   -- JSON persona for the robot
            created_at   TEXT
        )
        """
    )
    # One row per (group, member). share_pref is this member's per-group choice
    # of what the others see of their messages (1 card / 2 corrected / 3 original).
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS group_members (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            group_id  INTEGER NOT NULL,
            user_id   INTEGER NOT NULL,
            share_pref INTEGER DEFAULT 1,
            joined_at TEXT
        )
        """
    )
    # Group messages mirror the 1-on-1 messages table, plus is_robot (a reply
    # from the group's AI) and the snapshotted sender share pref.
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS group_messages (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            group_id    INTEGER NOT NULL,
            sender_id   INTEGER NOT NULL,   -- 0 for the robot
            text        TEXT NOT NULL,
            corrected   TEXT DEFAULT '',
            why         TEXT DEFAULT '',
            understood  INTEGER DEFAULT 1,
            sender_pref INTEGER DEFAULT 1,
            is_robot    INTEGER DEFAULT 0,
            created_at  TEXT
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


# ---------- users (accounts for partner chat) ----------

def create_user(email, password_hash, username, display_name):
    conn = get_conn()
    cur = conn.execute(
        """
        INSERT INTO users (email, password_hash, username, display_name, created_at)
        VALUES (?, ?, ?, ?, ?)
        """,
        (email, password_hash, username, display_name,
         datetime.utcnow().isoformat()),
    )
    conn.commit()
    user_id = cur.lastrowid
    conn.close()
    return user_id


def get_user_by_email(email):
    conn = get_conn()
    row = conn.execute(
        "SELECT * FROM users WHERE email = ?", (email,)
    ).fetchone()
    conn.close()
    return dict(row) if row else None


def get_user_by_username(username):
    conn = get_conn()
    row = conn.execute(
        "SELECT * FROM users WHERE username = ?", (username,)
    ).fetchone()
    conn.close()
    return dict(row) if row else None


def get_user_by_id(user_id):
    conn = get_conn()
    row = conn.execute(
        "SELECT * FROM users WHERE user_id = ?", (user_id,)
    ).fetchone()
    conn.close()
    return dict(row) if row else None


def update_partner_view_pref(user_id, pref):
    """Set what this user's chat partners see of their messages (1/2/3)."""
    conn = get_conn()
    conn.execute(
        "UPDATE users SET partner_view_pref = ? WHERE user_id = ?",
        (pref, user_id),
    )
    conn.commit()
    conn.close()


# ---------- sessions (login tokens) ----------

def create_session(user_id):
    token = secrets.token_urlsafe(32)
    conn = get_conn()
    conn.execute(
        "INSERT INTO sessions (token, user_id, created_at) VALUES (?, ?, ?)",
        (token, user_id, datetime.utcnow().isoformat()),
    )
    conn.commit()
    conn.close()
    return token


def get_user_id_for_token(token):
    conn = get_conn()
    row = conn.execute(
        "SELECT user_id FROM sessions WHERE token = ?", (token,)
    ).fetchone()
    conn.close()
    return row["user_id"] if row else None


# ---------- friendships (partner chat) ----------

def get_friendship(user_a, user_b):
    """The friendship row between two users, in either direction (or None)."""
    conn = get_conn()
    row = conn.execute(
        """
        SELECT * FROM friendships
        WHERE (requester_id = ? AND addressee_id = ?)
           OR (requester_id = ? AND addressee_id = ?)
        """,
        (user_a, user_b, user_b, user_a),
    ).fetchone()
    conn.close()
    return dict(row) if row else None


def create_friend_request(requester_id, addressee_id):
    conn = get_conn()
    conn.execute(
        """
        INSERT INTO friendships (requester_id, addressee_id, status, created_at)
        VALUES (?, ?, 'pending', ?)
        """,
        (requester_id, addressee_id, datetime.utcnow().isoformat()),
    )
    conn.commit()
    conn.close()


def accept_friend_request(requester_id, addressee_id):
    conn = get_conn()
    conn.execute(
        """
        UPDATE friendships SET status = 'accepted'
        WHERE requester_id = ? AND addressee_id = ? AND status = 'pending'
        """,
        (requester_id, addressee_id),
    )
    conn.commit()
    conn.close()


def delete_friendship(user_a, user_b):
    conn = get_conn()
    conn.execute(
        """
        DELETE FROM friendships
        WHERE (requester_id = ? AND addressee_id = ?)
           OR (requester_id = ? AND addressee_id = ?)
        """,
        (user_a, user_b, user_b, user_a),
    )
    conn.commit()
    conn.close()


def list_friends(user_id):
    """Users this person is accepted friends with (either direction)."""
    conn = get_conn()
    rows = conn.execute(
        """
        SELECT u.* FROM friendships f
        JOIN users u ON u.user_id = CASE
            WHEN f.requester_id = ? THEN f.addressee_id
            ELSE f.requester_id END
        WHERE f.status = 'accepted'
          AND (f.requester_id = ? OR f.addressee_id = ?)
        ORDER BY u.username
        """,
        (user_id, user_id, user_id),
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def list_incoming_requests(user_id):
    """Users who sent this person a still-pending friend request."""
    conn = get_conn()
    rows = conn.execute(
        """
        SELECT u.* FROM friendships f
        JOIN users u ON u.user_id = f.requester_id
        WHERE f.addressee_id = ? AND f.status = 'pending'
        ORDER BY f.created_at DESC
        """,
        (user_id,),
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def search_users(query, exclude_user_id):
    conn = get_conn()
    rows = conn.execute(
        """
        SELECT * FROM users
        WHERE username LIKE ? AND user_id != ?
        ORDER BY username LIMIT 20
        """,
        (f"%{query}%", exclude_user_id),
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


# ---------- conversations & messages (partner chat) ----------

def get_or_create_conversation(user_a, user_b):
    """One conversation per pair — the id is stable whichever way round the two
    users are passed (we always store the smaller id in user_low)."""
    low, high = (user_a, user_b) if user_a < user_b else (user_b, user_a)
    conn = get_conn()
    row = conn.execute(
        "SELECT id FROM conversations WHERE user_low = ? AND user_high = ?",
        (low, high),
    ).fetchone()
    if row is None:
        cur = conn.execute(
            "INSERT INTO conversations (user_low, user_high, created_at) "
            "VALUES (?, ?, ?)",
            (low, high, datetime.utcnow().isoformat()),
        )
        conn.commit()
        conv_id = cur.lastrowid
    else:
        conv_id = row["id"]
    conn.close()
    return conv_id


def get_conversation(conversation_id):
    conn = get_conn()
    row = conn.execute(
        "SELECT * FROM conversations WHERE id = ?", (conversation_id,)
    ).fetchone()
    conn.close()
    return dict(row) if row else None


def find_conversation(user_a, user_b):
    """The conversation id for a pair if one already exists, else None (unlike
    get_or_create_conversation, this never creates one — used for listing)."""
    low, high = (user_a, user_b) if user_a < user_b else (user_b, user_a)
    conn = get_conn()
    row = conn.execute(
        "SELECT id FROM conversations WHERE user_low = ? AND user_high = ?",
        (low, high),
    ).fetchone()
    conn.close()
    return row["id"] if row else None


def get_last_message(conversation_id):
    """The most recent message in a conversation, or None if it has none."""
    conn = get_conn()
    row = conn.execute(
        "SELECT * FROM messages WHERE conversation_id = ? "
        "ORDER BY id DESC LIMIT 1",
        (conversation_id,),
    ).fetchone()
    conn.close()
    return _message_row(row) if row else None


def add_message(conversation_id, sender_id, text, corrected="", why="",
                understood=True, sender_pref=1):
    conn = get_conn()
    created = datetime.utcnow().isoformat()
    cur = conn.execute(
        "INSERT INTO messages (conversation_id, sender_id, text, corrected, "
        "why, understood, sender_pref, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (conversation_id, sender_id, text, corrected, why,
         1 if understood else 0, sender_pref, created),
    )
    conn.commit()
    msg_id = cur.lastrowid
    conn.close()
    return {"id": msg_id, "senderId": sender_id, "text": text,
            "corrected": corrected, "why": why, "understood": understood,
            "senderPref": sender_pref, "createdAt": created}


def _message_row(r):
    return {
        "id": r["id"],
        "senderId": r["sender_id"],
        "text": r["text"],
        "corrected": r["corrected"] or "",
        "why": r["why"] or "",
        "understood": bool(r["understood"]) if r["understood"] is not None
        else True,
        "senderPref": r["sender_pref"] if r["sender_pref"] is not None else 1,
        "createdAt": r["created_at"],
    }


def get_messages(conversation_id, since_id=0):
    """Messages in a conversation with id greater than since_id (0 = all)."""
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM messages WHERE conversation_id = ? AND id > ? "
        "ORDER BY id",
        (conversation_id, since_id),
    ).fetchall()
    conn.close()
    return [_message_row(r) for r in rows]


# ---------- groups (group chat) ----------

def create_group(name, owner_id, has_robot, robot_name, robot_config):
    conn = get_conn()
    cur = conn.execute(
        "INSERT INTO groups (name, owner_id, has_robot, robot_name, "
        "robot_config, created_at) VALUES (?, ?, ?, ?, ?, ?)",
        (name, owner_id, 1 if has_robot else 0, robot_name or "",
         json.dumps(robot_config or {}), datetime.utcnow().isoformat()),
    )
    conn.commit()
    group_id = cur.lastrowid
    conn.close()
    return group_id


def get_group(group_id):
    conn = get_conn()
    row = conn.execute(
        "SELECT * FROM groups WHERE id = ?", (group_id,)
    ).fetchone()
    conn.close()
    if row is None:
        return None
    g = dict(row)
    g["robot_config"] = json.loads(g["robot_config"]) if g["robot_config"] \
        else {}
    return g


def add_group_member(group_id, user_id, share_pref=1):
    conn = get_conn()
    conn.execute(
        "INSERT INTO group_members (group_id, user_id, share_pref, joined_at) "
        "VALUES (?, ?, ?, ?)",
        (group_id, user_id, share_pref, datetime.utcnow().isoformat()),
    )
    conn.commit()
    conn.close()


def is_group_member(group_id, user_id):
    conn = get_conn()
    row = conn.execute(
        "SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?",
        (group_id, user_id),
    ).fetchone()
    conn.close()
    return row is not None


def get_group_share_pref(group_id, user_id):
    """This member's per-group share preference (defaults to 1)."""
    conn = get_conn()
    row = conn.execute(
        "SELECT share_pref FROM group_members WHERE group_id = ? "
        "AND user_id = ?",
        (group_id, user_id),
    ).fetchone()
    conn.close()
    return (row["share_pref"] if row and row["share_pref"] is not None else 1)


def update_group_share_pref(group_id, user_id, pref):
    conn = get_conn()
    conn.execute(
        "UPDATE group_members SET share_pref = ? WHERE group_id = ? "
        "AND user_id = ?",
        (pref, group_id, user_id),
    )
    conn.commit()
    conn.close()


def list_group_members(group_id):
    """The human members of a group (user rows), joined-order."""
    conn = get_conn()
    rows = conn.execute(
        """
        SELECT u.*, gm.share_pref FROM group_members gm
        JOIN users u ON u.user_id = gm.user_id
        WHERE gm.group_id = ?
        ORDER BY gm.id
        """,
        (group_id,),
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def list_user_groups(user_id):
    """Groups this user belongs to, most recently active first."""
    conn = get_conn()
    rows = conn.execute(
        """
        SELECT g.* FROM groups g
        JOIN group_members gm ON gm.group_id = g.id
        WHERE gm.user_id = ?
        """,
        (user_id,),
    ).fetchall()
    conn.close()
    result = []
    for r in rows:
        g = dict(r)
        g["robot_config"] = json.loads(g["robot_config"]) \
            if g["robot_config"] else {}
        result.append(g)
    return result


def add_group_message(group_id, sender_id, text, corrected="", why="",
                      understood=True, sender_pref=1, is_robot=False):
    conn = get_conn()
    created = datetime.utcnow().isoformat()
    cur = conn.execute(
        "INSERT INTO group_messages (group_id, sender_id, text, corrected, "
        "why, understood, sender_pref, is_robot, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (group_id, sender_id, text, corrected, why,
         1 if understood else 0, sender_pref, 1 if is_robot else 0, created),
    )
    conn.commit()
    msg_id = cur.lastrowid
    conn.close()
    return {"id": msg_id, "groupId": group_id, "senderId": sender_id,
            "text": text, "corrected": corrected, "why": why,
            "understood": understood, "senderPref": sender_pref,
            "isRobot": is_robot, "createdAt": created}


def _group_message_row(r):
    return {
        "id": r["id"],
        "groupId": r["group_id"],
        "senderId": r["sender_id"],
        "text": r["text"],
        "corrected": r["corrected"] or "",
        "why": r["why"] or "",
        "understood": bool(r["understood"]) if r["understood"] is not None
        else True,
        "senderPref": r["sender_pref"] if r["sender_pref"] is not None else 1,
        "isRobot": bool(r["is_robot"]),
        "createdAt": r["created_at"],
    }


def get_group_messages(group_id, since_id=0):
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM group_messages WHERE group_id = ? AND id > ? "
        "ORDER BY id",
        (group_id, since_id),
    ).fetchall()
    conn.close()
    return [_group_message_row(r) for r in rows]


def get_group_last_message(group_id):
    conn = get_conn()
    row = conn.execute(
        "SELECT * FROM group_messages WHERE group_id = ? ORDER BY id DESC "
        "LIMIT 1",
        (group_id,),
    ).fetchone()
    conn.close()
    return _group_message_row(row) if row else None


def get_group_recent(group_id, limit=10):
    """The last `limit` messages (chronological) — context for a robot reply."""
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM group_messages WHERE group_id = ? ORDER BY id DESC "
        "LIMIT ?",
        (group_id, limit),
    ).fetchall()
    conn.close()
    return [_group_message_row(r) for r in reversed(rows)]
