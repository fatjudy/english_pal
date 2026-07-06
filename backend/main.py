import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from dotenv import load_dotenv
from google import genai
from google.genai import types

import db

load_dotenv()
db.init_db()

client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])

SYSTEM_PROMPT = """
IMPORTANT SAFETY RULES:
You are chatting with an adult English learner. If the user brings up sexual
content, graphic violence, ways to harm themselves or others, illegal or
dangerous instructions, hate speech, or extremism, do NOT engage with it.
Warmly and briefly decline (one short sentence), then gently steer the
conversation back to a friendly, safe topic. Never lecture.
You may talk about sensitive subjects like news, history, or health in a
factual, gentle way — but never in a graphic, glorifying, or how-to way.

If the user seems genuinely upset, in crisis, or mentions self-harm, abuse, or
being in danger, do not brush them off. Warmly acknowledge how they feel, and
gently encourage them to reach out to someone they trust, a local crisis
helpline, or emergency services. Be human and caring first. Never provide
harmful methods.

Even when you decline, stay fully in character as your friendly persona, in a
warm and natural voice. Do NOT sound like a generic AI assistant or say things
like "my purpose is to be helpful and harmless." Simply decline kindly in one
sentence and gently steer back to a friendly topic. Only bring up crisis help
or hotlines if the user actually seems distressed or in danger — not for every
sensitive request.

The user is practicing English. Separately, look at the user's message:

- If it has any English mistakes, put a corrected version in the "correction"
  field, written in the USER'S OWN voice — exactly as if the user said it
  correctly themselves. Keep the same meaning, the same point of view, and the
  same names and pronouns: keep "I" as "I", and keep any name the user
  mentions exactly as-is (don't turn a person's name into "your friend ...").
  Keep the same sentence type — a statement stays a statement, not a question.
  Ignore punctuation and capitalization — do not add or change them (for
  example, don't add a question mark or a period). If the only change you
  would make is punctuation or capitalization, treat the message as already
  correct and set "correction" to an empty string.
  Make it sound natural and casual, but only fix the English; do not reply to
  it, answer it, or add new ideas.
- If the message is already correct, set "correction" to an empty string.
Also keep a running summary of the conversation as your long-term memory. In
the "summary" field, write an updated summary that combines the earlier summary
(if one is provided) with any important new details from this exchange — names,
topics, preferences, and key facts worth remembering. Keep it short, just a few
sentences.
"""

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class Message(BaseModel):
    role: str
    text: str

class ChatRequest(BaseModel):
    messages: list[Message]
    summary: str = ""
    palName: str = "Mia"
    personality: list[str] = []
    hobbies: list[str] = []
    topics: list[str] = []
    level: str = "Intermediate"

class ChatReply(BaseModel):
    reply: str
    correction: str
    summary: str

def build_system_prompt(request: ChatRequest) -> str:
    name = request.palName or "Mia"
    personality = ", ".join(request.personality) or "warm and friendly"
    hobbies = ", ".join(request.hobbies) or "lots of things"
    topics = ", ".join(request.topics) or "everyday life"
    intro = f"""
You are {name}, a friendly English conversation partner.
Your personality is: {personality}.
Your hobbies and interests: {hobbies}.
The user enjoys talking about: {topics}.
Chat naturally and warmly, matching this personality. Keep your replies short and
casual. Do NOT mention grammar or corrections in your reply.

The user's English level is "{request.level}". Match your vocabulary and sentence
length to this level (simpler for Beginner, richer for Advanced).
"""
    return intro + SYSTEM_PROMPT

@app.post("/chat")
def chat(request: ChatRequest):
    system_instruction = build_system_prompt(request)
    if request.summary:
        system_instruction += (
            "\n\nSummary of the earlier conversation (for context):\n"
            + request.summary
        )
    try:
        response = client.models.generate_content(
            model="gemini-2.5-flash-lite",
            contents=[
                {"role": m.role, "parts": [{"text": m.text}]}
                for m in request.messages
            ],
            config=types.GenerateContentConfig(
                system_instruction=system_instruction,
                response_mime_type="application/json",
                response_schema=ChatReply,
            ),
        )
        return {
            "reply": response.parsed.reply,
            "correction": response.parsed.correction,
            "summary": response.parsed.summary,
        }
    except Exception as e:
        print("Gemini error:", e)
        return {
            "reply": "Sorry, I'm a bit busy right now — please try again in a moment!",
            "correction": "",
            "summary": request.summary,
        }

class OpenerRequest(BaseModel):
    topic: str
    palName: str = "Mia"
    personality: list[str] = []
    hobbies: list[str] = []
    topics: list[str] = []
    level: str = "Intermediate"

@app.post("/opener")
def opener(request: OpenerRequest):
    name = request.palName or "Mia"
    personality = ", ".join(request.personality) or "warm and friendly"
    hobbies = ", ".join(request.hobbies) or "lots of things"
    interests = ", ".join(request.topics)
    topic = request.topic or "anything"
    if topic.lower() in ("surprise me", "anything", ""):
        if interests:
            topic_line = (
                f"Pick ONE specific topic to talk about — choose from your friend's "
                f"favourite topics ({interests}) or from your own hobbies ({hobbies}). "
                f"Don't ask what they want to talk about; jump straight into that one topic."
            )
        else:
            topic_line = (
                f"Pick ONE specific topic to talk about — something from your own hobbies "
                f"({hobbies}) or something popular right now. Don't ask what they want to "
                f"talk about; jump straight into that one topic."
            )
    else:
        topic_line = f'Start a conversation about "{topic}".'
    instruction = f"""
You are {name}, a friendly English conversation partner. Your personality:
{personality}. You are into: {hobbies}.

Text your friend a short, warm opening message, out of the blue, like a friend
texting. {topic_line} Share something you like or something popular or current.
Use real, specific examples — never use placeholders like "[insert ...]".
Be natural and casual, just 1-2 sentences, at an English level of
"{request.level}". Return ONLY the message text.
"""
    try:
        response = client.models.generate_content(
            model="gemini-2.5-flash-lite",
            contents=instruction,
        )
        return {"message": response.text.strip()}
    except Exception as e:
        print("Opener error:", e)
        if topic.lower() in ("surprise me", "anything", ""):
            return {"message": "Hey! Got a minute to chat?"}
        return {"message": f"Hey! Want to chat about {topic}?"}


# ---------- cloud storage (keyed by anonymous device_id) ----------

class ProfileSave(BaseModel):
    deviceId: str
    palName: str = "Mia"
    personality: list[str] = []
    hobbies: list[str] = []
    topics: list[str] = []
    level: str = "Intermediate"

class ChatSave(BaseModel):
    deviceId: str
    messages: list = []
    summary: str = ""

class DeviceRequest(BaseModel):
    deviceId: str


@app.post("/profile/save")
def profile_save(request: ProfileSave):
    db.save_profile(
        request.deviceId,
        request.palName,
        request.personality,
        request.hobbies,
        request.topics,
        request.level,
    )
    return {"ok": True}


@app.post("/profile/load")
def profile_load(request: DeviceRequest):
    profile = db.load_profile(request.deviceId)
    return {"profile": profile}


@app.post("/chat/save")
def chat_save(request: ChatSave):
    db.save_chat(request.deviceId, request.messages, request.summary)
    return {"ok": True}


@app.post("/chat/load")
def chat_load(request: DeviceRequest):
    chat = db.load_chat(request.deviceId)
    return {"chat": chat}