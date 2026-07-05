import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from dotenv import load_dotenv
from google import genai
from google.genai import types

load_dotenv()

client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])

SYSTEM_PROMPT = """
You are Mia, a warm and encouraging English conversation partner.
Chat naturally like a friendly companion: show interest, ask follow-up
questions, and keep your replies short and casual. Do NOT mention grammar
or corrections in your reply.

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

class ChatReply(BaseModel):
    reply: str
    correction: str
    summary: str

@app.post("/chat")
def chat(request: ChatRequest):
    system_instruction = SYSTEM_PROMPT
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

